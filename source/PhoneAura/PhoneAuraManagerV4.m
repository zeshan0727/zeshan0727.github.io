#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"
#import "PAConceptDSurfaces.h"
#import <ContactsUI/ContactsUI.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static CFStringRef const PADomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PAChanged = CFSTR("com.zeshan.phoneaura/preferences.changed");
static const void *PAHeaderKeyV4 = &PAHeaderKeyV4;
static const void *PADockKeyV4 = &PADockKeyV4;
static const void *PAFavoritesKeyV4 = &PAFavoritesKeyV4;
static const void *PARecentsKeyV4 = &PARecentsKeyV4;
static const void *PAContactsKeyV4 = &PAContactsKeyV4;
static const void *PAKeypadKeyV4 = &PAKeypadKeyV4;
static const void *PACardKeyV4 = &PACardKeyV4;
static const void *PABackgroundKeyV4 = &PABackgroundKeyV4;

static id PAReadV4(NSString *key) {
    CFPreferencesAppSynchronize(PADomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, PADomain));
}

static BOOL PABoolV4(NSString *key, BOOL fallback) {
    id value = PAReadV4(key);
    return value ? [value boolValue] : fallback;
}

static CGFloat PAFloatV4(NSString *key, CGFloat fallback) {
    id value = PAReadV4(key);
    return value ? [value doubleValue] : fallback;
}

static NSArray<UIView *> *PASubviewsV4(UIView *view) {
    if (!view) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        [result addObject:subview];
        [result addObjectsFromArray:PASubviewsV4(subview)];
    }
    return result;
}

static UINavigationController *PANavigationV4(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    return [selected isKindOfClass:[UINavigationController class]] ? (UINavigationController *)selected : nil;
}

static UIViewController *PATopV4(UITabBarController *tabController) {
    UINavigationController *navigationController = PANavigationV4(tabController);
    return navigationController ? navigationController.topViewController : tabController.selectedViewController;
}

static BOOL PAIsRootV4(UITabBarController *tabController) {
    UINavigationController *navigationController = PANavigationV4(tabController);
    return !navigationController || navigationController.viewControllers.count <= 1;
}

static UITabBarController *PAFindTabV4(UIViewController *controller) {
    UIViewController *cursor = controller;
    while (cursor) {
        if ([cursor isKindOfClass:[UITabBarController class]]) return (UITabBarController *)cursor;
        if (cursor.tabBarController) return cursor.tabBarController;
        cursor = cursor.parentViewController ?: cursor.presentingViewController;
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:[UITabBarController class]]) return (UITabBarController *)root;
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:[UITabBarController class]]) return (UITabBarController *)child;
        }
    }
    return nil;
}

static BOOL PAViewInsideV4(UIView *view, UIView *ancestor) {
    UIView *cursor = view;
    while (cursor) {
        if (cursor == ancestor) return YES;
        cursor = cursor.superview;
    }
    return NO;
}

@interface PhoneAuraManager ()
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL haptics;
@property(nonatomic) BOOL animations;
@property(nonatomic) BOOL showSubtitles;
@property(nonatomic) BOOL fullFavorites;
@property(nonatomic) BOOL fullRecents;
@property(nonatomic) BOOL fullContacts;
@property(nonatomic) BOOL fullKeypad;
@property(nonatomic) CGFloat cardOpacity;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic,strong) NSArray<NSString *> *favoriteIdentifiers;
@property(nonatomic,weak) UITabBarController *tabController;
@property(nonatomic,strong) PAStudioHeaderView *header;
@property(nonatomic,strong) PAStudioDock *dock;
@end

@implementation PhoneAuraManager

+ (instancetype)sharedManager {
    static PhoneAuraManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reloadPreferences];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        PASettingsChangedV4,
                                        PAChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

static void PASettingsChangedV4(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo) {
    PhoneAuraManager *manager = (__bridge PhoneAuraManager *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{ [manager reloadPreferences]; });
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       PAChanged,
                                       NULL);
}

- (void)reloadPreferences {
    self.enabled = PABoolV4(@"enabled", YES);
    self.haptics = PABoolV4(@"haptics", YES);
    self.animations = PABoolV4(@"animations", YES);
    self.showSubtitles = PABoolV4(@"showSubtitles", YES);
    self.fullFavorites = PABoolV4(@"fullFavorites", YES);
    self.fullRecents = PABoolV4(@"fullRecents", YES);
    self.fullContacts = PABoolV4(@"fullContacts", YES);
    self.fullKeypad = PABoolV4(@"fullKeypad", YES);
    self.cardOpacity = MAX(0.65, MIN(PAFloatV4(@"cardOpacity", 0.96), 1.0));
    self.cornerRadius = MAX(10.0, MIN(PAFloatV4(@"cornerRadius", 16.0), 26.0));
    id identifiers = PAReadV4(@"favoriteIdentifiers");
    self.favoriteIdentifiers = [identifiers isKindOfClass:[NSArray class]] ? identifiers : @[];

    if (!self.tabController) return;
    if (self.enabled) [self applyToTabController:self.tabController animated:NO];
    else [self restoreTabController:self.tabController];
}

- (void)controllerDidAppear:(UIViewController *)controller {
    UITabBarController *tabController = PAFindTabV4(controller);
    if (!tabController) return;
    self.tabController = tabController;
    if (self.enabled) [self applyToTabController:tabController animated:NO];
    else [self restoreTabController:tabController];
}

- (void)controllerDidLayout:(UIViewController *)controller {
    UITabBarController *tabController = PAFindTabV4(controller);
    if (!self.enabled || !tabController || tabController != self.tabController) return;
    [self applyToTabController:tabController animated:NO];
}

- (void)tabSelectionChanged:(UITabBarController *)tabController {
    self.tabController = tabController;
    if (self.enabled) [self applyToTabController:tabController animated:YES];
    else [self restoreTabController:tabController];
}

- (void)applyToTabController:(UITabBarController *)tabController animated:(BOOL)animated {
    if (!tabController.view.window && !tabController.view.superview) return;
    if (!PAIsRootV4(tabController)) {
        [self showSystemNavigation:tabController];
        return;
    }

    tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self installDock:tabController];
    [self installHeader:tabController];
    [self configureChrome:tabController animated:animated];
    [self installSelectedSurface:tabController];
    [self styleFallbackSurface:tabController];
    [tabController.view bringSubviewToFront:self.header];
    [tabController.tabBar bringSubviewToFront:self.dock];
}

- (void)installDock:(UITabBarController *)tabController {
    UITabBar *tabBar = tabController.tabBar;
    PAStudioDock *dock = objc_getAssociatedObject(tabBar, PADockKeyV4);
    if (!dock) {
        dock = [[PAStudioDock alloc] init];
        __weak typeof(self) weakSelf = self;
        __weak UITabBarController *weakTab = tabController;
        dock.selectionHandler = ^(NSUInteger index) {
            UITabBarController *strongTab = weakTab;
            if (!strongTab || index >= strongTab.viewControllers.count) return;
            if (weakSelf.haptics) {
                UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
                [generator selectionChanged];
            }
            strongTab.selectedIndex = index;
            [weakSelf applyToTabController:strongTab animated:YES];
        };
        [tabBar addSubview:dock];
        objc_setAssociatedObject(tabBar, PADockKeyV4, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.dock = dock;
    dock.hidden = NO;
    dock.frame = CGRectInset(tabBar.bounds, 8, 4);
    dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tabBar.backgroundImage = [UIImage new];
    tabBar.shadowImage = [UIImage new];
    tabBar.backgroundColor = UIColor.clearColor;
    tabBar.translucent = YES;
    for (UIView *subview in tabBar.subviews) {
        if (subview == dock) continue;
        NSString *name = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [name containsString:@"Button"]) {
            subview.alpha = 0;
            subview.userInteractionEnabled = NO;
        }
    }
}

- (void)installHeader:(UITabBarController *)tabController {
    PAStudioHeaderView *header = objc_getAssociatedObject(tabController.view, PAHeaderKeyV4);
    if (!header) {
        header = [[PAStudioHeaderView alloc] init];
        __weak typeof(self) weakSelf = self;
        header.actionHandler = ^{ [weakSelf headerAction]; };
        [tabController.view addSubview:header];
        objc_setAssociatedObject(tabController.view, PAHeaderKeyV4, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.header = header;
    header.hidden = NO;
    CGFloat safeTop = tabController.view.safeAreaInsets.top;
    header.frame = CGRectMake(20, safeTop + 2, CGRectGetWidth(tabController.view.bounds) - 40, 66);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
}

- (void)configureChrome:(UITabBarController *)tabController animated:(BOOL)animated {
    NSUInteger index = MIN(tabController.selectedIndex, 4);
    NSArray *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
    NSArray *subtitles = @[@"Your people, one tap away.", @"Your call history at a glance.", @"All your connections.", @"Dial with confidence.", @"Messages that matter."];
    NSArray *icons = @[@"plus", @"arrow.clockwise", @"person.badge.plus", @"ellipsis", @"pencil"];
    [self.header configureTitle:titles[index]
                       subtitle:subtitles[index]
                           icon:icons[index]
                         accent:PAAccentForIndex(index)
                   showSubtitle:self.showSubtitles];
    [self.dock updateSelectedIndex:index animated:(animated && self.animations)];
    UINavigationController *navigationController = PANavigationV4(tabController);
    if (navigationController) navigationController.navigationBarHidden = YES;
    UIViewController *top = PATopV4(tabController);
    top.additionalSafeAreaInsets = UIEdgeInsetsMake(78, 0, 0, 0);
}

- (void)hideAllCustomSurfaces:(UIViewController *)controller except:(UIView *)visible {
    NSArray *keys = @[[NSValue valueWithPointer:PAFavoritesKeyV4],
                      [NSValue valueWithPointer:PARecentsKeyV4],
                      [NSValue valueWithPointer:PAContactsKeyV4],
                      [NSValue valueWithPointer:PAKeypadKeyV4]];
    for (NSValue *value in keys) {
        UIView *surface = objc_getAssociatedObject(controller.view, value.pointerValue);
        if (surface) surface.hidden = surface != visible;
    }
}

- (void)installSelectedSurface:(UITabBarController *)tabController {
    UIViewController *top = PATopV4(tabController);
    if (!top || !top.isViewLoaded) return;
    NSUInteger index = MIN(tabController.selectedIndex, 4);
    UIView *visible = nil;

    if (index == 0 && self.fullFavorites) {
        PAFavoritesDashboardView *surface = objc_getAssociatedObject(top.view, PAFavoritesKeyV4);
        if (!surface) {
            surface = [[PAFavoritesDashboardView alloc] initWithFrame:top.view.bounds];
            surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            __weak typeof(self) weakSelf = self;
            surface.callHandler = ^(NSString *number) { [weakSelf callNumber:number]; };
            surface.settingsHandler = ^{ [weakSelf openStudioApp]; };
            [top.view addSubview:surface];
            objc_setAssociatedObject(top.view, PAFavoritesKeyV4, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface.hapticsEnabled = self.haptics;
        [surface reloadFavoriteIdentifiers:self.favoriteIdentifiers];
        visible = surface;
    } else if (index == 1 && self.fullRecents) {
        PARecentsDashboardView *surface = objc_getAssociatedObject(top.view, PARecentsKeyV4);
        if (!surface) {
            surface = [[PARecentsDashboardView alloc] initWithFrame:top.view.bounds];
            surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            __weak typeof(self) weakSelf = self;
            surface.callHandler = ^(NSString *number) { [weakSelf callNumber:number]; };
            [top.view addSubview:surface];
            objc_setAssociatedObject(top.view, PARecentsKeyV4, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface.hapticsEnabled = self.haptics;
        [surface refresh];
        visible = surface;
    } else if (index == 2 && self.fullContacts) {
        PAContactsDashboardView *surface = objc_getAssociatedObject(top.view, PAContactsKeyV4);
        if (!surface) {
            surface = [[PAContactsDashboardView alloc] initWithFrame:top.view.bounds];
            surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            __weak typeof(self) weakSelf = self;
            surface.contactHandler = ^(CNContact *contact) { [weakSelf showContact:contact]; };
            [top.view addSubview:surface];
            objc_setAssociatedObject(top.view, PAContactsKeyV4, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface.hapticsEnabled = self.haptics;
        visible = surface;
    } else if (index == 3 && self.fullKeypad) {
        PAStudioKeypadView *surface = objc_getAssociatedObject(top.view, PAKeypadKeyV4);
        if (!surface) {
            surface = [[PAStudioKeypadView alloc] initWithFrame:top.view.bounds];
            surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [top.view addSubview:surface];
            objc_setAssociatedObject(top.view, PAKeypadKeyV4, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface.backgroundColor = PAColorHex(0x040817,1);
        surface.hapticsEnabled = self.haptics;
        surface.animationsEnabled = self.animations;
        surface.studioCornerRadius = self.cornerRadius;
        visible = surface;
    }

    [self hideAllCustomSurfaces:top except:visible];
    if (visible) {
        visible.hidden = NO;
        visible.frame = top.view.bounds;
        [top.view bringSubviewToFront:visible];
    }
}

- (void)styleFallbackSurface:(UITabBarController *)tabController {
    UIViewController *top = PATopV4(tabController);
    NSUInteger index = MIN(tabController.selectedIndex, 4);
    BOOL custom = (index == 0 && self.fullFavorites) || (index == 1 && self.fullRecents) || (index == 2 && self.fullContacts) || (index == 3 && self.fullKeypad);
    if (custom || !top.isViewLoaded) return;

    CAGradientLayer *background = objc_getAssociatedObject(top.view, PABackgroundKeyV4);
    if (!background) {
        background = [CAGradientLayer layer];
        [top.view.layer insertSublayer:background atIndex:0];
        objc_setAssociatedObject(top.view, PABackgroundKeyV4, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    background.frame = top.view.bounds;
    background.colors = @[(id)[PAAccentForIndex(index) colorWithAlphaComponent:0.15].CGColor,
                          (id)PAColorHex(0x08132B,1).CGColor,
                          (id)PAColorHex(0x030712,1).CGColor];
    top.view.backgroundColor = PAColorHex(0x030712,1);
    for (UIView *view in PASubviewsV4(top.view)) {
        if ([view isKindOfClass:[UITableView class]]) [self styleTableView:(UITableView *)view tabIndex:index];
        else if ([view isKindOfClass:[UIScrollView class]]) view.backgroundColor = UIColor.clearColor;
    }
}

- (void)styleTableView:(UITableView *)tableView tabIndex:(NSUInteger)tabIndex {
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    for (UITableViewCell *cell in tableView.visibleCells) {
        NSIndexPath *indexPath = [tableView indexPathForCell:cell];
        PAStudioCardBackgroundView *background = objc_getAssociatedObject(cell, PACardKeyV4);
        if (!background) {
            background = [[PAStudioCardBackgroundView alloc] initWithFrame:cell.bounds];
            cell.backgroundView = background;
            objc_setAssociatedObject(cell, PACardKeyV4, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [background configureForTab:tabIndex row:indexPath.row opacity:self.cardOpacity cornerRadius:self.cornerRadius];
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.tintColor = PAAccentForIndex(tabIndex);
    }
}

- (void)tableViewDidLayout:(UITableView *)tableView {
    if (!self.enabled || !self.tabController || !PAIsRootV4(self.tabController)) return;
    NSUInteger index = MIN(self.tabController.selectedIndex, 4);
    if (index != 4) return;
    UIViewController *top = PATopV4(self.tabController);
    if (top && PAViewInsideV4(tableView, top.view)) [self styleTableView:tableView tabIndex:index];
}

- (void)collectionViewDidLayout:(UICollectionView *)collectionView {
}

- (void)showContact:(CNContact *)contact {
    UINavigationController *navigationController = PANavigationV4(self.tabController);
    if (!navigationController || !contact) return;
    CNContactViewController *controller = [CNContactViewController viewControllerForContact:contact];
    controller.allowsEditing = YES;
    controller.allowsActions = YES;
    [navigationController pushViewController:controller animated:YES];
}

- (void)callNumber:(NSString *)number {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < number.length; index++) {
        NSString *character = [number substringWithRange:NSMakeRange(index, 1)];
        if ([character rangeOfCharacterFromSet:allowed].location != NSNotFound) [clean appendString:character];
    }
    if (!clean.length) return;
    NSString *escaped = [clean stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", escaped ?: clean]];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)headerAction {
    NSUInteger index = MIN(self.tabController.selectedIndex, 4);
    UIViewController *top = PATopV4(self.tabController);
    if (index == 0) [self openStudioApp];
    else if (index == 1) {
        PARecentsDashboardView *surface = objc_getAssociatedObject(top.view, PARecentsKeyV4);
        [surface refresh];
    } else if (index == 2) [self openStudioApp];
    else if (index == 3) {
        PAStudioKeypadView *surface = objc_getAssociatedObject(top.view, PAKeypadKeyV4);
        [surface clearNumber];
    } else [self openStudioApp];
}

- (void)openStudioApp {
    NSURL *url = [NSURL URLWithString:@"phoneaurastudio://settings"];
    if (url && [UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    NSURL *fallback = [NSURL URLWithString:@"App-prefs:root=PhoneAura"];
    if (fallback) [UIApplication.sharedApplication openURL:fallback options:@{} completionHandler:nil];
}

- (void)showSystemNavigation:(UITabBarController *)tabController {
    self.header.hidden = YES;
    self.dock.hidden = YES;
    for (UIView *subview in tabController.tabBar.subviews) {
        if (subview == self.dock) continue;
        NSString *name = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [name containsString:@"Button"]) {
            subview.alpha = 1;
            subview.userInteractionEnabled = YES;
        }
    }
    UINavigationController *navigationController = PANavigationV4(tabController);
    if (navigationController) navigationController.navigationBarHidden = NO;
    UIViewController *top = PATopV4(tabController);
    top.additionalSafeAreaInsets = UIEdgeInsetsZero;
}

- (void)restoreTabController:(UITabBarController *)tabController {
    [self showSystemNavigation:tabController];
    tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    UIViewController *top = PATopV4(tabController);
    [self hideAllCustomSurfaces:top except:nil];
}

@end
