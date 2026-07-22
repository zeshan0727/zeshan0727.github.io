#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sqlite3.h>
#import <signal.h>
#import <unistd.h>
#import "NMCore.h"

static char NMConversationTableKey;
static NSMutableDictionary<NSString *, NSValue *> *NMOriginalSwipeIMPs;

static id NMSafeValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static void NMCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) NMCollectLabels(subview, labels);
}

static id NMConversationModelForCell(UITableViewCell *cell) {
    for (NSString *key in @[@"conversation", @"_conversation", @"chat", @"_chat",
                            @"conversationListItem", @"_conversationListItem",
                            @"model", @"_model"]) {
        id model = NMSafeValue(cell, key);
        if (model) return model;
    }
    return nil;
}

static NSArray<NSString *> *NMCandidatesForCell(UITableViewCell *cell) {
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet orderedSet];

    id model = NMConversationModelForCell(cell);
    for (NSString *modelKey in @[@"chatIdentifier", @"displayName", @"name",
                                 @"guid", @"identifier", @"recipientAddress",
                                 @"address", @"serviceName"]) {
        id value = NMSafeValue(model, modelKey);
        if ([value isKindOfClass:NSString.class] && [value length]) {
            [values addObject:value];
        }
    }

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(cell.contentView, labels);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ay = CGRectGetMinY(a.frame);
        CGFloat by = CGRectGetMinY(b.frame);
        if (ay < by) return NSOrderedAscending;
        if (ay > by) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (UILabel *label in labels) {
        NSString *text =
            [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 1 && text.length < 180) [values addObject:text];
    }
    return values.array;
}

static NSDate *NMDateFromNumericValue(NSNumber *number) {
    if (![number isKindOfClass:NSNumber.class]) return nil;
    double raw = number.doubleValue;
    if (raw <= 0) return nil;
    if (raw > 1000000000000.0) raw /= 1000000000.0;
    if (raw > 1300000000.0) return [NSDate dateWithTimeIntervalSince1970:raw];
    return [NSDate dateWithTimeIntervalSince1970:(raw + 978307200.0)];
}

static BOOL NMQueryDatabaseStats(NSArray<NSString *> *candidates,
                                 NSInteger *messageCount,
                                 NSDate **firstDate,
                                 NSString **resolvedIdentifier) {
    sqlite3 *database = NULL;
    const char *paths[] = {
        "/private/var/mobile/Library/SMS/sms.db",
        "/var/mobile/Library/SMS/sms.db"
    };
    for (NSUInteger index = 0; index < 2 && !database; index++) {
        if (sqlite3_open_v2(paths[index], &database, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
            if (database) sqlite3_close(database);
            database = NULL;
        }
    }
    if (!database) return NO;

    const char *sql =
        "SELECT COUNT(cmj.message_id), MIN(m.date), "
        "COALESCE(c.chat_identifier, c.guid, c.display_name) "
        "FROM chat c "
        "LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID "
        "LEFT JOIN message m ON m.ROWID = cmj.message_id "
        "WHERE lower(c.chat_identifier)=lower(?) "
        "OR lower(c.guid)=lower(?) "
        "OR lower(c.display_name)=lower(?) "
        "GROUP BY c.ROWID ORDER BY MAX(m.date) DESC LIMIT 1";

    BOOL found = NO;
    for (NSString *candidate in candidates) {
        if (candidate.length < 2) continue;
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) continue;
        const char *utf8 = candidate.UTF8String;
        sqlite3_bind_text(statement, 1, utf8, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 2, utf8, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, utf8, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(statement) == SQLITE_ROW) {
            if (messageCount) *messageCount = sqlite3_column_int64(statement, 0);
            if (firstDate && sqlite3_column_type(statement, 1) != SQLITE_NULL) {
                *firstDate = NMDateFromNumericValue(@(sqlite3_column_int64(statement, 1)));
            }
            if (resolvedIdentifier && sqlite3_column_type(statement, 2) != SQLITE_NULL) {
                const unsigned char *text = sqlite3_column_text(statement, 2);
                if (text) *resolvedIdentifier = [NSString stringWithUTF8String:(const char *)text];
            }
            found = YES;
        }
        sqlite3_finalize(statement);
        if (found) break;
    }
    sqlite3_close(database);
    return found;
}

static NSInteger NMFallbackMessageCount(id model) {
    for (NSString *key in @[@"messageCount", @"messagesCount", @"numberOfMessages", @"unreadCount"]) {
        id value = NMSafeValue(model, key);
        if ([value respondsToSelector:@selector(integerValue)]) {
            NSInteger count = [value integerValue];
            if (count >= 0) return count;
        }
    }
    for (NSString *key in @[@"messages", @"allMessages", @"transcriptItems", @"items"]) {
        id value = NMSafeValue(model, key);
        if ([value respondsToSelector:@selector(count)]) return [value count];
    }
    return NSNotFound;
}

static NSDate *NMFallbackFirstDate(id model) {
    for (NSString *key in @[@"firstMessageDate", @"dateOfFirstMessage",
                            @"creationDate", @"startDate", @"date"]) {
        id value = NMSafeValue(model, key);
        if ([value isKindOfClass:NSDate.class]) return value;
        if ([value isKindOfClass:NSNumber.class]) return NMDateFromNumericValue(value);
    }
    return nil;
}

static NSString *NMReadableDate(NSDate *date) {
    if (!date) return @"Not available";
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterLongStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return [formatter stringFromDate:date] ?: @"Not available";
}

@interface NMConversationDetailsController : UIViewController
@property(nonatomic,copy) NSString *conversationTitle;
@property(nonatomic,copy) NSString *identifierText;
@property(nonatomic,copy) NSString *messageCountText;
@property(nonatomic,copy) NSString *firstDateText;
@property(nonatomic,copy) dispatch_block_t deleteHandler;
@property(nonatomic) BOOL allowDelete;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *identifierLabel;
@property(nonatomic,strong) UILabel *countValue;
@property(nonatomic,strong) UILabel *dateValue;
@property(nonatomic,strong) UIButton *deleteButton;
@property(nonatomic,strong) UIButton *closeButton;
@end

@implementation NMConversationDetailsController

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)statCardWithIcon:(NSString *)icon
                       title:(NSString *)title
                       value:(NSString *)value
                      accent:(UIColor *)accent
                  valueLabel:(UILabel **)valueLabel {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = NMColor(0x17233E, 0.96);
    view.layer.cornerRadius = 20;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 0.8;
    view.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;

    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    image.tintColor = accent;
    image.contentMode = UIViewContentModeScaleAspectFit;
    image.frame = CGRectMake(16, 18, 28, 28);
    [view addSubview:image];

    UILabel *caption = [self labelWithFont:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]
                                    color:NMColor(0xAEBBD5, 1)];
    caption.text = title.uppercaseString;
    caption.frame = CGRectMake(56, 13, 220, 20);
    [view addSubview:caption];

    UILabel *valueView = [self labelWithFont:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]
                                      color:UIColor.whiteColor];
    valueView.text = value;
    valueView.frame = CGRectMake(56, 34, 245, 48);
    [view addSubview:valueView];
    if (valueLabel) *valueLabel = valueView;
    return view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:effect];
    blur.frame = self.view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blur];

    self.card = [[UIView alloc] init];
    self.card.backgroundColor = NMColor(0x0B1327, 0.99);
    self.card.layer.cornerRadius = 30;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = NMColor(0x7182AA, 0.32).CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = 0.5;
    self.card.layer.shadowRadius = 30;
    self.card.layer.shadowOffset = CGSizeMake(0, 14);
    [self.view addSubview:self.card];

    CAGradientLayer *strip = [CAGradientLayer layer];
    strip.name = @"NMDetailsStrip";
    strip.colors = @[(id)NMColor(0xFF5B61,1).CGColor,
                     (id)NMColor(0x6F63FF,1).CGColor,
                     (id)NMColor(0x18C8B7,1).CGColor];
    strip.startPoint = CGPointMake(0,0.5);
    strip.endPoint = CGPointMake(1,0.5);
    strip.cornerRadius = 3;
    [self.card.layer addSublayer:strip];

    UILabel *eyebrow = [self labelWithFont:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]
                                    color:NMColor(0x64DCCB,1)];
    eyebrow.text = @"CONVERSATION DETAILS";
    eyebrow.frame = CGRectMake(24, 38, 260, 18);
    [self.card addSubview:eyebrow];

    self.titleLabel = [self labelWithFont:[UIFont systemFontOfSize:27 weight:UIFontWeightBold]
                                   color:UIColor.whiteColor];
    self.titleLabel.text = self.conversationTitle.length ? self.conversationTitle : @"Conversation";
    [self.card addSubview:self.titleLabel];

    self.identifierLabel = [self labelWithFont:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
                                        color:NMColor(0xAEBBD5,1)];
    self.identifierLabel.text = self.identifierText.length ? self.identifierText : @"Messages conversation";
    [self.card addSubview:self.identifierLabel];

    UIView *countCard = [self statCardWithIcon:@"number.circle.fill"
                                         title:@"Messages"
                                         value:self.messageCountText ?: @"Not available"
                                        accent:NMColor(0x6F63FF,1)
                                    valueLabel:&_countValue];
    countCard.tag = 730001;
    [self.card addSubview:countCard];

    UIView *dateCard = [self statCardWithIcon:@"calendar.badge.clock"
                                        title:@"First message"
                                        value:self.firstDateText ?: @"Not available"
                                       accent:NMColor(0x18C8B7,1)
                                   valueLabel:&_dateValue];
    dateCard.tag = 730002;
    [self.card addSubview:dateCard];

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.deleteButton setTitle:@"Delete Conversation" forState:UIControlStateNormal];
    [self.deleteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.deleteButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.deleteButton.backgroundColor = NMColor(0xE93856,1);
    self.deleteButton.layer.cornerRadius = 18;
    self.deleteButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.deleteButton addTarget:self action:@selector(deleteTapped)
                forControlEvents:UIControlEventTouchUpInside];
    self.deleteButton.hidden = !self.allowDelete;
    [self.card addSubview:self.deleteButton];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.closeButton.backgroundColor = NMColor(0x273450,1);
    self.closeButton.layer.cornerRadius = 18;
    self.closeButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.closeButton addTarget:self action:@selector(closeTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:self.closeButton];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (NMPreferenceBool(@"animations", YES)) {
        self.card.transform = CGAffineTransformMakeScale(0.86, 0.86);
        self.card.alpha = 0;
        [UIView animateWithDuration:0.34
                             delay:0
            usingSpringWithDamping:0.78
             initialSpringVelocity:0
                           options:UIViewAnimationOptionBeginFromCurrentState
                        animations:^{
            self.card.transform = CGAffineTransformIdentity;
            self.card.alpha = 1;
        } completion:nil];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = MIN(CGRectGetWidth(self.view.bounds) - 28, 410);
    CGFloat height = 500;
    self.card.frame = CGRectMake((CGRectGetWidth(self.view.bounds)-width)/2,
                                 (CGRectGetHeight(self.view.bounds)-height)/2,
                                 width, height);
    for (CALayer *layer in self.card.layer.sublayers) {
        if ([layer.name isEqualToString:@"NMDetailsStrip"]) {
            layer.frame = CGRectMake(24, 20, width-48, 6);
        }
    }
    self.titleLabel.frame = CGRectMake(24, 64, width-48, 66);
    self.identifierLabel.frame = CGRectMake(24, 124, width-48, 38);
    [self.card viewWithTag:730001].frame = CGRectMake(24, 176, width-48, 92);
    [self.card viewWithTag:730002].frame = CGRectMake(24, 280, width-48, 92);
    self.deleteButton.frame = CGRectMake(24, 390, width-48, 54);
    self.closeButton.frame = CGRectMake(24, 452, width-48, 38);
}

- (void)deleteTapped {
    NMHaptic(YES);
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Delete Conversation?"
                                            message:@"This permanently removes the complete conversation from Messages."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *action) {
        if (weakSelf.deleteHandler) weakSelf.deleteHandler();
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTapped {
    NMHaptic(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

static void NMInvokeNativeDelete(UIContextualAction *action,
                                 id delegate,
                                 UITableView *tableView,
                                 NSIndexPath *indexPath) {
    if (action) {
        id handlerObject = NMSafeValue(action, @"handler") ?: NMSafeValue(action, @"_handler");
        if (handlerObject) {
            void (^handler)(UIContextualAction *, UIView *, void (^)(BOOL)) = handlerObject;
            handler(action, nil, ^(__unused BOOL success) {});
            return;
        }
    }

    SEL selector = @selector(tableView:commitEditingStyle:forRowAtIndexPath:);
    if ([delegate respondsToSelector:selector]) {
        typedef void (*CommitFunction)(id, SEL, UITableView *, UITableViewCellEditingStyle, NSIndexPath *);
        ((CommitFunction)objc_msgSend)(delegate, selector, tableView,
                                      UITableViewCellEditingStyleDelete, indexPath);
        return;
    }

    UIViewController *controller = NMControllerForView(tableView);
    for (NSString *name in @[@"_deleteConversationAtIndexPath:",
                             @"deleteConversationAtIndexPath:",
                             @"removeConversationAtIndexPath:"]) {
        SEL privateSelector = NSSelectorFromString(name);
        if ([controller respondsToSelector:privateSelector]) {
            typedef void (*IndexFunction)(id, SEL, NSIndexPath *);
            ((IndexFunction)objc_msgSend)(controller, privateSelector, indexPath);
            return;
        }
    }
}

static void NMPresentDetails(UITableView *tableView,
                             NSIndexPath *indexPath,
                             UIContextualAction *nativeDelete,
                             id delegate) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;

    NSArray<NSString *> *candidates = NMCandidatesForCell(cell);
    id model = NMConversationModelForCell(cell);

    NSString *title = candidates.firstObject ?: @"Conversation";
    NSString *identifier = candidates.count > 1 ? candidates[1] : nil;
    NSInteger count = NSNotFound;
    NSDate *firstDate = nil;
    NSString *databaseIdentifier = nil;
    NMQueryDatabaseStats(candidates, &count, &firstDate, &databaseIdentifier);
    if (count == NSNotFound) count = NMFallbackMessageCount(model);
    if (!firstDate) firstDate = NMFallbackFirstDate(model);
    if (databaseIdentifier.length) identifier = databaseIdentifier;

    NMConversationDetailsController *details = [[NMConversationDetailsController alloc] init];
    details.modalPresentationStyle = UIModalPresentationOverFullScreen;
    details.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    details.conversationTitle = title;
    details.identifierText = identifier;
    details.messageCountText =
        NMPreferenceBool(@"showMessageCount", YES)
        ? (count == NSNotFound ? @"Not available" : [NSString stringWithFormat:@"%ld", (long)count])
        : @"Hidden";
    details.firstDateText =
        NMPreferenceBool(@"showFirstDate", YES) ? NMReadableDate(firstDate) : @"Hidden";
    details.allowDelete = NMPreferenceBool(@"deleteFromCard", YES);

    __weak UITableView *weakTable = tableView;
    NSIndexPath *capturedPath = [indexPath copy];
    __weak id weakDelegate = delegate;
    details.deleteHandler = ^{
        NMInvokeNativeDelete(nativeDelete, weakDelegate, weakTable, capturedPath);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakTable reloadData];
        });
    };

    UIViewController *presenter = NMControllerForView(tableView);
    if (!presenter) return;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    NMHaptic(NO);
    [presenter presentViewController:details animated:YES completion:nil];
}

typedef UISwipeActionsConfiguration *(*NMSwipeIMP)(id, SEL, UITableView *, NSIndexPath *);

static UISwipeActionsConfiguration *NMCustomTrailingSwipe(id delegate,
                                                           SEL selector,
                                                           UITableView *tableView,
                                                           NSIndexPath *indexPath) {
    NMSwipeIMP originalIMP = NULL;
    @synchronized(NMOriginalSwipeIMPs) {
        originalIMP = [NMOriginalSwipeIMPs[NSStringFromClass([delegate class])] pointerValue];
    }

    UISwipeActionsConfiguration *original =
        originalIMP ? originalIMP(delegate, selector, tableView, indexPath) : nil;

    if (!NMEnabled() ||
        !NMPreferenceBool(@"detailsSwipe", YES) ||
        ![objc_getAssociatedObject(tableView, &NMConversationTableKey) boolValue]) {
        return original;
    }

    UIContextualAction *nativeDelete = nil;
    for (UIContextualAction *action in original.actions) {
        if (action.style == UIContextualActionStyleDestructive ||
            [action.title.lowercaseString containsString:@"delete"]) {
            nativeDelete = action;
            break;
        }
    }

    __weak UITableView *weakTable = tableView;
    NSIndexPath *capturedPath = [indexPath copy];
    __weak id weakDelegate = delegate;

    UIContextualAction *info =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                title:@"Info"
                                              handler:^(__unused UIContextualAction *action,
                                                        __unused UIView *sourceView,
                                                        void (^completionHandler)(BOOL)) {
        NMPresentDetails(weakTable, capturedPath, nativeDelete, weakDelegate);
        completionHandler(YES);
    }];
    info.backgroundColor = NMColor(0x6F63FF,1);
    info.image = [UIImage systemImageNamed:@"info.circle.fill"];

    UIContextualAction *delete =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                title:@"Delete"
                                              handler:^(__unused UIContextualAction *action,
                                                        __unused UIView *sourceView,
                                                        void (^completionHandler)(BOOL)) {
        UIViewController *presenter = NMControllerForView(weakTable);
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Delete Conversation?"
                                                message:@"This permanently removes the complete conversation."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:^(__unused UIAlertAction *cancel) {
            completionHandler(NO);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(__unused UIAlertAction *confirm) {
            NMHaptic(YES);
            NMInvokeNativeDelete(nativeDelete, weakDelegate, weakTable, capturedPath);
            completionHandler(YES);
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    }];
    delete.backgroundColor = NMColor(0xE93856,1);
    delete.image = [UIImage systemImageNamed:@"trash.fill"];

    UISwipeActionsConfiguration *configuration =
        [UISwipeActionsConfiguration configurationWithActions:@[delete, info]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

void NMInstallSwipeForConversationTable(UITableView *tableView) {
    if (!tableView || !tableView.delegate) return;
    objc_setAssociatedObject(tableView, &NMConversationTableKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id delegate = tableView.delegate;
    Class cls = [delegate class];
    NSString *className = NSStringFromClass(cls);
    SEL selector = @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:);

    @synchronized([NSProcessInfo processInfo]) {
        if (!NMOriginalSwipeIMPs) NMOriginalSwipeIMPs = [NSMutableDictionary dictionary];
        if (NMOriginalSwipeIMPs[className]) return;

        Method method = class_getInstanceMethod(cls, selector);
        IMP original = method ? method_getImplementation(method) : NULL;
        NMOriginalSwipeIMPs[className] = [NSValue valueWithPointer:original];

        const char *types = method ? method_getTypeEncoding(method) : "@@:@@";
        if (!class_addMethod(cls, selector, (IMP)NMCustomTrailingSwipe, types)) {
            Method ownMethod = class_getInstanceMethod(cls, selector);
            method_setImplementation(ownMethod, (IMP)NMCustomTrailingSwipe);
        }
    }
}

static void NMPreferencesChanged(__unused CFNotificationCenterRef center,
                                 __unused void *observer,
                                 __unused CFStringRef name,
                                 __unused const void *object,
                                 __unused CFDictionaryRef userInfo) {
    NMReloadPreferences();
    if (NMIsMessagesProcess()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            kill(getpid(), SIGTERM);
        });
    }
}

%ctor {
    if (!NMIsMessagesProcess()) return;
    NMReloadPreferences();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    NMPreferencesChanged,
                                    (__bridge CFStringRef)NMPreferencesChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
