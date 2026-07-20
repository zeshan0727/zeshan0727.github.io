#import "PhoneAuraManager.h"
#import <QuartzCore/QuartzCore.h>

static CFStringRef const PAPreferencesDomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PAPreferencesChangedNotification = CFSTR("com.zeshan.phoneaura/preferences.changed");

static id PAReadPreference(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PAPreferencesDomain);
    return CFBridgingRelease(value);
}

@class PhoneAuraManager;
static void PAPreferencesChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    PhoneAuraManager *manager = (__bridge PhoneAuraManager *)observer;
    [manager reloadPreferences];
}

@interface PAOrbitButton : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, assign) NSInteger tabIndex;
- (instancetype)initWithIconName:(NSString *)iconName title:(NSString *)title index:(NSInteger)index;
- (void)applyAccentColor:(UIColor *)accent active:(BOOL)active;
@end

@implementation PAOrbitButton

- (instancetype)initWithIconName:(NSString *)iconName title:(NSString *)title index:(NSInteger)index {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _tabIndex = index;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.cornerRadius = 19.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = title;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    UIImageSymbolConfiguration *symbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:iconName withConfiguration:symbolConfiguration];

    _iconView = [[UIImageView alloc] initWithImage:image];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;

    _captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _captionLabel.text = title;
    _captionLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightSemibold];
    _captionLabel.textAlignment = NSTextAlignmentCenter;
    _captionLabel.adjustsFontSizeToFitWidth = YES;
    _captionLabel.minimumScaleFactor = 0.72;

    UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _captionLabel]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentCenter;
    contentStack.distribution = UIStackViewDistributionFill;
    contentStack.spacing = 1.0;
    contentStack.userInteractionEnabled = NO;
    [self addSubview:contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [contentStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [contentStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2.0],
        [contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2.0],
        [_iconView.widthAnchor constraintEqualToConstant:21.0],
        [_iconView.heightAnchor constraintEqualToConstant:21.0],
        [self.heightAnchor constraintEqualToConstant:42.0]
    ]];

    return self;
}

- (void)applyAccentColor:(UIColor *)accent active:(BOOL)active {
    UIColor *inactiveColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    self.iconView.tintColor = active ? accent : inactiveColor;
    self.captionLabel.textColor = active ? UIColor.whiteColor : inactiveColor;
    self.backgroundColor = active ? [accent colorWithAlphaComponent:0.24] : UIColor.clearColor;
    self.layer.borderWidth = active ? 0.7 : 0.0;
    self.layer.borderColor = active ? [accent colorWithAlphaComponent:0.45].CGColor : UIColor.clearColor.CGColor;
    self.accessibilityTraits = active ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

@end

@interface PhoneAuraManager ()
@property (nonatomic, weak) UITabBarController *tabController;
@property (nonatomic, strong) UIVisualEffectView *dockView;
@property (nonatomic, strong) UIStackView *dockStack;
@property (nonatomic, copy) NSArray<PAOrbitButton *> *dockButtons;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL hapticsEnabled;
@property (nonatomic, assign) BOOL animationsEnabled;
@property (nonatomic, assign) BOOL forceDark;
@property (nonatomic, assign) NSInteger accentStyle;
@property (nonatomic, assign) CGFloat glassIntensity;
@property (nonatomic, assign) BOOL capturedOriginalTabBarState;
@property (nonatomic, assign) CGFloat originalTabBarAlpha;
@property (nonatomic, assign) BOOL originalTabBarInteractionEnabled;
@property (nonatomic, assign) BOOL originalTabBarAccessibilityHidden;
@end

@implementation PhoneAuraManager

+ (instancetype)sharedManager {
    static PhoneAuraManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[PhoneAuraManager alloc] initPrivate];
    });
    return manager;
}

- (instancetype)init {
    return [PhoneAuraManager sharedManager];
}

- (instancetype)initPrivate {
    self = [super init];
    if (!self) return nil;

    _enabled = YES;
    _hapticsEnabled = YES;
    _animationsEnabled = YES;
    _forceDark = YES;
    _accentStyle = 0;
    _glassIntensity = 0.72;

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    PAPreferencesChangedCallback,
                                    PAPreferencesChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    [self reloadPreferences];
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)(self),
                                       PAPreferencesChangedNotification,
                                       NULL);
}

- (UIColor *)accentColor {
    switch (self.accentStyle) {
        case 1:
            return [UIColor colorWithRed:0.67 green:0.36 blue:1.0 alpha:1.0];
        case 2:
            return [UIColor colorWithRed:0.12 green:0.86 blue:0.56 alpha:1.0];
        case 3:
            return [UIColor colorWithRed:1.0 green:0.43 blue:0.23 alpha:1.0];
        default:
            return [UIColor colorWithRed:0.08 green:0.66 blue:1.0 alpha:1.0];
    }
}

- (UITabBarController *)tabControllerForController:(UIViewController *)controller {
    if ([controller isKindOfClass:UITabBarController.class]) {
        return (UITabBarController *)controller;
    }
    if (controller.tabBarController) {
        return controller.tabBarController;
    }

    UIViewController *cursor = controller.parentViewController;
    while (cursor) {
        if ([cursor isKindOfClass:UITabBarController.class]) {
            return (UITabBarController *)cursor;
        }
        cursor = cursor.parentViewController;
    }
    return nil;
}

- (void)captureTabBarStateIfNeeded:(UITabBarController *)tabController {
    if (self.capturedOriginalTabBarState) return;
    self.capturedOriginalTabBarState = YES;
    self.originalTabBarAlpha = tabController.tabBar.alpha;
    self.originalTabBarInteractionEnabled = tabController.tabBar.userInteractionEnabled;
    self.originalTabBarAccessibilityHidden = tabController.tabBar.accessibilityElementsHidden;
}

- (void)restoreStockTabBar {
    UITabBarController *tabController = self.tabController;
    if (tabController && self.capturedOriginalTabBarState) {
        tabController.tabBar.alpha = self.originalTabBarAlpha;
        tabController.tabBar.userInteractionEnabled = self.originalTabBarInteractionEnabled;
        tabController.tabBar.accessibilityElementsHidden = self.originalTabBarAccessibilityHidden;
    }
    [self.dockView removeFromSuperview];
    self.dockView = nil;
    self.dockStack = nil;
    self.dockButtons = nil;
    self.capturedOriginalTabBarState = NO;
}

- (void)attachToTabController:(UITabBarController *)tabController {
    if (!self.enabled || !tabController || tabController.viewControllers.count == 0) return;

    if (self.tabController != tabController) {
        [self restoreStockTabBar];
        self.tabController = tabController;
    }

    [self captureTabBarStateIfNeeded:tabController];

    // Keep Apple's real tab bar in the layout so every Phone screen retains its
    // correct safe area. Only its drawing and touch handling are replaced.
    tabController.tabBar.alpha = 0.0;
    tabController.tabBar.userInteractionEnabled = NO;
    tabController.tabBar.accessibilityElementsHidden = YES;

    if (!self.dockView || self.dockView.superview != tabController.view) {
        [self buildDockInTabController:tabController];
    }

    [tabController.view bringSubviewToFront:self.dockView];
    [self updateDockSelection];
    [self updateDockVisibility];
}

- (void)buildDockInTabController:(UITabBarController *)tabController {
    [self.dockView removeFromSuperview];

    UIBlurEffectStyle blurStyle = self.forceDark ? UIBlurEffectStyleSystemUltraThinMaterialDark
                                                  : UIBlurEffectStyleSystemUltraThinMaterial;
    UIVisualEffectView *dock = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.clipsToBounds = NO;
    dock.layer.cornerRadius = 27.0;
    dock.layer.cornerCurve = kCACornerCurveContinuous;
    dock.layer.masksToBounds = NO;
    dock.layer.borderWidth = 0.8;
    dock.layer.borderColor = [[self accentColor] colorWithAlphaComponent:0.24].CGColor;
    dock.layer.shadowColor = [self accentColor].CGColor;
    dock.layer.shadowOpacity = 0.22;
    dock.layer.shadowRadius = 16.0;
    dock.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    dock.overrideUserInterfaceStyle = self.forceDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    dock.contentView.backgroundColor = [[self accentColor] colorWithAlphaComponent:0.035 * self.glassIntensity];

    NSArray<NSString *> *icons = @[
        @"star.fill",
        @"clock.arrow.circlepath",
        @"person.2.fill",
        @"circle.grid.3x3.fill",
        @"recordingtape"
    ];
    NSArray<NSString *> *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];

    NSMutableArray<PAOrbitButton *> *buttons = [NSMutableArray arrayWithCapacity:5];
    for (NSInteger index = 0; index < 5; index++) {
        PAOrbitButton *button = [[PAOrbitButton alloc] initWithIconName:icons[index]
                                                                 title:titles[index]
                                                                 index:index];
        [button addTarget:self action:@selector(dockButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 3.0;
    [dock.contentView addSubview:stack];
    [tabController.view addSubview:dock];

    [NSLayoutConstraint activateConstraints:@[
        [dock.leadingAnchor constraintEqualToAnchor:tabController.view.leadingAnchor constant:16.0],
        [dock.trailingAnchor constraintEqualToAnchor:tabController.view.trailingAnchor constant:-16.0],
        [dock.centerYAnchor constraintEqualToAnchor:tabController.tabBar.centerYAnchor constant:-1.0],
        [dock.heightAnchor constraintEqualToConstant:58.0],
        [stack.leadingAnchor constraintEqualToAnchor:dock.contentView.leadingAnchor constant:7.0],
        [stack.trailingAnchor constraintEqualToAnchor:dock.contentView.trailingAnchor constant:-7.0],
        [stack.topAnchor constraintEqualToAnchor:dock.contentView.topAnchor constant:7.0],
        [stack.bottomAnchor constraintEqualToAnchor:dock.contentView.bottomAnchor constant:-7.0]
    ]];

    self.dockView = dock;
    self.dockStack = stack;
    self.dockButtons = buttons;
}

- (void)dockButtonPressed:(PAOrbitButton *)sender {
    UITabBarController *tabController = self.tabController;
    NSInteger index = sender.tabIndex;
    if (!tabController || index < 0 || index >= (NSInteger)tabController.viewControllers.count) return;

    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }

    tabController.selectedIndex = (NSUInteger)index;
    [self updateDockSelection];

    if (self.animationsEnabled) {
        sender.transform = CGAffineTransformMakeScale(0.88, 0.88);
        [UIView animateWithDuration:0.34
                              delay:0.0
             usingSpringWithDamping:0.58
              initialSpringVelocity:0.7
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            sender.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)updateDockSelection {
    UITabBarController *tabController = self.tabController;
    if (!tabController || !self.dockButtons) return;

    NSUInteger selectedIndex = tabController.selectedIndex;
    UIColor *accent = [self accentColor];
    [self.dockButtons enumerateObjectsUsingBlock:^(PAOrbitButton *button, NSUInteger index, BOOL *stop) {
        [button applyAccentColor:accent active:(index == selectedIndex)];
    }];
}

- (void)updateDockVisibility {
    UITabBarController *tabController = self.tabController;
    if (!tabController || !self.dockView) return;

    BOOL shouldHide = tabController.tabBar.hidden || tabController.presentedViewController != nil;
    self.dockView.hidden = shouldHide;
}

- (void)controllerDidAppear:(UIViewController *)controller {
    if (!self.enabled || !controller) return;
    UITabBarController *tabController = [self tabControllerForController:controller];
    if (tabController) {
        [self attachToTabController:tabController];
    }
}

- (void)tabSelectionChanged:(UITabBarController *)tabController {
    if (!self.enabled) return;
    [self attachToTabController:tabController];
}

- (void)tableViewDidLayout:(UITableView *)tableView {
    // Intentionally left untouched in the safety architecture. Global table
    // styling caused the overlapping rows seen in PhoneAura 0.1 and 0.2.
}

- (void)reloadPreferences {
    id enabledValue = PAReadPreference(@"enabled");
    id hapticsValue = PAReadPreference(@"haptics");
    id animationsValue = PAReadPreference(@"animations");
    id forceDarkValue = PAReadPreference(@"forceDark");
    id accentValue = PAReadPreference(@"accentStyle");
    id intensityValue = PAReadPreference(@"glassIntensity");

    self.enabled = enabledValue ? [enabledValue boolValue] : YES;
    self.hapticsEnabled = hapticsValue ? [hapticsValue boolValue] : YES;
    self.animationsEnabled = animationsValue ? [animationsValue boolValue] : YES;
    self.forceDark = forceDarkValue ? [forceDarkValue boolValue] : YES;
    self.accentStyle = accentValue ? [accentValue integerValue] : 0;
    self.glassIntensity = intensityValue ? MAX(0.35, MIN(1.0, [intensityValue doubleValue])) : 0.72;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.enabled) {
            [self restoreStockTabBar];
            return;
        }

        UITabBarController *tabController = self.tabController;
        if (tabController) {
            [self.dockView removeFromSuperview];
            self.dockView = nil;
            self.dockButtons = nil;
            self.dockStack = nil;
            [self attachToTabController:tabController];
        }
    });
}

@end
