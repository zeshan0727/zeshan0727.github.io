#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sqlite3.h>

static NSString * const NM13Domain = @"com.nextsolution.nextmessage";
static const void *NM13PanKey = &NM13PanKey;
static const void *NM13RailKey = &NM13RailKey;
static const void *NM13OpenKey = &NM13OpenKey;

static UIColor *NM13Color(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xff) / 255.0
                           green:((hex >> 8) & 0xff) / 255.0
                            blue:(hex & 0xff) / 255.0
                           alpha:alpha];
}

static NSDictionary *NM13Preferences(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
        @"/private/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path];
        if (values.count) [result addEntriesFromDictionary:values];
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)NM13Domain);
    for (NSString *key in @[@"enabled", @"detailsSwipe", @"deleteFromCard", @"haptics", @"animations"]) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                            (__bridge CFStringRef)NM13Domain);
        if (value) result[key] = CFBridgingRelease(value);
    }
    return result;
}

static BOOL NM13Bool(NSString *key, BOOL fallback) {
    id value = NM13Preferences()[key];
    return value ? [value boolValue] : fallback;
}

static UIViewController *NM13ViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL NM13IsConversationListCell(UITableViewCell *cell) {
    if (!cell.window) return NO;
    UIViewController *controller = NM13ViewControllerForView(cell);
    NSString *controllerName = NSStringFromClass(controller.class);
    NSString *cellName = NSStringFromClass(cell.class);
    BOOL controllerMatch = [controllerName rangeOfString:@"ConversationList" options:NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL cellMatch = [cellName rangeOfString:@"Conversation" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                     [cellName rangeOfString:@"CK" options:NSCaseInsensitiveSearch].location != NSNotFound;
    return controllerMatch && cellMatch;
}

static UITableView *NM13TableForCell(UITableViewCell *cell) {
    UIView *view = cell.superview;
    while (view && ![view isKindOfClass:UITableView.class]) view = view.superview;
    return (UITableView *)view;
}

static NSArray<NSString *> *NM13TextsInView(UIView *view) {
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet orderedSet];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count) {
        UIView *current = stack.lastObject;
        [stack removeLastObject];
        if ([current isKindOfClass:UILabel.class]) {
            NSString *text = [((UILabel *)current).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (text.length > 1 && text.length < 160) [values addObject:text];
        }
        [stack addObjectsFromArray:current.subviews];
    }
    return values.array;
}

static NSDate *NM13DateFromRaw(sqlite3_int64 raw) {
    double value = (double)raw;
    if (value > 1000000000000.0) value /= 1000000000.0;
    if (value < 1300000000.0) value += 978307200.0;
    return value > 0 ? [NSDate dateWithTimeIntervalSince1970:value] : nil;
}

static BOOL NM13Stats(NSArray<NSString *> *candidates, NSInteger *count, NSDate **firstDate, NSString **identifier) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2("/var/mobile/Library/SMS/sms.db", &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NO;
    }
    const char *sql = "SELECT COUNT(cmj.message_id), MIN(m.date), COALESCE(c.chat_identifier,c.guid,c.display_name) FROM chat c LEFT JOIN chat_message_join cmj ON cmj.chat_id=c.ROWID LEFT JOIN message m ON m.ROWID=cmj.message_id WHERE lower(c.chat_identifier)=lower(?) OR lower(c.guid)=lower(?) OR lower(c.display_name)=lower(?) GROUP BY c.ROWID ORDER BY MAX(m.date) DESC LIMIT 1";
    BOOL found = NO;
    for (NSString *candidate in candidates) {
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) continue;
        const char *utf8 = candidate.UTF8String;
        for (int index = 1; index <= 3; index++) sqlite3_bind_text(stmt, index, utf8, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            if (count) *count = (NSInteger)sqlite3_column_int64(stmt, 0);
            if (firstDate && sqlite3_column_type(stmt, 1) != SQLITE_NULL) *firstDate = NM13DateFromRaw(sqlite3_column_int64(stmt, 1));
            if (identifier && sqlite3_column_type(stmt, 2) != SQLITE_NULL) {
                const unsigned char *text = sqlite3_column_text(stmt, 2);
                if (text) *identifier = [NSString stringWithUTF8String:(const char *)text];
            }
            found = YES;
        }
        sqlite3_finalize(stmt);
        if (found) break;
    }
    sqlite3_close(db);
    return found;
}

@interface NM13DetailsController : UIViewController
@property(nonatomic,copy) NSString *displayTitle;
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic) NSInteger messageCount;
@property(nonatomic,strong) NSDate *firstDate;
@property(nonatomic,copy) dispatch_block_t deleteBlock;
@end

@implementation NM13DetailsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = self.view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blur];

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.tag = 727130;
    card.backgroundColor = NM13Color(0x10182E, 0.98);
    card.layer.cornerRadius = 30;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1;
    card.layer.borderColor = NM13Color(0x8294BD, 0.30).CGColor;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.46;
    card.layer.shadowRadius = 28;
    card.layer.shadowOffset = CGSizeMake(0, 14);
    [self.view addSubview:card];

    CAGradientLayer *strip = [CAGradientLayer layer];
    strip.name = @"NM13Strip";
    strip.colors = @[(id)NM13Color(0xFF5B61,1).CGColor,(id)NM13Color(0x6F63FF,1).CGColor,(id)NM13Color(0x18C8B7,1).CGColor];
    strip.startPoint = CGPointMake(0,0.5);
    strip.endPoint = CGPointMake(1,0.5);
    [card.layer addSublayer:strip];

    NSArray *titles = @[@"Conversation Details", @"Messages", @"First Message"];
    for (NSInteger i=0; i<3; i++) {
        UILabel *label = [[UILabel alloc] init];
        label.tag = 727140 + i;
        label.numberOfLines = 0;
        label.textColor = i == 0 ? UIColor.whiteColor : NM13Color(0xAEBBD5,1);
        label.font = i == 0 ? [UIFont systemFontOfSize:26 weight:UIFontWeightBold] : [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        label.text = titles[i];
        [card addSubview:label];
    }

    UILabel *name = [card viewWithTag:727140];
    name.text = self.displayTitle.length ? self.displayTitle : @"Conversation Details";

    UILabel *count = [[UILabel alloc] init];
    count.tag = 727150;
    count.textColor = UIColor.whiteColor;
    count.font = [UIFont monospacedDigitSystemFontOfSize:27 weight:UIFontWeightBold];
    count.text = self.messageCount >= 0 ? [NSString stringWithFormat:@"%ld", (long)self.messageCount] : @"—";
    [card addSubview:count];

    UILabel *date = [[UILabel alloc] init];
    date.tag = 727151;
    date.textColor = UIColor.whiteColor;
    date.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    date.numberOfLines = 2;
    if (self.firstDate) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        date.text = [formatter stringFromDate:self.firstDate];
    } else date.text = @"Not available";
    [card addSubview:date];

    UILabel *identifier = [[UILabel alloc] init];
    identifier.tag = 727152;
    identifier.textColor = NM13Color(0x8FA2C8,1);
    identifier.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    identifier.numberOfLines = 2;
    identifier.text = self.identifier.length ? self.identifier : @"Messages conversation";
    [card addSubview:identifier];

    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    deleteButton.tag = 727160;
    [deleteButton setTitle:@"Delete Conversation" forState:UIControlStateNormal];
    [deleteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    deleteButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    deleteButton.backgroundColor = NM13Color(0xE93856,1);
    deleteButton.layer.cornerRadius = 17;
    [deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:deleteButton];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.tag = 727161;
    [close setTitle:@"Close" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    close.backgroundColor = NM13Color(0x273450,1);
    close.layer.cornerRadius = 17;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *card = [self.view viewWithTag:727130];
    CGFloat width = MIN(self.view.bounds.size.width - 34, 390);
    CGFloat height = 470;
    card.frame = CGRectMake((self.view.bounds.size.width-width)/2,(self.view.bounds.size.height-height)/2,width,height);
    for (CALayer *layer in card.layer.sublayers) if ([layer.name isEqualToString:@"NM13Strip"]) layer.frame = CGRectMake(24,20,width-48,6);
    [card viewWithTag:727140].frame = CGRectMake(24,45,width-48,62);
    [card viewWithTag:727152].frame = CGRectMake(24,105,width-48,42);
    [card viewWithTag:727141].frame = CGRectMake(24,164,width-48,22);
    [card viewWithTag:727150].frame = CGRectMake(24,190,width-48,42);
    [card viewWithTag:727142].frame = CGRectMake(24,252,width-48,22);
    [card viewWithTag:727151].frame = CGRectMake(24,278,width-48,55);
    [card viewWithTag:727160].frame = CGRectMake(24,height-118,width-48,52);
    [card viewWithTag:727161].frame = CGRectMake(24,height-58,width-48,42);
}

- (void)deleteTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Conversation?" message:@"This removes the full conversation and cannot be undone." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        if (weakSelf.deleteBlock) weakSelf.deleteBlock();
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

static void NM13DeleteCell(UITableViewCell *cell) {
    UITableView *table = NM13TableForCell(cell);
    NSIndexPath *indexPath = [table indexPathForCell:cell];
    id delegate = table.delegate;
    SEL selector = @selector(tableView:commitEditingStyle:forRowAtIndexPath:);
    if (delegate && indexPath && [delegate respondsToSelector:selector]) {
        typedef void (*CommitFn)(id,SEL,UITableView *,UITableViewCellEditingStyle,NSIndexPath *);
        ((CommitFn)objc_msgSend)(delegate,selector,table,UITableViewCellEditingStyleDelete,indexPath);
    }
}

static void NM13PresentDetails(UITableViewCell *cell) {
    NSArray<NSString *> *texts = NM13TextsInView(cell.contentView);
    NSInteger count = -1;
    NSDate *date = nil;
    NSString *identifier = nil;
    NM13Stats(texts,&count,&date,&identifier);
    NM13DetailsController *details = [[NM13DetailsController alloc] init];
    details.modalPresentationStyle = UIModalPresentationOverFullScreen;
    details.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    details.displayTitle = texts.firstObject ?: @"Conversation Details";
    details.identifier = identifier ?: (texts.count > 1 ? texts[1] : nil);
    details.messageCount = count;
    details.firstDate = date;
    __weak UITableViewCell *weakCell = cell;
    details.deleteBlock = ^{ NM13DeleteCell(weakCell); };
    UIViewController *controller = NM13ViewControllerForView(cell);
    [controller presentViewController:details animated:YES completion:nil];
}

@interface NM13RailTarget : NSObject
@property(nonatomic,weak) UITableViewCell *cell;
- (void)details;
- (void)deleteConversation;
@end
@implementation NM13RailTarget
- (void)details { NM13PresentDetails(self.cell); }
- (void)deleteConversation {
    UITableViewCell *cell = self.cell;
    UIViewController *controller = NM13ViewControllerForView(cell);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Conversation?" message:@"This action cannot be undone." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){ NM13DeleteCell(cell); }]];
    [controller presentViewController:alert animated:YES completion:nil];
}
@end

static void NM13CloseRail(UITableViewCell *cell, BOOL animated) {
    objc_setAssociatedObject(cell,NM13OpenKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void (^changes)(void) = ^{ cell.contentView.transform = CGAffineTransformIdentity; };
    animated ? [UIView animateWithDuration:0.22 animations:changes] : changes();
}

static void NM13Pan(UIPanGestureRecognizer *gesture) {
    UITableViewCell *cell = (UITableViewCell *)gesture.view;
    if (!NM13Bool(@"enabled",YES) || !NM13Bool(@"detailsSwipe",YES)) { NM13CloseRail(cell,NO); return; }
    CGPoint translation = [gesture translationInView:cell];
    CGPoint velocity = [gesture velocityInView:cell];
    if (gesture.state == UIGestureRecognizerStateChanged) {
        if (fabs(translation.x) < fabs(translation.y)) return;
        CGFloat offset = MIN(0,MAX(-184,translation.x));
        cell.contentView.transform = CGAffineTransformMakeTranslation(offset,0);
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        BOOL open = translation.x < -70 || velocity.x < -500;
        objc_setAssociatedObject(cell,NM13OpenKey,@(open),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            cell.contentView.transform = open ? CGAffineTransformMakeTranslation(-184,0) : CGAffineTransformIdentity;
        } completion:nil];
    }
}

static void NM13InstallRail(UITableViewCell *cell) {
    if (!NM13IsConversationListCell(cell)) return;
    if (!NM13Bool(@"enabled",YES)) {
        UIView *rail = objc_getAssociatedObject(cell,NM13RailKey);
        [rail removeFromSuperview];
        objc_setAssociatedObject(cell,NM13RailKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NM13CloseRail(cell,NO);
        return;
    }
    UIView *rail = objc_getAssociatedObject(cell,NM13RailKey);
    if (!rail) {
        rail = [[UIView alloc] init];
        rail.backgroundColor = UIColor.clearColor;
        [cell insertSubview:rail belowSubview:cell.contentView];
        objc_setAssociatedObject(cell,NM13RailKey,rail,OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        NM13RailTarget *target = [[NM13RailTarget alloc] init];
        target.cell = cell;
        objc_setAssociatedObject(rail,@selector(details),target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIButton *details = [UIButton buttonWithType:UIButtonTypeSystem];
        details.tag = 727171;
        details.backgroundColor = NM13Color(0x6F63FF,1);
        [details setImage:[UIImage systemImageNamed:@"info.circle.fill"] forState:UIControlStateNormal];
        [details setTitle:@" Info" forState:UIControlStateNormal];
        [details setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        details.tintColor = UIColor.whiteColor;
        details.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        [details addTarget:target action:@selector(details) forControlEvents:UIControlEventTouchUpInside];
        [rail addSubview:details];

        UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        deleteButton.tag = 727172;
        deleteButton.backgroundColor = NM13Color(0xE93856,1);
        [deleteButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
        [deleteButton setTitle:@" Delete" forState:UIControlStateNormal];
        [deleteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        deleteButton.tintColor = UIColor.whiteColor;
        deleteButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        [deleteButton addTarget:target action:@selector(deleteConversation) forControlEvents:UIControlEventTouchUpInside];
        [rail addSubview:deleteButton];
    }
    rail.frame = cell.bounds;
    CGFloat width = 92;
    [rail viewWithTag:727171].frame = CGRectMake(cell.bounds.size.width-width*2,0,width,cell.bounds.size.height);
    [rail viewWithTag:727172].frame = CGRectMake(cell.bounds.size.width-width,0,width,cell.bounds.size.height);

    UIPanGestureRecognizer *pan = objc_getAssociatedObject(cell,NM13PanKey);
    if (!pan) {
        pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:nil];
        [pan addTarget:[NSBlockOperation blockOperationWithBlock:^{}] action:@selector(main)];
        [cell addGestureRecognizer:pan];
        [pan removeTarget:nil action:NULL];
        [pan addTarget:(id)cell action:@selector(nm13_handlePan:)];
        objc_setAssociatedObject(cell,NM13PanKey,pan,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"]) return;
    NM13InstallRail(self);
}
%new
- (void)nm13_handlePan:(UIPanGestureRecognizer *)gesture { NM13Pan(gesture); }
%end

%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"]) return;
    if (!NM13Bool(@"enabled",YES)) {
        self.view.backgroundColor = nil;
        self.navigationController.navigationBar.standardAppearance = nil;
        self.navigationController.navigationBar.scrollEdgeAppearance = nil;
    }
}
%end
