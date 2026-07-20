#import "PhoneAuraManager.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static CFStringRef const PAPreferencesDomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PAPreferencesChanged = CFSTR("com.zeshan.phoneaura/preferences.changed");

static const void *PAHeaderKey = &PAHeaderKey;
static const void *PADockKey = &PADockKey;
static const void *PACardKey = &PACardKey;
static const void *PAGradientKey = &PAGradientKey;
static const void *PANumberBackdropKey = &PANumberBackdropKey;
static const void *PAShortcutsKey = &PAShortcutsKey;

static void PAPreferencesDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

static UIColor *PAColorHex(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

static UIColor *PAAccentForIndex(NSUInteger index) {
    switch (index) {
        case 0: return PAColorHex(0xFF5A5F, 1.0);
        case 1: return PAColorHex(0x6C63FF, 1.0);
        case 2: return PAColorHex(0x16C7B7, 1.0);
        case 3: return PAColorHex(0xFF7A1A, 1.0);
        case 4: return PAColorHex(0xFF3D87, 1.0);
        default: return PAColorHex(0x6C63FF, 1.0);
    }
}

static NSArray<UIColor *> *PAPaletteForIndex(NSUInteger index) {
    switch (index) {
        case 0:
            return @[PAColorHex(0xFF5A5F,1), PAColorHex(0x7C4DFF,1), PAColorHex(0x13BFC0,1), PAColorHex(0xFF7A1A,1)];
        case 1:
            return @[PAColorHex(0xFF5A5F,1), PAColorHex(0x16C7B7,1), PAColorHex(0x3B82F6,1), PAColorHex(0xA855F7,1), PAColorHex(0x22C55E,1)];
        case 2:
            return @[PAColorHex(0x16C7B7,1), PAColorHex(0x0EA5E9,1), PAColorHex(0x22C55E,1)];
        case 4:
            return @[PAColorHex(0xFF3D87,1), PAColorHex(0xFF8A1F,1), PAColorHex(0x8B5CF6,1)];
        default:
            return @[PAAccentForIndex(index)];
    }
}

static id PAReadPreference(NSString *key) {
    CFPreferencesAppSynchronize(PAPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PAPreferencesDomain);
    return CFBridgingRelease(value);
}

static BOOL PABoolPreference(NSString *key, BOOL fallback) {
    id value = PAReadPreference(key);
    return value ? [value boolValue] : fallback;
}

static CGFloat PAFloatPreference(NSString *key, CGFloat fallback) {
    id value = PAReadPreference(key);
    return value ? [value doubleValue] : fallback;
}

static NSArray<UIView *> *PAAllSubviews(UIView *view) {
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        [result addObject:subview];
        [result addObjectsFromArray:PAAllSubviews(subview)];
    }
    return result;
}

static BOOL PAViewIsDescendantOf(UIView *view, UIView *ancestor) {
    if (!view || !ancestor) return NO;
    UIView *cursor = view;
    while (cursor) {
        if (cursor == ancestor) return YES;
        cursor = cursor.superview;
    }
    return NO;
}

static UIViewController *PATabRoot(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController *)selected).viewControllers.firstObject;
    }
    return selected;
}

static UIViewController *PATabTop(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController *)selected).topViewController;
    }
    return selected;
}

static BOOL PAIsRootVisible(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController *)selected).viewControllers.count <= 1;
    }
    return YES;
}

static UITabBarController *PAFindTabController(UIViewController *controller) {
    UIViewController *cursor = controller;
    while (cursor) {
        if ([cursor isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)cursor;
        }
        if (cursor.tabBarController) {
            return cursor.tabBarController;
        }
        cursor = cursor.parentViewController ?: cursor.presentingViewController;
    }

    UIWindow *window = controller.view.window ?: UIApplication.sharedApplication.keyWindow;
    UIViewController *root = window.rootViewController;
    if ([root isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)root;
    }
    for (UIViewController *child in root.childViewControllers) {
        if ([child isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)child;
        }
    }
    return nil;
}

static void PAStyleLabelsInView(UIView *view) {
    for (UIView *subview in PAAllSubviews(view)) {
        if (![subview isKindOfClass:[UILabel class]]) continue;
        UILabel *label = (UILabel *)subview;
        if (label.textColor && CGColorGetAlpha(label.textColor.CGColor) < 0.05) continue;

        CGFloat r=0,g=0,b=0,a=0;
        if ([label.textColor getRed:&r green:&g blue:&b alpha:&a]) {
            BOOL keepSemanticColor = (r > 0.7 && g < 0.45) || (g > 0.55 && r < 0.45) || (b > 0.65 && r < 0.45);
            if (keepSemanticColor) continue;
        }

        if (label.font.pointSize >= 16.0 || (label.font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold)) {
            label.textColor = UIColor.whiteColor;
        } else {
            label.textColor = PAColorHex(0xAAB4CC, 1.0);
        }
    }
}

@interface PAStudioHeaderView : UIView
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIButton *actionButton;
@property(nonatomic,strong) CAGradientLayer *accentGlow;
@property(nonatomic,copy) void (^actionHandler)(void);
- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon accent:(UIColor *)accent showSubtitle:(BOOL)showSubtitle;
@end

@implementation PAStudioHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;

        _accentGlow = [CAGradientLayer layer];
        _accentGlow.startPoint = CGPointMake(0.0, 0.5);
        _accentGlow.endPoint = CGPointMake(1.0, 0.5);
        _accentGlow.opacity = 0.35;
        [self.layer insertSublayer:_accentGlow atIndex:0];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.72;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = PAColorHex(0xAAB4CC, 1.0);
        [self addSubview:_subtitleLabel];

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.tintColor = UIColor.whiteColor;
        _actionButton.backgroundColor = PAColorHex(0x17213D, 0.96);
        _actionButton.layer.cornerRadius = 15.0;
        _actionButton.layer.shadowOpacity = 0.22;
        _actionButton.layer.shadowRadius = 12.0;
        _actionButton.layer.shadowOffset = CGSizeMake(0, 5);
        [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_actionButton];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat buttonSize = 46.0;
    self.actionButton.frame = CGRectMake(CGRectGetWidth(self.bounds)-buttonSize, 7.0, buttonSize, buttonSize);
    CGFloat textWidth = CGRectGetMinX(self.actionButton.frame)-12.0;
    self.titleLabel.frame = CGRectMake(0, 0, textWidth, 43.0);
    self.subtitleLabel.frame = CGRectMake(1, 42.0, textWidth, 24.0);
    self.accentGlow.frame = CGRectMake(-20, 0, CGRectGetWidth(self.bounds)*0.72, CGRectGetHeight(self.bounds));
}

- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon accent:(UIColor *)accent showSubtitle:(BOOL)showSubtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = !showSubtitle;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    UIImage *image = [UIImage systemImageNamed:icon withConfiguration:configuration];
    [self.actionButton setImage:image forState:UIControlStateNormal];
    self.actionButton.backgroundColor = [accent colorWithAlphaComponent:0.88];
    self.actionButton.layer.shadowColor = accent.CGColor;
    self.accentGlow.colors = @[(id)[accent colorWithAlphaComponent:0.30].CGColor,
                               (id)[accent colorWithAlphaComponent:0.0].CGColor];
    [self setNeedsLayout];
}

- (void)actionTapped {
    if (self.actionHandler) self.actionHandler();
}

@end

@interface PAStudioDockButton : UIControl
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UIView *selectionBubble;
@property(nonatomic,strong) UIColor *accent;
@property(nonatomic) NSUInteger itemIndex;
- (void)configureTitle:(NSString *)title icon:(NSString *)icon index:(NSUInteger)index;
- (void)setStudioSelected:(BOOL)selected animated:(BOOL)animated;
@end

@implementation PAStudioDockButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _selectionBubble = [[UIView alloc] init];
        _selectionBubble.userInteractionEnabled = NO;
        _selectionBubble.layer.cornerRadius = 18.0;
        _selectionBubble.alpha = 0.0;
        [self addSubview:_selectionBubble];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = PAColorHex(0xAAB4CC, 1.0);
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.textColor = PAColorHex(0xAAB4CC, 1.0);
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.7;
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)configureTitle:(NSString *)title icon:(NSString *)icon index:(NSUInteger)index {
    self.itemIndex = index;
    self.accent = PAAccentForIndex(index);
    self.titleLabel.text = title;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    self.iconView.image = [UIImage systemImageNamed:icon withConfiguration:configuration];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat centerX = CGRectGetMidX(self.bounds);
    self.selectionBubble.frame = CGRectMake(centerX-18.0, 5.0, 36.0, 36.0);
    self.iconView.frame = CGRectMake(centerX-12.0, 11.0, 24.0, 24.0);
    self.titleLabel.frame = CGRectMake(2.0, 43.0, CGRectGetWidth(self.bounds)-4.0, 16.0);
}

- (void)setStudioSelected:(BOOL)selected animated:(BOOL)animated {
    void (^changes)(void) = ^{
        self.selectionBubble.alpha = selected ? 1.0 : 0.0;
        self.selectionBubble.backgroundColor = [self.accent colorWithAlphaComponent:0.25];
        self.iconView.tintColor = selected ? self.accent : PAColorHex(0xAAB4CC, 1.0);
        self.titleLabel.textColor = selected ? self.accent : PAColorHex(0xAAB4CC, 1.0);
        self.iconView.transform = selected ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
    };
    if (animated) {
        [UIView animateWithDuration:0.24 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:changes completion:nil];
    } else {
        changes();
    }
}

@end

@interface PAStudioDock : UIView
@property(nonatomic,strong) UIVisualEffectView *blurView;
@property(nonatomic,strong) NSArray<PAStudioDockButton *> *buttons;
@property(nonatomic,weak) UITabBarController *tabController;
@property(nonatomic,copy) void (^selectionHandler)(NSUInteger index);
- (void)updateSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated;
@end

@implementation PAStudioDock

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 24.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = NO;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.38;
        self.layer.shadowRadius = 20.0;
        self.layer.shadowOffset = CGSizeMake(0, 8);

        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
        _blurView.layer.cornerRadius = 24.0;
        _blurView.layer.cornerCurve = kCACornerCurveContinuous;
        _blurView.clipsToBounds = YES;
        _blurView.backgroundColor = PAColorHex(0x10192F, 0.76);
        [self addSubview:_blurView];

        NSArray *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
        NSArray *icons = @[@"star.fill", @"clock.fill", @"person.fill", @"circle.grid.3x3.fill", @"recordingtape"];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger index=0; index<titles.count; index++) {
            PAStudioDockButton *button = [[PAStudioDockButton alloc] init];
            [button configureTitle:titles[index] icon:icons[index] index:index];
            [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
        }
        _buttons = buttons;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.blurView.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds) / MAX(self.buttons.count, 1);
    [self.buttons enumerateObjectsUsingBlock:^(PAStudioDockButton *button, NSUInteger index, BOOL *stop) {
        button.frame = CGRectMake(width*index, 0, width, CGRectGetHeight(self.bounds));
    }];
}

- (void)buttonTapped:(PAStudioDockButton *)sender {
    if (self.selectionHandler) self.selectionHandler(sender.itemIndex);
}

- (void)updateSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated {
    [self.buttons enumerateObjectsUsingBlock:^(PAStudioDockButton *button, NSUInteger index, BOOL *stop) {
        [button setStudioSelected:(index == selectedIndex) animated:animated];
    }];
}

@end

@interface PACardBackgroundView : UIView
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIView *accentStrip;
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic) CGFloat cornerRadius;
- (void)configureAccent:(UIColor *)accent strong:(BOOL)strong opacity:(CGFloat)opacity cornerRadius:(CGFloat)cornerRadius;
@end

@implementation PACardBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _card = [[UIView alloc] init];
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.7;
        _card.layer.shadowColor = UIColor.blackColor.CGColor;
        _card.layer.shadowOpacity = 0.20;
        _card.layer.shadowRadius = 10.0;
        _card.layer.shadowOffset = CGSizeMake(0, 5);
        [self addSubview:_card];

        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0.0, 0.0);
        _gradient.endPoint = CGPointMake(1.0, 1.0);
        [_card.layer insertSublayer:_gradient atIndex:0];

        _accentStrip = [[UIView alloc] init];
        [_card addSubview:_accentStrip];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.card.frame = CGRectInset(self.bounds, 13.0, 4.5);
    self.card.layer.cornerRadius = self.cornerRadius;
    self.gradient.frame = self.card.bounds;
    self.gradient.cornerRadius = self.cornerRadius;
    self.accentStrip.frame = CGRectMake(0, 0, 5.0, CGRectGetHeight(self.card.bounds));
    self.accentStrip.layer.cornerRadius = 2.5;
}

- (void)configureAccent:(UIColor *)accent strong:(BOOL)strong opacity:(CGFloat)opacity cornerRadius:(CGFloat)cornerRadius {
    self.cornerRadius = cornerRadius;
    CGFloat strength = strong ? 0.72 : 0.24;
    UIColor *start = [accent colorWithAlphaComponent:strength * opacity];
    UIColor *end = PAColorHex(0x16213D, (strong ? 0.92 : 0.82) * opacity);
    self.gradient.colors = @[(id)start.CGColor, (id)end.CGColor];
    self.card.layer.borderColor = [accent colorWithAlphaComponent:strong ? 0.44 : 0.18].CGColor;
    self.card.layer.shadowColor = [accent colorWithAlphaComponent:0.45].CGColor;
    self.accentStrip.backgroundColor = accent;
    [self setNeedsLayout];
}

@end

@interface PAShortcutsView : UIView
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) NSArray<UIButton *> *buttons;
@property(nonatomic,copy) void (^tapHandler)(NSUInteger index);
@end

@implementation PAShortcutsView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"Smart Shortcuts";
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        [self addSubview:_titleLabel];

        NSArray *titles = @[@"Family Group", @"Work Line", @"Voicemail", @"Create Shortcut"];
        NSArray *icons = @[@"person.2.fill", @"briefcase.fill", @"recordingtape", @"plus"];
        NSArray *colors = @[PAColorHex(0x7C4DFF,1), PAColorHex(0xFF7A1A,1), PAColorHex(0x16C7B7,1), PAColorHex(0x24304E,1)];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger index=0; index<titles.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = index;
            button.tintColor = UIColor.whiteColor;
            button.backgroundColor = [colors[index] colorWithAlphaComponent:0.92];
            button.layer.cornerRadius = 13.0;
            button.layer.cornerCurve = kCACornerCurveContinuous;
            button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 8);
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
            [button setImage:[UIImage systemImageNamed:icons[index] withConfiguration:configuration] forState:UIControlStateNormal];
            [button setTitle:[@"  " stringByAppendingString:titles[index]] forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            [button addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
        }
        _buttons = buttons;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(16, 6, CGRectGetWidth(self.bounds)-32, 24);
    CGFloat gap = 9.0;
    CGFloat width = (CGRectGetWidth(self.bounds)-32-gap)/2.0;
    CGFloat height = 48.0;
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        NSUInteger row = index / 2;
        NSUInteger column = index % 2;
        button.frame = CGRectMake(16 + column*(width+gap), 36 + row*(height+gap), width, height);
    }];
}

- (void)shortcutTapped:(UIButton *)sender {
    if (self.tapHandler) self.tapHandler(sender.tag);
}

@end

@interface PhoneAuraManager ()
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL haptics;
@property(nonatomic) BOOL animations;
@property(nonatomic) BOOL forceDark;
@property(nonatomic) BOOL showSubtitles;
@property(nonatomic) BOOL showShortcuts;
@property(nonatomic) BOOL styleKeypad;
@property(nonatomic) CGFloat cardOpacity;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic,weak) UITabBarController *tabController;
@property(nonatomic,strong) PAStudioDock *dock;
@property(nonatomic,strong) PAStudioHeaderView *header;
@end

@implementation PhoneAuraManager

+ (instancetype)sharedManager {
    static PhoneAuraManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reloadPreferences];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        PAPreferencesDidChange,
                                        PAPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

static void PAPreferencesDidChange(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    PhoneAuraManager *manager = (__bridge PhoneAuraManager *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [manager reloadPreferences];
    });
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       PAPreferencesChanged,
                                       NULL);
}

- (void)reloadPreferences {
    self.enabled = PABoolPreference(@"enabled", YES);
    self.haptics = PABoolPreference(@"haptics", YES);
    self.animations = PABoolPreference(@"animations", YES);
    self.forceDark = PABoolPreference(@"forceDark", YES);
    self.showSubtitles = PABoolPreference(@"showSubtitles", YES);
    self.showShortcuts = PABoolPreference(@"showShortcuts", YES);
    self.styleKeypad = PABoolPreference(@"styleKeypad", YES);
    self.cardOpacity = PAFloatPreference(@"cardOpacity", 0.94);
    self.cornerRadius = PAFloatPreference(@"cornerRadius", 16.0);

    if (self.tabController) {
        if (self.enabled) {
            [self applyToTabController:self.tabController animated:NO];
        } else {
            [self removeStudioFromTabController:self.tabController];
        }
    }
}

- (void)controllerDidAppear:(UIViewController *)controller {
    if (!self.enabled) return;
    UITabBarController *tabController = PAFindTabController(controller);
    if (!tabController) return;
    self.tabController = tabController;
    [self applyToTabController:tabController animated:NO];
}

- (void)controllerDidLayout:(UIViewController *)controller {
    if (!self.enabled) return;
    UITabBarController *tabController = PAFindTabController(controller);
    if (!tabController || tabController != self.tabController) return;
    [self applyToTabController:tabController animated:NO];
}

- (void)tabSelectionChanged:(UITabBarController *)tabController {
    if (!self.enabled) {
        [self removeStudioFromTabController:tabController];
        return;
    }
    self.tabController = tabController;
    [self applyToTabController:tabController animated:YES];
}

- (void)applyToTabController:(UITabBarController *)tabController animated:(BOOL)animated {
    if (!tabController.view.window && !tabController.view.superview) return;

    if (self.forceDark) {
        tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }

    [self installDockForTabController:tabController];
    [self installHeaderForTabController:tabController];
    [self updateDockAndHeaderForTabController:tabController animated:animated];
    [self styleVisibleRootForTabController:tabController];
}

- (void)installDockForTabController:(UITabBarController *)tabController {
    UITabBar *tabBar = tabController.tabBar;
    if (!tabBar) return;

    PAStudioDock *dock = objc_getAssociatedObject(tabBar, PADockKey);
    if (!dock) {
        dock = [[PAStudioDock alloc] init];
        __weak typeof(self) weakSelf = self;
        __weak UITabBarController *weakTab = tabController;
        dock.selectionHandler = ^(NSUInteger index) {
            __strong typeof(weakSelf) self = weakSelf;
            UITabBarController *strongTab = weakTab;
            if (!self || !strongTab || index >= strongTab.viewControllers.count) return;

            if (self.haptics) {
                UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
                [generator selectionChanged];
            }
            strongTab.selectedIndex = index;
            [self updateDockAndHeaderForTabController:strongTab animated:YES];
            [self styleVisibleRootForTabController:strongTab];
        };
        [tabBar addSubview:dock];
        objc_setAssociatedObject(tabBar, PADockKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    self.dock = dock;
    dock.tabController = tabController;
    CGFloat horizontalInset = 14.0;
    CGFloat verticalInset = 8.0;
    dock.frame = CGRectInset(tabBar.bounds, horizontalInset, verticalInset);
    dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    tabBar.backgroundImage = [UIImage new];
    tabBar.shadowImage = [UIImage new];
    tabBar.backgroundColor = UIColor.clearColor;
    tabBar.translucent = YES;

    for (UIView *subview in tabBar.subviews) {
        if (subview == dock) continue;
        NSString *className = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [className containsString:@"Button"]) {
            subview.alpha = 0.0;
            subview.userInteractionEnabled = YES;
        }
    }
    [tabBar bringSubviewToFront:dock];
}

- (void)installHeaderForTabController:(UITabBarController *)tabController {
    PAStudioHeaderView *header = objc_getAssociatedObject(tabController.view, PAHeaderKey);
    if (!header) {
        header = [[PAStudioHeaderView alloc] init];
        __weak typeof(self) weakSelf = self;
        header.actionHandler = ^{
            [weakSelf performHeaderAction];
        };
        [tabController.view addSubview:header];
        objc_setAssociatedObject(tabController.view, PAHeaderKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.header = header;
    CGFloat safeTop = tabController.view.safeAreaInsets.top;
    header.frame = CGRectMake(22.0, safeTop + 4.0, CGRectGetWidth(tabController.view.bounds)-44.0, 70.0);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [tabController.view bringSubviewToFront:header];
}

- (void)updateDockAndHeaderForTabController:(UITabBarController *)tabController animated:(BOOL)animated {
    NSUInteger index = MIN(tabController.selectedIndex, 4);
    [self.dock updateSelectedIndex:index animated:(animated && self.animations)];

    NSArray *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
    NSArray *subtitles = @[@"Your people, one tap away.",
                           @"Your call history at a glance.",
                           @"All your connections.",
                           @"Dial with confidence.",
                           @"Messages that matter."];
    NSArray *icons = @[@"plus", @"line.3.horizontal.decrease", @"magnifyingglass", @"ellipsis", @"pencil"];
    [self.header configureTitle:titles[index]
                       subtitle:subtitles[index]
                           icon:icons[index]
                         accent:PAAccentForIndex(index)
                   showSubtitle:self.showSubtitles];

    BOOL rootVisible = PAIsRootVisible(tabController);
    self.header.hidden = !rootVisible;

    UIViewController *root = PATabRoot(tabController);
    UIViewController *top = PATabTop(tabController);
    UINavigationController *navigationController = [tabController.selectedViewController isKindOfClass:[UINavigationController class]]
        ? (UINavigationController *)tabController.selectedViewController : nil;

    if (rootVisible) {
        navigationController.navigationBarHidden = YES;
        root.additionalSafeAreaInsets = UIEdgeInsetsMake(82.0, 0, 0, 0);
    } else {
        navigationController.navigationBarHidden = NO;
        root.additionalSafeAreaInsets = UIEdgeInsetsZero;
        top.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
}

- (void)styleVisibleRootForTabController:(UITabBarController *)tabController {
    if (!PAIsRootVisible(tabController)) return;
    UIViewController *root = PATabRoot(tabController);
    if (!root || !root.isViewLoaded) return;

    NSUInteger index = MIN(tabController.selectedIndex, 4);
    UIColor *accent = PAAccentForIndex(index);

    CAGradientLayer *background = objc_getAssociatedObject(root.view, PAGradientKey);
    if (!background) {
        background = [CAGradientLayer layer];
        background.startPoint = CGPointMake(0.0, 0.0);
        background.endPoint = CGPointMake(1.0, 1.0);
        [root.view.layer insertSublayer:background atIndex:0];
        objc_setAssociatedObject(root.view, PAGradientKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    background.frame = root.view.bounds;
    background.colors = @[(id)[accent colorWithAlphaComponent:0.17].CGColor,
                          (id)PAColorHex(0x071228, 1.0).CGColor,
                          (id)PAColorHex(0x030711, 1.0).CGColor];
    background.locations = @[@0.0, @0.33, @1.0];
    root.view.backgroundColor = PAColorHex(0x030711, 1.0);

    for (UIView *view in PAAllSubviews(root.view)) {
        if ([view isKindOfClass:[UIScrollView class]]) {
            view.backgroundColor = UIColor.clearColor;
        }
        if ([view isKindOfClass:[UISearchBar class]]) {
            [self styleSearchBar:(UISearchBar *)view accent:accent];
        }
    }

    if (index == 3 && self.styleKeypad) {
        [self styleKeypadInView:root.view accent:accent];
    }

    [self.header.superview bringSubviewToFront:self.header];
    [self.dock.superview bringSubviewToFront:self.dock];
}

- (void)styleSearchBar:(UISearchBar *)searchBar accent:(UIColor *)accent {
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    UITextField *field = searchBar.searchTextField;
    field.backgroundColor = PAColorHex(0x17213D, 0.88);
    field.textColor = UIColor.whiteColor;
    field.tintColor = accent;
    field.layer.cornerRadius = 14.0;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.clipsToBounds = YES;
    field.leftView.tintColor = PAColorHex(0xAAB4CC, 1.0);
    NSAttributedString *placeholder = [[NSAttributedString alloc] initWithString:(field.placeholder ?: @"Search")
                                                                     attributes:@{NSForegroundColorAttributeName:PAColorHex(0x8792AA,1)}];
    field.attributedPlaceholder = placeholder;
}

- (void)tableViewDidLayout:(UITableView *)tableView {
    if (!self.enabled || !self.tabController || !PAIsRootVisible(self.tabController)) return;
    UIViewController *root = PATabRoot(self.tabController);
    if (!root || !PAViewIsDescendantOf(tableView, root.view)) return;

    NSUInteger tabIndex = MIN(self.tabController.selectedIndex, 4);
    NSArray<UIColor *> *palette = PAPaletteForIndex(tabIndex);

    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;

    for (UITableViewCell *cell in tableView.visibleCells) {
        NSIndexPath *indexPath = [tableView indexPathForCell:cell];
        NSUInteger row = indexPath ? indexPath.row : 0;
        UIColor *accent = palette[row % palette.count];
        BOOL strong = (tabIndex == 0 && row == 0) || (tabIndex == 2 && row == 0) || tabIndex == 4;

        PACardBackgroundView *background = objc_getAssociatedObject(cell, PACardKey);
        if (!background) {
            background = [[PACardBackgroundView alloc] initWithFrame:cell.bounds];
            cell.backgroundView = background;
            objc_setAssociatedObject(cell, PACardKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [background configureAccent:accent strong:strong opacity:self.cardOpacity cornerRadius:self.cornerRadius];

        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.tintColor = accent;
        PAStyleLabelsInView(cell.contentView);
    }

    for (UIView *subview in tableView.subviews) {
        if ([subview isKindOfClass:[UITableViewHeaderFooterView class]]) {
            UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)subview;
            header.contentView.backgroundColor = UIColor.clearColor;
            header.textLabel.textColor = PAColorHex(0xAAB4CC, 1.0);
            header.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        }
    }

    if (tabIndex == 0 && self.showShortcuts) {
        PAShortcutsView *shortcuts = objc_getAssociatedObject(tableView, PAShortcutsKey);
        if (!shortcuts) {
            shortcuts = [[PAShortcutsView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 154)];
            __weak typeof(self) weakSelf = self;
            shortcuts.tapHandler = ^(NSUInteger index) {
                [weakSelf shortcutTapped:index];
            };
            objc_setAssociatedObject(tableView, PAShortcutsKey, shortcuts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        shortcuts.frame = CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 154);
        if (tableView.tableFooterView != shortcuts) {
            tableView.tableFooterView = shortcuts;
        }
    }
}

- (void)collectionViewDidLayout:(UICollectionView *)collectionView {
    if (!self.enabled || !self.tabController || !PAIsRootVisible(self.tabController)) return;
    UIViewController *root = PATabRoot(self.tabController);
    if (!root || !PAViewIsDescendantOf(collectionView, root.view)) return;

    NSUInteger tabIndex = MIN(self.tabController.selectedIndex, 4);
    NSArray<UIColor *> *palette = PAPaletteForIndex(tabIndex);
    collectionView.backgroundColor = UIColor.clearColor;

    NSUInteger counter = 0;
    for (UICollectionViewCell *cell in collectionView.visibleCells) {
        UIColor *accent = palette[counter % palette.count];
        CAGradientLayer *gradient = objc_getAssociatedObject(cell, PAGradientKey);
        if (!gradient) {
            gradient = [CAGradientLayer layer];
            gradient.startPoint = CGPointMake(0, 0);
            gradient.endPoint = CGPointMake(1, 1);
            [cell.layer insertSublayer:gradient atIndex:0];
            objc_setAssociatedObject(cell, PAGradientKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        gradient.frame = cell.bounds;
        gradient.colors = @[(id)[accent colorWithAlphaComponent:0.75*self.cardOpacity].CGColor,
                            (id)PAColorHex(0x17213D, 0.92*self.cardOpacity).CGColor];
        gradient.cornerRadius = self.cornerRadius;
        cell.layer.cornerRadius = self.cornerRadius;
        cell.layer.cornerCurve = kCACornerCurveContinuous;
        cell.layer.masksToBounds = YES;
        cell.layer.borderWidth = 0.7;
        cell.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;
        PAStyleLabelsInView(cell.contentView);
        counter++;
    }
}

- (void)styleKeypadInView:(UIView *)rootView accent:(UIColor *)accent {
    NSArray<UIView *> *views = PAAllSubviews(rootView);
    for (UIView *view in views) {
        if (PAViewIsDescendantOf(view, self.header) || PAViewIsDescendantOf(view, self.dock)) continue;

        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)view;
            NSString *title = button.currentTitle ?: @"";
            NSString *label = (button.accessibilityLabel ?: @"").lowercaseString;
            BOOL numberButton = title.length == 1 && [@"0123456789*#" containsString:title];
            BOOL callButton = [label containsString:@"call"] && ![label containsString:@"voicemail"];
            BOOL deleteButton = [label containsString:@"delete"] || [label containsString:@"backspace"];

            if (numberButton && CGRectGetWidth(button.bounds) > 42.0) {
                button.backgroundColor = PAColorHex(0x1A2440, 0.98);
                button.layer.cornerRadius = MIN(17.0, CGRectGetHeight(button.bounds)*0.28);
                button.layer.cornerCurve = kCACornerCurveContinuous;
                button.layer.borderWidth = 0.8;
                button.layer.borderColor = PAColorHex(0x52607D, 0.32).CGColor;
                button.layer.shadowColor = UIColor.blackColor.CGColor;
                button.layer.shadowOpacity = 0.28;
                button.layer.shadowRadius = 9.0;
                button.layer.shadowOffset = CGSizeMake(0, 4);
                [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
                button.tintColor = UIColor.whiteColor;
                PAStyleLabelsInView(button);
            } else if (callButton && CGRectGetWidth(button.bounds) > 42.0) {
                button.backgroundColor = PAColorHex(0x32C85A, 1.0);
                button.tintColor = UIColor.whiteColor;
                button.layer.cornerRadius = MIN(22.0, CGRectGetHeight(button.bounds)*0.32);
                button.layer.cornerCurve = kCACornerCurveContinuous;
                button.layer.shadowColor = PAColorHex(0x32C85A,1).CGColor;
                button.layer.shadowOpacity = 0.42;
                button.layer.shadowRadius = 18.0;
                button.layer.shadowOffset = CGSizeMake(0, 6);
            } else if (deleteButton) {
                button.tintColor = PAColorHex(0xC7D0E3,1);
                button.backgroundColor = PAColorHex(0x17213D,0.88);
                button.layer.cornerRadius = 12.0;
            }
        } else if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            if (label.font.pointSize < 24.0 || CGRectGetMinY(label.frame) > 300.0) continue;

            NSString *text = label.text ?: @"";
            NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789 ()-"];
            BOOL looksLikeNumber = text.length == 0 || [[text stringByTrimmingCharactersInSet:allowed] length] == 0;
            if (!looksLikeNumber) continue;

            UIView *parent = label.superview;
            if (!parent || PAViewIsDescendantOf(parent, self.header)) continue;

            UIView *backdrop = objc_getAssociatedObject(label, PANumberBackdropKey);
            if (!backdrop) {
                backdrop = [[UIView alloc] init];
                backdrop.userInteractionEnabled = NO;
                backdrop.layer.cornerRadius = 17.0;
                backdrop.layer.cornerCurve = kCACornerCurveContinuous;
                backdrop.layer.shadowColor = accent.CGColor;
                backdrop.layer.shadowOpacity = 0.32;
                backdrop.layer.shadowRadius = 16.0;
                backdrop.layer.shadowOffset = CGSizeMake(0, 6);

                CAGradientLayer *gradient = [CAGradientLayer layer];
                gradient.colors = @[(id)PAColorHex(0xFF4E4E,1).CGColor, (id)PAColorHex(0xFF7A1A,1).CGColor];
                gradient.startPoint = CGPointMake(0,0.5);
                gradient.endPoint = CGPointMake(1,0.5);
                gradient.cornerRadius = 17.0;
                [backdrop.layer insertSublayer:gradient atIndex:0];
                objc_setAssociatedObject(backdrop, PAGradientKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                [parent insertSubview:backdrop belowSubview:label];
                objc_setAssociatedObject(label, PANumberBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGRect frame = CGRectInset(label.frame, -22.0, -13.0);
            frame.origin.x = MAX(16.0, frame.origin.x);
            frame.size.width = MIN(CGRectGetWidth(parent.bounds)-32.0, frame.size.width);
            backdrop.frame = frame;
            CAGradientLayer *gradient = objc_getAssociatedObject(backdrop, PAGradientKey);
            gradient.frame = backdrop.bounds;
            label.textColor = UIColor.whiteColor;
            label.font = [UIFont systemFontOfSize:MAX(label.font.pointSize, 27.0) weight:UIFontWeightBold];
        }
    }
}

- (void)performHeaderAction {
    if (!self.tabController) return;
    NSUInteger index = MIN(self.tabController.selectedIndex, 4);
    UIViewController *root = PATabRoot(self.tabController);

    if (index == 2) {
        for (UIView *view in PAAllSubviews(root.view)) {
            if ([view isKindOfClass:[UISearchBar class]]) {
                [(UISearchBar *)view becomeFirstResponder];
                return;
            }
        }
    }

    UIBarButtonItem *item = root.navigationItem.rightBarButtonItem ?: root.navigationItem.leftBarButtonItem;
    if (item.action) {
        [UIApplication.sharedApplication sendAction:item.action to:item.target from:item forEvent:nil];
        return;
    }

    if (index == 3) {
        [self presentQuickSettings];
    }
}

- (void)shortcutTapped:(NSUInteger)index {
    if (!self.tabController) return;
    switch (index) {
        case 0: self.tabController.selectedIndex = 2; break;
        case 1: self.tabController.selectedIndex = 3; break;
        case 2: self.tabController.selectedIndex = 4; break;
        default: [self presentQuickSettings]; return;
    }
    [self updateDockAndHeaderForTabController:self.tabController animated:YES];
    [self styleVisibleRootForTabController:self.tabController];
}

- (void)presentQuickSettings {
    UIViewController *presenter = PATabTop(self.tabController);
    if (!presenter || presenter.presentedViewController) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PhoneAura"
                                                                   message:@"Bold Card Studio is active. Use Settings → PhoneAura to customize cards, subtitles, shortcuts, keypad styling, haptics and animations."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open PhoneAura Settings"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:@"App-prefs:root=PhoneAura"];
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)removeStudioFromTabController:(UITabBarController *)tabController {
    UITabBar *tabBar = tabController.tabBar;
    PAStudioDock *dock = objc_getAssociatedObject(tabBar, PADockKey);
    [dock removeFromSuperview];
    objc_setAssociatedObject(tabBar, PADockKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    PAStudioHeaderView *header = objc_getAssociatedObject(tabController.view, PAHeaderKey);
    [header removeFromSuperview];
    objc_setAssociatedObject(tabController.view, PAHeaderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    for (UIView *subview in tabBar.subviews) {
        subview.alpha = 1.0;
        subview.userInteractionEnabled = YES;
    }

    for (UIViewController *controller in tabController.viewControllers) {
        UIViewController *root = controller;
        if ([controller isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navigationController = (UINavigationController *)controller;
            navigationController.navigationBarHidden = NO;
            root = navigationController.viewControllers.firstObject;
        }
        root.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }

    tabBar.backgroundImage = nil;
    tabBar.shadowImage = nil;
    self.dock = nil;
    self.header = nil;
}

@end
