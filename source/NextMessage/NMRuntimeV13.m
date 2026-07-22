#import "NMRuntimeV13.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sqlite3.h>

static NSString * const NMDomain = @"com.nextsolution.nextmessage";
static NSString * const NMChanged = @"com.nextsolution.nextmessage/preferences.changed";
static const NSInteger NMBackgroundTag = 727300;
static const NSInteger NMHeaderTag = 727301;
static const NSInteger NMCardTag = 727302;
static const NSInteger NMAccentTag = 727303;
static BOOL nmEnabled = YES;
static BOOL nmCards = YES;
static BOOL nmGlass = YES;
static BOOL nmBubbles = YES;
static BOOL nmComposer = YES;
static BOOL nmDetails = YES;
static BOOL nmCount = YES;
static BOOL nmFirstDate = YES;
static BOOL nmDelete = YES;
static BOOL nmHaptics = YES;
static BOOL nmAnimations = YES;
static CGFloat nmOpacity = 0.96;
static CGFloat nmRadius = 20.0;
static NSMutableDictionary<NSString *, NSValue *> *nmOriginalSwipeIMPs;

static UIColor *NMC(uint32_t hex, CGFloat a) {
    return [UIColor colorWithRed:((hex >> 16) & 255)/255.0 green:((hex >> 8) & 255)/255.0 blue:(hex & 255)/255.0 alpha:a];
}

static BOOL NMIsMessages(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"];
}

static id NMRead(NSString *key, id fallback) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NMDomain));
    if (!value) {
        NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:NMDomain];
        value = [suite objectForKey:key];
    }
    if (!value) {
        NSArray *paths = @[@"/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
                           @"/private/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
                           @"/var/jb/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist"];
        for (NSString *path in paths) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
            if (dict[key]) { value = dict[key]; break; }
        }
    }
    return value ?: fallback;
}

static void NMLoad(void) {
    nmEnabled = [NMRead(@"enabled", @YES) boolValue];
    nmCards = [NMRead(@"conversationCards", @YES) boolValue];
    nmGlass = [NMRead(@"glassBackground", @YES) boolValue];
    nmBubbles = [NMRead(@"bubbleStyling", @YES) boolValue];
    nmComposer = [NMRead(@"inputStyling", @YES) boolValue];
    nmDetails = [NMRead(@"detailsSwipe", @YES) boolValue];
    nmCount = [NMRead(@"showMessageCount", @YES) boolValue];
    nmFirstDate = [NMRead(@"showFirstDate", @YES) boolValue];
    nmDelete = [NMRead(@"deleteFromCard", @YES) boolValue];
    nmHaptics = [NMRead(@"haptics", @YES) boolValue];
    nmAnimations = [NMRead(@"animations", @YES) boolValue];
    nmOpacity = MIN(MAX([NMRead(@"cardOpacity", @0.96) doubleValue], 0.68), 1.0);
    nmRadius = MIN(MAX([NMRead(@"cornerRadius", @20.0) doubleValue], 12.0), 30.0);
}

static void NMFeedback(BOOL warning) {
    if (!nmHaptics) return;
    if (warning) [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeWarning];
    else [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

static UIViewController *NMControllerForView(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
        r = r.nextResponder;
    }
    return nil;
}

static BOOL NMNameContains(id object, NSArray<NSString *> *parts) {
    NSString *name = NSStringFromClass([object class]);
    for (NSString *part in parts) if ([name rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static UITableView *NMFindTable(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *sub in view.subviews) { UITableView *table = NMFindTable(sub); if (table) return table; }
    return nil;
}

static UISearchBar *NMFindSearch(UIView *view) {
    if ([view isKindOfClass:UISearchBar.class]) return (UISearchBar *)view;
    for (UIView *sub in view.subviews) { UISearchBar *bar = NMFindSearch(sub); if (bar) return bar; }
    return nil;
}

static void NMCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *sub in view.subviews) NMCollectLabels(sub, labels);
}

static void NMRemoveThemeFromView(UIView *view) {
    [[view viewWithTag:NMBackgroundTag] removeFromSuperview];
    [[view viewWithTag:NMHeaderTag] removeFromSuperview];
    [[view viewWithTag:NMCardTag] removeFromSuperview];
    [[view viewWithTag:NMAccentTag] removeFromSuperview];
    view.layer.borderWidth = 0;
    view.layer.shadowOpacity = 0;
}

static void NMApplyNavigation(UIViewController *controller) {
    UINavigationBar *bar = controller.navigationController.navigationBar;
    if (!bar) return;
    if (!nmEnabled) {
        bar.standardAppearance = nil;
        bar.scrollEdgeAppearance = nil;
        bar.compactAppearance = nil;
        return;
    }
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = NMC(0x08101F, 0.96);
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor,
                                       NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]};
    appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor,
                                            NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    bar.tintColor = NMC(0x37D8C8, 1);
}

static UIView *NMHeader(void) {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(12, 6, UIScreen.mainScreen.bounds.size.width - 24, 92)];
    header.tag = NMHeaderTag;
    header.userInteractionEnabled = NO;
    header.layer.cornerRadius = 26;
    header.layer.cornerCurve = kCACornerCurveContinuous;
    header.clipsToBounds = YES;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = header.bounds;
    gradient.colors = @[(id)NMC(0xFF5B61,1).CGColor,(id)NMC(0x6F63FF,1).CGColor,(id)NMC(0x18C8B7,1).CGColor];
    gradient.startPoint = CGPointMake(0,0.3); gradient.endPoint = CGPointMake(1,0.8);
    [header.layer addSublayer:gradient];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 14, header.bounds.size.width-48, 38)];
    title.text = @"Next Message";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:29 weight:UIFontWeightBold];
    [header addSubview:title];
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(25, 51, header.bounds.size.width-50, 24)];
    sub.text = @"Messages, redesigned by Next Solution";
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [header addSubview:sub];
    return header;
}

static void NMThemeListController(UIViewController *controller) {
    UITableView *table = NMFindTable(controller.view);
    if (!table) return;
    if (!nmEnabled) {
        NMRemoveThemeFromView(controller.view);
        table.backgroundColor = nil;
        table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        table.contentInset = UIEdgeInsetsZero;
        [table reloadData];
        return;
    }
    controller.view.backgroundColor = NMC(0x050914,1);
    UIView *bg = [controller.view viewWithTag:NMBackgroundTag];
    if (!bg && nmGlass) {
        bg = [[UIView alloc] initWithFrame:controller.view.bounds]; bg.tag = NMBackgroundTag; bg.userInteractionEnabled = NO;
        CAGradientLayer *g = [CAGradientLayer layer]; g.name = @"NMMain"; g.colors = @[(id)NMC(0x050914,1).CGColor,(id)NMC(0x11122B,1).CGColor,(id)NMC(0x071E28,1).CGColor]; g.startPoint=CGPointMake(0,0); g.endPoint=CGPointMake(1,1); [bg.layer addSublayer:g];
        [controller.view insertSubview:bg atIndex:0];
    }
    bg.frame = controller.view.bounds; for (CALayer *l in bg.layer.sublayers) l.frame = bg.bounds;
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.contentInset = UIEdgeInsetsMake(102,0,18,0);
    table.scrollIndicatorInsets = table.contentInset;
    UIView *header = [controller.view viewWithTag:NMHeaderTag];
    if (!header) { header = NMHeader(); [controller.view addSubview:header]; }
    CGRect hf = header.frame; hf.size.width = controller.view.bounds.size.width - 24; header.frame = hf;
    for (CALayer *l in header.layer.sublayers) if ([l isKindOfClass:CAGradientLayer.class]) l.frame = header.bounds;
    UISearchBar *search = NMFindSearch(controller.view);
    if (search) {
        search.searchTextField.backgroundColor = NMC(0x18233F,0.96);
        search.searchTextField.textColor = UIColor.whiteColor;
        search.searchTextField.layer.cornerRadius = 16;
        search.searchTextField.clipsToBounds = YES;
    }
}

static void NMThemeConversationController(UIViewController *controller) {
    if (!nmEnabled) { NMRemoveThemeFromView(controller.view); controller.view.backgroundColor = nil; return; }
    controller.view.backgroundColor = NMC(0x050914,1);
    for (UIView *sub in controller.view.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if ([name rangeOfString:@"Transcript" options:NSCaseInsensitiveSearch].location != NSNotFound || [sub isKindOfClass:UICollectionView.class]) sub.backgroundColor = UIColor.clearColor;
        if (nmComposer && ([name rangeOfString:@"Entry" options:NSCaseInsensitiveSearch].location != NSNotFound || [name rangeOfString:@"Compose" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
            sub.backgroundColor = NMC(0x111A31,0.96); sub.layer.cornerRadius = 21; sub.layer.cornerCurve = kCACornerCurveContinuous; sub.layer.borderWidth = 1; sub.layer.borderColor = NMC(0x6E7FA8,0.34).CGColor;
        }
    }
}

static void NMApplyController(UIViewController *controller) {
    if (!NMIsMessages() || !controller.view.window) return;
    NSString *name = NSStringFromClass(controller.class);
    BOOL list = ([name rangeOfString:@"ConversationList" options:NSCaseInsensitiveSearch].location != NSNotFound || [name rangeOfString:@"MessagesController" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL chat = ([name rangeOfString:@"ConversationView" options:NSCaseInsensitiveSearch].location != NSNotFound || [name rangeOfString:@"Transcript" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL details = ([name rangeOfString:@"Details" options:NSCaseInsensitiveSearch].location != NSNotFound || [name rangeOfString:@"Contact" options:NSCaseInsensitiveSearch].location != NSNotFound);
    if (details) return;
    NMApplyNavigation(controller);
    if (list) NMThemeListController(controller);
    else if (chat) NMThemeConversationController(controller);
}

static void NMStyleCell(UITableViewCell *cell) {
    if (!NMIsMessages() || !cell.window) return;
    UIViewController *controller = NMControllerForView(cell);
    NSString *controllerName = NSStringFromClass(controller.class);
    BOOL isList = [controllerName rangeOfString:@"ConversationList" options:NSCaseInsensitiveSearch].location != NSNotFound || [controllerName rangeOfString:@"MessagesController" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (!isList || !nmEnabled || !nmCards) {
        [[cell.contentView viewWithTag:NMCardTag] removeFromSuperview];
        [[cell.contentView viewWithTag:NMAccentTag] removeFromSuperview];
        return;
    }
    cell.backgroundColor = UIColor.clearColor; cell.contentView.backgroundColor = UIColor.clearColor;
    UIView *card = [cell.contentView viewWithTag:NMCardTag];
    if (!card) {
        card = [[UIView alloc] init]; card.tag = NMCardTag; card.userInteractionEnabled = NO; card.layer.cornerCurve = kCACornerCurveContinuous; card.layer.borderWidth = 0.8; card.layer.shadowColor = UIColor.blackColor.CGColor; card.layer.shadowOpacity = 0.28; card.layer.shadowRadius = 12; card.layer.shadowOffset = CGSizeMake(0,5);
        CAGradientLayer *g = [CAGradientLayer layer]; g.name=@"NMCell"; [card.layer addSublayer:g]; [cell.contentView insertSubview:card atIndex:0];
        UIView *accent = [[UIView alloc] init]; accent.tag = NMAccentTag; accent.userInteractionEnabled=NO; [cell.contentView addSubview:accent];
        CAGradientLayer *ag=[CAGradientLayer layer]; ag.name=@"NMAccent"; ag.colors=@[(id)NMC(0xFF5B61,1).CGColor,(id)NMC(0x6F63FF,1).CGColor,(id)NMC(0x18C8B7,1).CGColor]; ag.startPoint=CGPointMake(0,0); ag.endPoint=CGPointMake(0,1); [accent.layer addSublayer:ag];
    }
    card.frame = CGRectInset(cell.contentView.bounds, 10, 5); card.layer.cornerRadius = nmRadius; card.layer.borderColor=NMC(0x7E8CB0,0.26).CGColor; card.alpha=nmOpacity;
    for (CALayer *l in card.layer.sublayers) if ([l.name isEqualToString:@"NMCell"]) { CAGradientLayer *g=(id)l; g.frame=card.bounds; g.cornerRadius=nmRadius; g.colors=@[(id)NMC(0x192748,1).CGColor,(id)NMC(0x111A33,1).CGColor,(id)NMC(0x17223D,1).CGColor]; g.startPoint=CGPointMake(0,0.5); g.endPoint=CGPointMake(1,0.5); }
    UIView *accent=[cell.contentView viewWithTag:NMAccentTag]; accent.frame=CGRectMake(10,12,4,MAX(cell.contentView.bounds.size.height-24,20)); accent.layer.cornerRadius=2; for(CALayer *l in accent.layer.sublayers) l.frame=accent.bounds;
    NSMutableArray *labels=[NSMutableArray array]; NMCollectLabels(cell.contentView,labels);
    for (UILabel *label in labels) { if (label.tag==NMHeaderTag) continue; label.textColor = label.font.pointSize >= 16 ? UIColor.whiteColor : NMC(0xAEBBD5,1); }
    for (UIView *sub in cell.contentView.subviews) if ([sub isKindOfClass:UIImageView.class]) { sub.layer.cornerRadius = MIN(sub.bounds.size.width,sub.bounds.size.height)/2.0; sub.clipsToBounds=YES; }
}

static void NMStyleBubbleView(UIView *view) {
    if (!NMIsMessages() || !view.window) return;
    UIViewController *controller=NMControllerForView(view);
    NSString *cn=NSStringFromClass(controller.class);
    BOOL chat=[cn rangeOfString:@"ConversationView" options:NSCaseInsensitiveSearch].location!=NSNotFound || [cn rangeOfString:@"Transcript" options:NSCaseInsensitiveSearch].location!=NSNotFound;
    if (!chat) return;
    NSString *name=NSStringFromClass(view.class);
    if (!nmEnabled) { view.layer.borderWidth=0; return; }
    if (nmBubbles && ([name rangeOfString:@"Balloon" options:NSCaseInsensitiveSearch].location!=NSNotFound || [name rangeOfString:@"Bubble" options:NSCaseInsensitiveSearch].location!=NSNotFound)) {
        view.layer.cornerRadius = MIN(MAX(nmRadius,17),24); view.layer.cornerCurve=kCACornerCurveContinuous; view.clipsToBounds=YES; view.layer.borderWidth=0.8; view.layer.borderColor=NMC(0x8A96B6,0.24).CGColor;
    }
}

static NSDate *NMDate(NSNumber *n) { if(![n isKindOfClass:NSNumber.class]) return nil; double v=n.doubleValue; if(v<=0)return nil; if(v>1e12)v/=1e9; if(v>1300000000)return [NSDate dateWithTimeIntervalSince1970:v]; return [NSDate dateWithTimeIntervalSince1970:v+978307200.0]; }

static BOOL NMStats(NSArray<NSString *> *values, NSInteger *count, NSDate **date, NSString **identifier) {
    sqlite3 *db=NULL; for(NSString *p in @[@"/private/var/mobile/Library/SMS/sms.db",@"/var/mobile/Library/SMS/sms.db"]) if(sqlite3_open_v2(p.UTF8String,&db,SQLITE_OPEN_READONLY,NULL)==SQLITE_OK) break; else { if(db)sqlite3_close(db); db=NULL; }
    if(!db)return NO;
    const char *sql="SELECT COUNT(cmj.message_id),MIN(m.date),COALESCE(c.chat_identifier,c.guid,c.display_name) FROM chat c LEFT JOIN chat_message_join cmj ON cmj.chat_id=c.ROWID LEFT JOIN message m ON m.ROWID=cmj.message_id WHERE lower(c.chat_identifier)=lower(?) OR lower(c.guid)=lower(?) OR lower(c.display_name)=lower(?) GROUP BY c.ROWID LIMIT 1";
    BOOL found=NO;
    for(NSString *v in values){ if(v.length<2)continue; sqlite3_stmt *s=NULL; if(sqlite3_prepare_v2(db,sql,-1,&s,NULL)!=SQLITE_OK)continue; for(int i=1;i<=3;i++)sqlite3_bind_text(s,i,v.UTF8String,-1,SQLITE_TRANSIENT); if(sqlite3_step(s)==SQLITE_ROW){ if(count)*count=sqlite3_column_int64(s,0); if(date&&sqlite3_column_type(s,1)!=SQLITE_NULL)*date=NMDate(@(sqlite3_column_int64(s,1))); if(identifier&&sqlite3_column_type(s,2)!=SQLITE_NULL)*identifier=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,2)]; found=YES;} sqlite3_finalize(s); if(found)break; }
    sqlite3_close(db); return found;
}

@interface NMDetailsV13 : UIViewController
@property(nonatomic,copy) NSString *titleText; @property(nonatomic,copy) NSString *identifierText; @property(nonatomic,copy) NSString *countText; @property(nonatomic,copy) NSString *dateText; @property(nonatomic,copy) dispatch_block_t deleteBlock;
@end
@implementation NMDetailsV13
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=[UIColor colorWithWhite:0 alpha:.72]; UIView *card=[[UIView alloc]initWithFrame:CGRectZero]; card.tag=77; card.backgroundColor=NMC(0x10182E,.99); card.layer.cornerRadius=30; card.layer.cornerCurve=kCACornerCurveContinuous; card.layer.borderWidth=1; card.layer.borderColor=NMC(0x8493B7,.35).CGColor; card.layer.shadowOpacity=.5; card.layer.shadowRadius=30; [self.view addSubview:card]; NSArray *texts=@[self.titleText?:@"Conversation Details",self.identifierText?:@"Messages conversation",[NSString stringWithFormat:@"Messages\n%@",self.countText?:@"Not available"],[NSString stringWithFormat:@"First message\n%@",self.dateText?:@"Not available"]]; NSArray *sizes=@[@26,@14,@18,@18]; CGFloat y=44; for(NSUInteger i=0;i<texts.count;i++){UILabel*l=[[UILabel alloc]initWithFrame:CGRectZero];l.tag=100+i;l.text=texts[i];l.numberOfLines=0;l.textColor=i==1?NMC(0xAEBBD5,1):UIColor.whiteColor;l.font=[UIFont systemFontOfSize:[sizes[i] doubleValue] weight:i==0?UIFontWeightBold:UIFontWeightSemibold];[card addSubview:l];y+=70;} UIButton *del=[UIButton buttonWithType:UIButtonTypeSystem];del.tag=200;[del setTitle:@"Delete Conversation" forState:UIControlStateNormal];[del setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];del.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightBold];del.backgroundColor=NMC(0xE93856,1);del.layer.cornerRadius=18;[del addTarget:self action:@selector(del) forControlEvents:UIControlEventTouchUpInside];del.hidden=!nmDelete;[card addSubview:del];UIButton*close=[UIButton buttonWithType:UIButtonTypeSystem];close.tag=201;[close setTitle:@"Close" forState:UIControlStateNormal];[close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];close.backgroundColor=NMC(0x293653,1);close.layer.cornerRadius=18;[close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];[card addSubview:close]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; UIView*card=[self.view viewWithTag:77];CGFloat w=MIN(self.view.bounds.size.width-34,390),h=440;card.frame=CGRectMake((self.view.bounds.size.width-w)/2,(self.view.bounds.size.height-h)/2,w,h);((UILabel*)[card viewWithTag:100]).frame=CGRectMake(24,34,w-48,68);((UILabel*)[card viewWithTag:101]).frame=CGRectMake(24,104,w-48,42);((UILabel*)[card viewWithTag:102]).frame=CGRectMake(24,162,w-48,70);((UILabel*)[card viewWithTag:103]).frame=CGRectMake(24,240,w-48,76);[card viewWithTag:200].frame=CGRectMake(24,328,w-48,52);[card viewWithTag:201].frame=CGRectMake(24,386,w-48,42); }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if(nmAnimations){UIView*c=[self.view viewWithTag:77];c.transform=CGAffineTransformMakeScale(.88,.88);c.alpha=0;[UIView animateWithDuration:.32 delay:0 usingSpringWithDamping:.78 initialSpringVelocity:0 options:0 animations:^{c.alpha=1;c.transform=CGAffineTransformIdentity;} completion:nil];}}
- (void)del { NMFeedback(YES); UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Delete Conversation?" message:@"This action cannot be undone." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction*x){if(w.deleteBlock)w.deleteBlock();[w dismissViewControllerAnimated:YES completion:nil];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)close { NMFeedback(NO); [self dismissViewControllerAnimated:YES completion:nil]; }
@end

static NSArray<NSString *> *NMCellValues(UITableViewCell *cell) { NSMutableOrderedSet *set=[NSMutableOrderedSet orderedSet];NSMutableArray*labels=[NSMutableArray array];NMCollectLabels(cell.contentView,labels);for(UILabel*l in labels){NSString*t=[l.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(t.length>1&&t.length<140)[set addObject:t];}return set.array; }

static void NMCallAction(UIContextualAction *action) { id h=nil;@try{h=[action valueForKey:@"handler"]?:[action valueForKey:@"_handler"];}@catch(__unused NSException*e){} if(h){void(^block)(UIContextualAction*,UIView*,void(^)(BOOL))=h;block(action,nil,^(__unused BOOL ok){});} }

static UISwipeActionsConfiguration *NMSwipeReplacement(id self, SEL _cmd, UITableView *table, NSIndexPath *indexPath) {
    NSString *key=NSStringFromClass([self class]); IMP imp=[nmOriginalSwipeIMPs[key] pointerValue]; UISwipeActionsConfiguration *original=imp?((id(*)(id,SEL,id,id))imp)(self,_cmd,table,indexPath):nil;
    if(!nmEnabled||!nmDetails)return original;
    UIContextualAction *deleteAction=nil; for(UIContextualAction*a in original.actions)if(a.style==UIContextualActionStyleDestructive||[a.title.lowercaseString containsString:@"delete"]){deleteAction=a;break;}
    __weak id weakSelf=self; __weak UITableView*weakTable=table; UIContextualAction *detailsAction=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Details" handler:^(__unused UIContextualAction*a,__unused UIView*v,void(^done)(BOOL)){UITableViewCell*cell=[weakTable cellForRowAtIndexPath:indexPath];NSArray*vals=NMCellValues(cell);NSInteger count=NSNotFound;NSDate*date=nil;NSString*identifier=nil;NMStats(vals,&count,&date,&identifier);NSDateFormatter*f=[[NSDateFormatter alloc]init];f.dateStyle=NSDateFormatterMediumStyle;f.timeStyle=NSDateFormatterShortStyle;NMDetailsV13*d=[NMDetailsV13 new];d.modalPresentationStyle=UIModalPresentationOverFullScreen;d.titleText=vals.firstObject?:@"Conversation";d.identifierText=identifier?:((vals.count>1)?vals[1]:@"Messages conversation");d.countText=nmCount?(count==NSNotFound?@"Not available":[NSString stringWithFormat:@"%ld",(long)count]):@"Hidden";d.dateText=nmFirstDate?(date?[f stringFromDate:date]:@"Not available"):@"Hidden";d.deleteBlock=^{if(deleteAction)NMCallAction(deleteAction);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakTable reloadData];});};UIViewController*vc=(UIViewController*)weakSelf;if(![vc isKindOfClass:UIViewController.class])vc=NMControllerForView(weakTable);[vc presentViewController:d animated:YES completion:nil];NMFeedback(NO);done(YES);}];detailsAction.backgroundColor=NMC(0x6F63FF,1);detailsAction.image=[UIImage systemImageNamed:@"info.circle.fill"];
    UIContextualAction *customDelete=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction*a,__unused UIView*v,void(^done)(BOOL)){if(deleteAction)NMCallAction(deleteAction);done(YES);}];customDelete.image=[UIImage systemImageNamed:@"trash.fill"];
    UISwipeActionsConfiguration *cfg=[UISwipeActionsConfiguration configurationWithActions:nmDelete?@[customDelete,detailsAction]:@[detailsAction]];cfg.performsFirstActionWithFullSwipe=NO;return cfg;
}

static void NMInstallSwipeHooks(void) {
    if(!nmOriginalSwipeIMPs)nmOriginalSwipeIMPs=[NSMutableDictionary dictionary];
    int count=objc_getClassList(NULL,0);Class *classes=calloc(count,sizeof(Class));objc_getClassList(classes,count);SEL sel=@selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:);
    for(int i=0;i<count;i++){Class cls=classes[i];NSString*n=NSStringFromClass(cls);if([n rangeOfString:@"Conversation" options:NSCaseInsensitiveSearch].location==NSNotFound&&[n rangeOfString:@"Message" options:NSCaseInsensitiveSearch].location==NSNotFound)continue;unsigned int mc=0;Method *methods=class_copyMethodList(cls,&mc);for(unsigned int j=0;j<mc;j++)if(method_getName(methods[j])==sel){NSString*k=NSStringFromClass(cls);if(!nmOriginalSwipeIMPs[k]){IMP old=method_getImplementation(methods[j]);nmOriginalSwipeIMPs[k]=[NSValue valueWithPointer:old];method_setImplementation(methods[j],(IMP)NMSwipeReplacement);}break;}free(methods);}free(classes);
}

@implementation UIViewController (NMRuntimeV13)
- (void)nm13_viewDidAppear:(BOOL)animated { [self nm13_viewDidAppear:animated]; NMApplyController(self); }
- (void)nm13_viewDidLayoutSubviews { [self nm13_viewDidLayoutSubviews]; NMApplyController(self); }
@end
@implementation UITableViewCell (NMRuntimeV13)
- (void)nm13_layoutSubviews { [self nm13_layoutSubviews]; NMStyleCell(self); }
@end
@implementation UIView (NMRuntimeV13)
- (void)nm13_didMoveToWindow { [self nm13_didMoveToWindow]; NMStyleBubbleView(self); }
@end

static void NMSwizzle(Class c, SEL a, SEL b) { Method m1=class_getInstanceMethod(c,a),m2=class_getInstanceMethod(c,b);if(m1&&m2)method_exchangeImplementations(m1,m2); }
static void NMRefreshAll(void) { for(UIWindowScene*scene in UIApplication.sharedApplication.connectedScenes)for(UIWindow*w in scene.windows){UIViewController*root=w.rootViewController;if(root)NMApplyController(root);for(UIView*v in w.subviews){if([v isKindOfClass:UITableView.class])[(UITableView*)v reloadData];}} }
static void NMChangedCallback(__unused CFNotificationCenterRef c,__unused void*o,__unused CFStringRef n,__unused const void*x,__unused CFDictionaryRef u){NMLoad();dispatch_async(dispatch_get_main_queue(),^{NMRefreshAll();});}

void NMInstallRuntimeV13(void) {
    if(!NMIsMessages())return;NMLoad();NMSwizzle(UIViewController.class,@selector(viewDidAppear:),@selector(nm13_viewDidAppear:));NMSwizzle(UIViewController.class,@selector(viewDidLayoutSubviews),@selector(nm13_viewDidLayoutSubviews));NMSwizzle(UITableViewCell.class,@selector(layoutSubviews),@selector(nm13_layoutSubviews));NMSwizzle(UIView.class,@selector(didMoveToWindow),@selector(nm13_didMoveToWindow));CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NMChangedCallback,(__bridge CFStringRef)NMChanged,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{NMInstallSwipeHooks();NMRefreshAll();});
}
