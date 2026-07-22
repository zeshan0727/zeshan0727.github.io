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

static id NMConversationModel(UITableViewCell *cell) {
    for (NSString *key in @[@"conversation", @"_conversation", @"chat", @"_chat",
                            @"conversationListItem", @"_conversationListItem",
                            @"model", @"_model"]) {
        id value = NMSafeValue(cell, key);
        if (value) return value;
    }
    return nil;
}

static NSArray<NSString *> *NMCandidates(UITableViewCell *cell) {
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet orderedSet];
    id model = NMConversationModel(cell);
    for (NSString *key in @[@"chatIdentifier", @"displayName", @"name", @"guid",
                            @"identifier", @"recipientAddress", @"address"]) {
        id value = NMSafeValue(model, key);
        if ([value isKindOfClass:NSString.class] && [value length]) [values addObject:value];
    }

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(cell.contentView, labels);
    for (UILabel *label in labels) {
        NSString *text =
            [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 1 && text.length < 180) [values addObject:text];
    }
    return values.array;
}

static NSDate *NMDateFromDatabaseValue(sqlite3_int64 value) {
    double raw = (double)value;
    if (raw <= 0) return nil;
    if (raw > 1000000000000.0) raw /= 1000000000.0;
    if (raw > 1300000000.0) return [NSDate dateWithTimeIntervalSince1970:raw];
    return [NSDate dateWithTimeIntervalSince1970:(raw + 978307200.0)];
}

static BOOL NMDatabaseStats(NSArray<NSString *> *candidates,
                            NSInteger *count,
                            NSDate **firstDate,
                            NSString **identifier) {
    sqlite3 *database = NULL;
    const char *paths[] = {
        "/private/var/mobile/Library/SMS/sms.db",
        "/var/mobile/Library/SMS/sms.db"
    };
    for (NSUInteger i = 0; i < 2 && !database; i++) {
        if (sqlite3_open_v2(paths[i], &database, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
            if (database) sqlite3_close(database);
            database = NULL;
        }
    }
    if (!database) return NO;

    const char *sql =
        "SELECT COUNT(cmj.message_id), MIN(m.date), "
        "COALESCE(c.chat_identifier,c.guid,c.display_name) "
        "FROM chat c "
        "LEFT JOIN chat_message_join cmj ON cmj.chat_id=c.ROWID "
        "LEFT JOIN message m ON m.ROWID=cmj.message_id "
        "WHERE lower(c.chat_identifier)=lower(?) OR lower(c.guid)=lower(?) "
        "OR lower(c.display_name)=lower(?) "
        "GROUP BY c.ROWID ORDER BY MAX(m.date) DESC LIMIT 1";

    BOOL found = NO;
    for (NSString *candidate in candidates) {
        if (candidate.length < 2) continue;
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) continue;
        const char *text = candidate.UTF8String;
        for (int index = 1; index <= 3; index++) {
            sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT);
        }
        if (sqlite3_step(statement) == SQLITE_ROW) {
            if (count) *count = sqlite3_column_int64(statement, 0);
            if (firstDate && sqlite3_column_type(statement, 1) != SQLITE_NULL) {
                *firstDate = NMDateFromDatabaseValue(sqlite3_column_int64(statement, 1));
            }
            if (identifier && sqlite3_column_type(statement, 2) != SQLITE_NULL) {
                const unsigned char *result = sqlite3_column_text(statement, 2);
                if (result) *identifier = [NSString stringWithUTF8String:(const char *)result];
            }
            found = YES;
        }
        sqlite3_finalize(statement);
        if (found) break;
    }
    sqlite3_close(database);
    return found;
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
@property(nonatomic,copy) NSString *titleText;
@property(nonatomic,copy) NSString *identifierText;
@property(nonatomic,copy) NSString *countText;
@property(nonatomic,copy) NSString *dateText;
@property(nonatomic,copy) dispatch_block_t deleteHandler;
@property(nonatomic) BOOL allowDelete;
@property(nonatomic,strong) UIView *card;
@end

@implementation NMConversationDetailsController

- (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)statCard:(NSString *)caption value:(NSString *)value accent:(UIColor *)accent {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = NMColor(0x17233E,0.96);
    card.layer.cornerRadius = 20;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.8;
    card.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;

    UILabel *title = [self label:caption.uppercaseString
                           font:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]
                          color:NMColor(0xAEBBD5,1)];
    title.frame = CGRectMake(18,13,280,18);
    [card addSubview:title];

    UILabel *valueLabel = [self label:value
                                 font:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]
                                color:UIColor.whiteColor];
    valueLabel.frame = CGRectMake(18,34,300,45);
    [card addSubview:valueLabel];
    return card;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = self.view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blur];

    self.card = [[UIView alloc] init];
    self.card.backgroundColor = NMColor(0x0B1327,0.99);
    self.card.layer.cornerRadius = 30;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = NMColor(0x7182AA,0.32).CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = 0.5;
    self.card.layer.shadowRadius = 30;
    self.card.layer.shadowOffset = CGSizeMake(0,14);
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

    UILabel *eyebrow = [self label:@"CONVERSATION DETAILS"
                              font:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]
                             color:NMColor(0x64DCCB,1)];
    eyebrow.tag = 1;
    [self.card addSubview:eyebrow];

    UILabel *title = [self label:self.titleText.length ? self.titleText : @"Conversation"
                            font:[UIFont systemFontOfSize:27 weight:UIFontWeightBold]
                           color:UIColor.whiteColor];
    title.tag = 2;
    [self.card addSubview:title];

    UILabel *identifier = [self label:self.identifierText.length ? self.identifierText : @"Messages conversation"
                                 font:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
                                color:NMColor(0xAEBBD5,1)];
    identifier.tag = 3;
    [self.card addSubview:identifier];

    UIView *countCard = [self statCard:@"Messages" value:self.countText ?: @"Not available"
                                accent:NMColor(0x6F63FF,1)];
    countCard.tag = 4;
    [self.card addSubview:countCard];

    UIView *dateCard = [self statCard:@"First message" value:self.dateText ?: @"Not available"
                               accent:NMColor(0x18C8B7,1)];
    dateCard.tag = 5;
    [self.card addSubview:dateCard];

    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    deleteButton.tag = 6;
    [deleteButton setTitle:@"Delete Conversation" forState:UIControlStateNormal];
    [deleteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    deleteButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    deleteButton.backgroundColor = NMColor(0xE93856,1);
    deleteButton.layer.cornerRadius = 18;
    deleteButton.hidden = !self.allowDelete;
    [deleteButton addTarget:self action:@selector(deleteTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:deleteButton];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.tag = 7;
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    closeButton.backgroundColor = NMColor(0x273450,1);
    closeButton.layer.cornerRadius = 18;
    [closeButton addTarget:self action:@selector(closeTapped)
          forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:closeButton];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!NMPreferenceBool(@"animations",YES)) return;
    self.card.transform = CGAffineTransformMakeScale(0.86,0.86);
    self.card.alpha = 0;
    [UIView animateWithDuration:0.34 delay:0
         usingSpringWithDamping:0.78 initialSpringVelocity:0
                       options:UIViewAnimationOptionBeginFromCurrentState
                    animations:^{
        self.card.transform = CGAffineTransformIdentity;
        self.card.alpha = 1;
    } completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = MIN(CGRectGetWidth(self.view.bounds)-28,410);
    CGFloat height = 500;
    self.card.frame = CGRectMake((CGRectGetWidth(self.view.bounds)-width)/2,
                                 (CGRectGetHeight(self.view.bounds)-height)/2,
                                 width,height);
    for (CALayer *layer in self.card.layer.sublayers) {
        if ([layer.name isEqualToString:@"NMDetailsStrip"]) {
            layer.frame = CGRectMake(24,20,width-48,6);
        }
    }
    [self.card viewWithTag:1].frame = CGRectMake(24,38,width-48,18);
    [self.card viewWithTag:2].frame = CGRectMake(24,64,width-48,62);
    [self.card viewWithTag:3].frame = CGRectMake(24,125,width-48,35);
    [self.card viewWithTag:4].frame = CGRectMake(24,176,width-48,92);
    [self.card viewWithTag:5].frame = CGRectMake(24,280,width-48,92);
    [self.card viewWithTag:6].frame = CGRectMake(24,390,width-48,54);
    [self.card viewWithTag:7].frame = CGRectMake(24,452,width-48,38);
}

- (void)deleteTapped {
    NMHaptic(YES);
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Delete Conversation?"
                                            message:@"This permanently removes the complete conversation."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel handler:nil]];
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

static void NMInvokeDelete(UIContextualAction *nativeAction,
                           id delegate,
                           UITableView *tableView,
                           NSIndexPath *indexPath) {
    if (nativeAction) {
        id handlerValue = NMSafeValue(nativeAction, @"handler") ?: NMSafeValue(nativeAction, @"_handler");
        if (handlerValue) {
            void (^handler)(UIContextualAction *, UIView *, void (^)(BOOL)) = handlerValue;
            handler(nativeAction,nil,^(__unused BOOL success){});
            return;
        }
    }

    SEL commitSelector = @selector(tableView:commitEditingStyle:forRowAtIndexPath:);
    if ([delegate respondsToSelector:commitSelector]) {
        typedef void (*CommitIMP)(id,SEL,UITableView *,UITableViewCellEditingStyle,NSIndexPath *);
        ((CommitIMP)objc_msgSend)(delegate,commitSelector,tableView,
                                 UITableViewCellEditingStyleDelete,indexPath);
    }
}

static void NMPresentDetails(UITableView *tableView,
                             NSIndexPath *indexPath,
                             UIContextualAction *nativeDelete,
                             id delegate) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;

    NSArray<NSString *> *candidates = NMCandidates(cell);
    NSInteger count = NSNotFound;
    NSDate *firstDate = nil;
    NSString *identifier = nil;
    NMDatabaseStats(candidates,&count,&firstDate,&identifier);

    if (count == NSNotFound) {
        id value = NMSafeValue(NMConversationModel(cell),@"messageCount");
        if ([value respondsToSelector:@selector(integerValue)]) count = [value integerValue];
    }

    NMConversationDetailsController *details = [[NMConversationDetailsController alloc] init];
    details.modalPresentationStyle = UIModalPresentationOverFullScreen;
    details.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    details.titleText = candidates.firstObject ?: @"Conversation";
    details.identifierText = identifier ?: (candidates.count > 1 ? candidates[1] : nil);
    details.countText = NMPreferenceBool(@"showMessageCount",YES)
        ? (count == NSNotFound ? @"Not available" : [NSString stringWithFormat:@"%ld",(long)count])
        : @"Hidden";
    details.dateText = NMPreferenceBool(@"showFirstDate",YES) ? NMReadableDate(firstDate) : @"Hidden";
    details.allowDelete = NMPreferenceBool(@"deleteFromCard",YES);

    __weak UITableView *weakTable = tableView;
    __weak id weakDelegate = delegate;
    NSIndexPath *capturedPath = [indexPath copy];
    details.deleteHandler = ^{
        NMInvokeDelete(nativeDelete,weakDelegate,weakTable,capturedPath);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{ [weakTable reloadData]; });
    };

    UIViewController *presenter = NMControllerForView(tableView);
    if (!presenter) return;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    NMHaptic(NO);
    [presenter presentViewController:details animated:YES completion:nil];
}

typedef UISwipeActionsConfiguration *(*NMSwipeIMP)(id,SEL,UITableView *,NSIndexPath *);

static UISwipeActionsConfiguration *NMCustomSwipe(id delegate,
                                                   SEL selector,
                                                   UITableView *tableView,
                                                   NSIndexPath *indexPath) {
    NMSwipeIMP originalIMP = NULL;
    NSValue *stored = NMOriginalSwipeIMPs[NSStringFromClass([delegate class])];
    if (stored) [stored getValue:&originalIMP];

    UISwipeActionsConfiguration *original =
        originalIMP ? originalIMP(delegate,selector,tableView,indexPath) : nil;

    if (!NMEnabled() || !NMPreferenceBool(@"detailsSwipe",YES) ||
        ![objc_getAssociatedObject(tableView,&NMConversationTableKey) boolValue]) {
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
    __weak id weakDelegate = delegate;
    NSIndexPath *capturedPath = [indexPath copy];

    UIContextualAction *infoAction =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                title:@"Info"
                                              handler:^(__unused UIContextualAction *action,
                                                        __unused UIView *source,
                                                        void (^completion)(BOOL)) {
        NMPresentDetails(weakTable,capturedPath,nativeDelete,weakDelegate);
        completion(YES);
    }];
    infoAction.backgroundColor = NMColor(0x6F63FF,1);
    infoAction.image = [UIImage systemImageNamed:@"info.circle.fill"];

    UIContextualAction *deleteAction =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                title:@"Delete"
                                              handler:^(__unused UIContextualAction *action,
                                                        __unused UIView *source,
                                                        void (^completion)(BOOL)) {
        UIViewController *presenter = NMControllerForView(weakTable);
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Delete Conversation?"
                                                message:@"This permanently removes the complete conversation."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:^(__unused UIAlertAction *cancel) {
            completion(NO);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(__unused UIAlertAction *confirm) {
            NMHaptic(YES);
            NMInvokeDelete(nativeDelete,weakDelegate,weakTable,capturedPath);
            completion(YES);
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    }];
    deleteAction.backgroundColor = NMColor(0xE93856,1);
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UISwipeActionsConfiguration *configuration =
        [UISwipeActionsConfiguration configurationWithActions:@[deleteAction,infoAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

void NMInstallSwipeForConversationTable(UITableView *tableView) {
    if (!tableView || !tableView.delegate) return;
    objc_setAssociatedObject(tableView,&NMConversationTableKey,@YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id delegate = tableView.delegate;
    Class cls = [delegate class];
    NSString *className = NSStringFromClass(cls);
    if (!NMOriginalSwipeIMPs) NMOriginalSwipeIMPs = [NSMutableDictionary dictionary];
    if (NMOriginalSwipeIMPs[className]) return;

    SEL selector = @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:);
    Method method = class_getInstanceMethod(cls,selector);
    IMP original = method ? method_getImplementation(method) : NULL;
    NMOriginalSwipeIMPs[className] = [NSValue valueWithBytes:&original objCType:@encode(IMP)];

    const char *types = method ? method_getTypeEncoding(method) : "@@:@@";
    if (!class_addMethod(cls,selector,(IMP)NMCustomSwipe,types)) {
        Method ownMethod = class_getInstanceMethod(cls,selector);
        method_setImplementation(ownMethod,(IMP)NMCustomSwipe);
    }
}

static void NMPreferencesChanged(__unused CFNotificationCenterRef center,
                                 __unused void *observer,
                                 __unused CFStringRef name,
                                 __unused const void *object,
                                 __unused CFDictionaryRef userInfo) {
    NMReloadPreferences();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.18*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{ kill(getpid(),SIGTERM); });
}

%ctor {
    if (!NMIsMessagesProcess()) return;
    NMReloadPreferences();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,NMPreferencesChanged,
                                    (__bridge CFStringRef)NMPreferencesChangedNotification,
                                    NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
}
