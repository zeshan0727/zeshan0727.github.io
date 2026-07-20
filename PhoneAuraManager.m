#import "PhoneAuraManager.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PANotification = @"com.zeshan.phoneaura/preferences.changed";
static NSInteger const PABackgroundTag = 915001;
static NSInteger const PADockTag = 915002;

typedef NS_ENUM(NSInteger, PAAccentStyle) {
    PAAccentStyleOcean = 0,
    PAAccentStyleAurora = 1,
    PAAccentStyleEmerald = 2,
    PAAccentStyleSunset = 3
};

#pragma mark - Preferences

static id PAReadPreference(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)PADomain);
    return CFBridgingRelease(value);
}

static BOOL PABool(NSString *key, BOOL fallback) {
    id value = PAReadPreference(key);
    return value ? [value boolValue] : fallback;
}

static NSInteger PAInteger(NSString *key, NSInteger fallback) {
    id value = PAReadPreference(key);
    return value ? [value integerValue] : fallback;
}

static CGFloat PAFloat(NSString *key, CGFloat fallback) {
    id value = PAReadPreference(key);
    return value ? [value doubleValue] : fallback;
}

static UIColor *PAAccentColor(void) {
    switch ((PAAccentStyle)PAInteger(@"accentStyle", PAAccentStyleOcean)) {
        case PAAccentStyleAurora:
            return [UIColor colorWithRed:0.72 green:0.37 blue:1.00 alpha:1.0];
        case PAAccentStyleEmerald:
            return [UIColor colorWithRed:0.10 green:0.86 blue:0.66 alpha:1.0];
        case PAAccentStyleSunset:
            return [UIColor colorWithRed:1.00 green:0.39 blue:0.27 alpha:1.0];
        case PAAccentStyleOcean:
        default:
            return [UIColor colorWithRed:0.16 green:0.68 blue:1.00 alpha:1.0];
    }
}

static NSArray<UIColor *> *PAGradientColors(void) {
    switch ((PAAccentStyle)PAInteger(@"accentStyle", PAAccentStyleOcean)) {
        case PAAccentStyleAurora:
            return @[
                [UIColor colorWithRed:0.04 green:0.03 blue:0.11 alpha:1.0],
                [UIColor colorWithRed:0.18 green:0.06 blue:0.31 alpha:1.0],
                [UIColor colorWithRed:0.02 green:0.04 blue:0.10 alpha:1.0]
            ];
        case PAAccentStyleEmerald:
            return @[
                [UIColor colorWithRed:0.01 green:0.08 blue:0.09 alpha:1.0],
                [UIColor colorWithRed:0.02 green:0.23 blue:0.20 alpha:1.0],
                [UIColor colorWithRed:0.01 green:0.04 blue:0.08 alpha:1.0]
            ];
        case PAAccentStyleSunset:
            return @[
                [UIColor colorWithRed:0.12 green:0.03 blue:0.05 alpha:1.0],
                [UIColor colorWithRed:0.35 green:0.08 blue:0.07 alpha:1.0],
                [UIColor colorWithRed:0.05 green:0.02 blue:0.08 alpha:1.0]
            ];
        case PAAccentStyleOcean:
        default:
            return @[
                [UIColor colorWithRed:0.01 green:0.05 blue:0.13 alpha:1.0],
                [UIColor colorWithRed:0.02 green:0.19 blue:0.35 alpha:1.0],
                [UIColor colorWithRed:0.04 green:0.02 blue:0.14 alpha:1.0]
            ];
    }
}

static UIColor *PAPrimaryTextColor(void) {
    return PABool(@"forceDark", YES) ? UIColor.whiteColor : UIColor.labelColor;
}

static UIColor *PASecondaryTextColor(void) {
    return PABool(@"forceDark", YES)
        ? [UIColor colorWithWhite:1.0 alpha:0.58]
        : UIColor.secondaryLabelColor;
}

static void PAHaptic(UIImpactFeedbackStyle style) {
    if (!PABool(@"haptics", YES)) return;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    [generator prepare];
    [generator impactOccurred];
}

#pragma mark - Background

@interface UIColor (PhoneAuraHue)
- (UIColor *)colorWithHueOffset:(CGFloat)offset;
@end

@interface PABackgroundView : UIView
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UIView *glowOne;
@property (nonatomic, strong) UIView *glowTwo;
- (void)refreshColors;
@end

@implementation PABackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _gradientLayer = [CAGradientLayer layer];
    _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    _gradientLayer.locations = @[@0.0, @0.52, @1.0];
    [self.layer addSublayer:_gradientLayer];

    _glowOne = [[UIView alloc] initWithFrame:CGRectZero];
    _glowOne.userInteractionEnabled = NO;
    _glowOne.layer.cornerRadius = 130.0;
    _glowOne.layer.shadowRadius = 55.0;
    _glowOne.layer.shadowOpacity = 0.55;
    _glowOne.layer.shadowOffset = CGSizeZero;
    [self addSubview:_glowOne];

    _glowTwo = [[UIView alloc] initWithFrame:CGRectZero];
    _glowTwo.userInteractionEnabled = NO;
    _glowTwo.layer.cornerRadius = 110.0;
    _glowTwo.layer.shadowRadius = 50.0;
    _glowTwo.layer.shadowOpacity = 0.42;
    _glowTwo.layer.shadowOffset = CGSizeZero;
    [self addSubview:_glowTwo];

    [self refreshColors];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    self.glowOne.frame = CGRectMake(width - 170.0, -70.0, 260.0, 260.0);
    self.glowTwo.frame = CGRectMake(-100.0, height * 0.55, 220.0, 220.0);
}

- (void)refreshColors {
    NSMutableArray *cgColors = [NSMutableArray array];
    for (UIColor *color in PAGradientColors()) {
        [cgColors addObject:(id)color.CGColor];
    }
    self.gradientLayer.colors = cgColors;
    UIColor *accent = PAAccentColor();
    self.glowOne.backgroundColor = [accent colorWithAlphaComponent:0.18];
    self.glowOne.layer.shadowColor = accent.CGColor;
    self.glowTwo.backgroundColor = [[accent colorWithHueOffset:0.08] colorWithAlphaComponent:0.12];
    self.glowTwo.layer.shadowColor = accent.CGColor;
}

@end

@implementation UIColor (PhoneAuraHue)
- (UIColor *)colorWithHueOffset:(CGFloat)offset {
    CGFloat h = 0, s = 0, b = 0, a = 0;
    if ([self getHue:&h saturation:&s brightness:&b alpha:&a]) {
        h = fmod(h + offset + 1.0, 1.0);
        return [UIColor colorWithHue:h saturation:s brightness:b alpha:a];
    }
    return self;
}
@end

#pragma mark - Cell background

@interface PAInsetCellBackground : UIView
@property (nonatomic, strong) UIView *bubble;
@end

@implementation PAInsetCellBackground

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    _bubble = [[UIView alloc] initWithFrame:CGRectZero];
    _bubble.userInteractionEnabled = NO;
    _bubble.layer.cornerRadius = 18.0;
    _bubble.layer.cornerCurve = kCACornerCurveContinuous;
    _bubble.layer.borderWidth = 0.5;
    [self addSubview:_bubble];
    [self refresh];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.bubble.frame = CGRectInset(self.bounds, 12.0, 4.0);
}

- (void)refresh {
    CGFloat intensity = MIN(MAX(PAFloat(@"glassIntensity", 0.72), 0.35), 1.0);
    self.bubble.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.055 + (intensity * 0.045)];
    self.bubble.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
}

@end

#pragma mark - Floating dock

@class PhoneAuraManager;

@interface PAFloatingDock : UIVisualEffectView
@property (nonatomic, weak) PhoneAuraManager *manager;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, assign) NSInteger selectedIndex;
- (void)refreshAppearance;
- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated;
@end

@interface PADockButton : UIButton
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIView *selectionPill;
@end

@implementation PADockButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.accessibilityTraits = UIAccessibilityTraitButton;
    _selectionPill = [[UIView alloc] initWithFrame:CGRectZero];
    _selectionPill.userInteractionEnabled = NO;
    _selectionPill.layer.cornerRadius = 18.0;
    _selectionPill.layer.cornerCurve = kCACornerCurveContinuous;
    _selectionPill.alpha = 0.0;
    [self addSubview:_selectionPill];

    _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.userInteractionEnabled = NO;
    [self addSubview:_iconView];

    _captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _captionLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
    _captionLabel.textAlignment = NSTextAlignmentCenter;
    _captionLabel.userInteractionEnabled = NO;
    [self addSubview:_captionLabel];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    self.selectionPill.frame = CGRectMake((width - 42.0) / 2.0, 5.0, 42.0, 36.0);
    self.iconView.frame = CGRectMake((width - 24.0) / 2.0, 11.0, 24.0, 24.0);
    self.captionLabel.frame = CGRectMake(0.0, 43.0, width, 15.0);
}

@end

@implementation PAFloatingDock

- (instancetype)initWithFrame:(CGRect)frame {
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self = [super initWithEffect:effect];
    if (!self) return nil;

    self.clipsToBounds = YES;
    self.layer.cornerRadius = 28.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 0.7;
    self.layer.shadowOpacity = 0.35;
    self.layer.shadowRadius = 24.0;
    self.layer.shadowOffset = CGSizeMake(0.0, 12.0);

    _stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _stack.axis = UILayoutConstraintAxisHorizontal;
    _stack.distribution = UIStackViewDistributionFillEqually;
    _stack.alignment = UIStackViewAlignmentFill;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [_stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [_stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
        [_stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0]
    ]];

    NSArray<NSString *> *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
    NSArray<NSString *> *icons = @[@"star.fill", @"clock.fill", @"person.2.fill", @"circle.grid.3x3.fill", @"recordingtape"];
    NSMutableArray *created = [NSMutableArray array];

    for (NSInteger index = 0; index < titles.count; index++) {
        PADockButton *button = [PADockButton buttonWithType:UIButtonTypeCustom];
        button.tag = index;
        button.accessibilityLabel = titles[index];
        button.captionLabel.text = titles[index];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
        button.iconView.image = [UIImage systemImageNamed:icons[index] withConfiguration:config];
        [button addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self.stack addArrangedSubview:button];
        [created addObject:button];
    }

    self.buttons = created;
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.65;
    [self addGestureRecognizer:longPress];

    [self refreshAppearance];
    return self;
}

- (void)buttonPressed:(UIButton *)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([self.manager respondsToSelector:NSSelectorFromString(@"dockButtonPressed:")]) {
        [self.manager performSelector:NSSelectorFromString(@"dockButtonPressed:") withObject:sender];
    }
#pragma clang diagnostic pop
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([self.manager respondsToSelector:NSSelectorFromString(@"presentSettings")]) {
        [self.manager performSelector:NSSelectorFromString(@"presentSettings")];
    }
#pragma clang diagnostic pop
}

- (void)refreshAppearance {
    UIColor *accent = PAAccentColor();
    CGFloat intensity = MIN(MAX(PAFloat(@"glassIntensity", 0.72), 0.35), 1.0);
    self.alpha = 0.78 + (intensity * 0.20);
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.layer.shadowColor = accent.CGColor;

    for (NSInteger index = 0; index < self.buttons.count; index++) {
        PADockButton *button = (PADockButton *)self.buttons[index];
        BOOL selected = index == self.selectedIndex;
        button.selectionPill.backgroundColor = [accent colorWithAlphaComponent:0.22];
        button.iconView.tintColor = selected ? accent : [UIColor colorWithWhite:1.0 alpha:0.60];
        button.captionLabel.textColor = selected ? UIColor.whiteColor : [UIColor colorWithWhite:1.0 alpha:0.48];
        button.selectionPill.alpha = selected ? 1.0 : 0.0;
        button.transform = selected ? CGAffineTransformMakeScale(1.03, 1.03) : CGAffineTransformIdentity;
        button.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex animated:(BOOL)animated {
    _selectedIndex = selectedIndex;
    void (^changes)(void) = ^{
        [self refreshAppearance];
    };
    if (animated && PABool(@"animations", YES)) {
        [UIView animateWithDuration:0.38
                              delay:0.0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.45
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

@end

#pragma mark - Settings sheet

@interface PASettingsViewController : UIViewController
@property (nonatomic, copy) void (^onChanged)(void);
@end

@implementation PASettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.09 alpha:1.0];

    PABackgroundView *background = [[PABackgroundView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:background];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *content = [[UIStackView alloc] initWithFrame:CGRectZero];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 14.0;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20.0],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20.0],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18.0],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-30.0],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40.0]
    ]];

    UIView *heading = [self headingView];
    [content addArrangedSubview:heading];
    [heading.heightAnchor constraintEqualToConstant:78.0].active = YES;

    [content addArrangedSubview:[self switchCardWithTitle:@"Haptic feedback"
                                                 subtitle:@"Subtle feedback when changing tabs"
                                                      key:@"haptics"
                                             defaultValue:YES]];
    [content addArrangedSubview:[self switchCardWithTitle:@"Fluid animations"
                                                 subtitle:@"Spring transitions and selection movement"
                                                      key:@"animations"
                                             defaultValue:YES]];
    [content addArrangedSubview:[self switchCardWithTitle:@"Midnight appearance"
                                                 subtitle:@"Keep the Phone app in the dark glass style"
                                                      key:@"forceDark"
                                             defaultValue:YES]];

    UIView *accentCard = [self cardContainer];
    UIStackView *accentStack = [self verticalStackInCard:accentCard];
    UILabel *accentTitle = [self label:@"Accent atmosphere" size:16.0 weight:UIFontWeightSemibold color:UIColor.whiteColor];
    UILabel *accentSubtitle = [self label:@"Choose the glow and active color" size:12.0 weight:UIFontWeightRegular color:[UIColor colorWithWhite:1.0 alpha:0.56]];
    UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:@[@"Ocean", @"Aurora", @"Emerald", @"Sunset"]];
    segments.selectedSegmentIndex = PAInteger(@"accentStyle", 0);
    segments.selectedSegmentTintColor = [PAAccentColor() colorWithAlphaComponent:0.72];
    segments.tag = 2001;
    [segments addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [accentStack addArrangedSubview:accentTitle];
    [accentStack addArrangedSubview:accentSubtitle];
    [accentStack setCustomSpacing:12.0 afterView:accentSubtitle];
    [accentStack addArrangedSubview:segments];
    [content addArrangedSubview:accentCard];

    UIView *intensityCard = [self cardContainer];
    UIStackView *intensityStack = [self verticalStackInCard:intensityCard];
    UILabel *intensityTitle = [self label:@"Glass intensity" size:16.0 weight:UIFontWeightSemibold color:UIColor.whiteColor];
    UILabel *intensitySubtitle = [self label:@"Control the opacity of cards and the floating dock" size:12.0 weight:UIFontWeightRegular color:[UIColor colorWithWhite:1.0 alpha:0.56]];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
    slider.minimumValue = 0.35;
    slider.maximumValue = 1.0;
    slider.value = PAFloat(@"glassIntensity", 0.72);
    slider.minimumTrackTintColor = PAAccentColor();
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [intensityStack addArrangedSubview:intensityTitle];
    [intensityStack addArrangedSubview:intensitySubtitle];
    [intensityStack setCustomSpacing:10.0 afterView:intensitySubtitle];
    [intensityStack addArrangedSubview:slider];
    [content addArrangedSubview:intensityCard];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Done" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    close.backgroundColor = PAAccentColor();
    close.tintColor = UIColor.whiteColor;
    close.layer.cornerRadius = 18.0;
    close.layer.cornerCurve = kCACornerCurveContinuous;
    [close addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
    [content addArrangedSubview:close];
    [close.heightAnchor constraintEqualToConstant:56.0].active = YES;
}

- (UIView *)headingView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    UILabel *title = [self label:@"PhoneAura" size:30.0 weight:UIFontWeightBold color:UIColor.whiteColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *subtitle = [self label:@"Long-press the floating dock to return here." size:13.0 weight:UIFontWeightRegular color:[UIColor colorWithWhite:1.0 alpha:0.58]];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:title];
    [view addSubview:subtitle];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:view.topAnchor constant:4.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0]
    ]];
    return view;
}

- (UIView *)switchCardWithTitle:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key defaultValue:(BOOL)fallback {
    UIView *card = [self cardContainer];
    UIStackView *horizontal = [[UIStackView alloc] initWithFrame:CGRectZero];
    horizontal.axis = UILayoutConstraintAxisHorizontal;
    horizontal.alignment = UIStackViewAlignmentCenter;
    horizontal.spacing = 12.0;
    horizontal.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:horizontal];
    [NSLayoutConstraint activateConstraints:@[
        [horizontal.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [horizontal.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [horizontal.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [horizontal.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0]
    ]];

    UIStackView *labels = [[UIStackView alloc] initWithFrame:CGRectZero];
    labels.axis = UILayoutConstraintAxisVertical;
    labels.spacing = 3.0;
    [labels addArrangedSubview:[self label:title size:16.0 weight:UIFontWeightSemibold color:UIColor.whiteColor]];
    [labels addArrangedSubview:[self label:subtitle size:12.0 weight:UIFontWeightRegular color:[UIColor colorWithWhite:1.0 alpha:0.56]]];

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.on = PABool(key, fallback);
    toggle.onTintColor = PAAccentColor();
    toggle.accessibilityIdentifier = key;
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

    [horizontal addArrangedSubview:labels];
    [horizontal addArrangedSubview:toggle];
    return card;
}

- (UIView *)cardContainer {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.075];
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.6;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.13].CGColor;
    return card;
}

- (UIStackView *)verticalStackInCard:(UIView *)card {
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:15.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-15.0]
    ]];
    return stack;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (void)writeValue:(id)value key:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)PADomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PANotification,
                                         NULL,
                                         NULL,
                                         true);
    if (self.onChanged) self.onChanged();
}

- (void)switchChanged:(UISwitch *)sender {
    [self writeValue:@(sender.on) key:sender.accessibilityIdentifier ?: @""];
    PAHaptic(UIImpactFeedbackStyleLight);
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self writeValue:@(sender.selectedSegmentIndex) key:@"accentStyle"];
    PAHaptic(UIImpactFeedbackStyleMedium);
}

- (void)sliderChanged:(UISlider *)sender {
    [self writeValue:@(sender.value) key:@"glassIntensity"];
}

- (void)closePressed {
    PAHaptic(UIImpactFeedbackStyleLight);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Manager

@interface PhoneAuraManager ()
@property (nonatomic, weak) UITabBarController *tabController;
@property (nonatomic, weak) PAFloatingDock *dock;
@property (nonatomic, assign) BOOL applying;
@end

@implementation PhoneAuraManager

+ (instancetype)sharedManager {
    static PhoneAuraManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[PhoneAuraManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    PASettingsChanged,
                                    (__bridge CFStringRef)PANotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    return self;
}

static void PASettingsChanged(CFNotificationCenterRef center,
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
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                             (__bridge const void *)(self));
}

- (void)reloadPreferences {
    if (!self.tabController) return;
    [self installAndStyleTabController:self.tabController];
    UIViewController *visible = [self visibleControllerFrom:self.tabController];
    [self styleController:visible];
}

- (void)controllerDidAppear:(UIViewController *)controller {
    if (self.applying) return;
    UITabBarController *tab = [self tabControllerForController:controller];
    if (!tab) tab = [self locateTabController];
    if (!tab) return;

    self.tabController = tab;
    [self installAndStyleTabController:tab];
    [self styleController:controller];
    [self updateDockVisibilityForController:controller];
}

- (void)tabSelectionChanged:(UITabBarController *)tabController {
    if (!tabController) return;
    self.tabController = tabController;
    [self installAndStyleTabController:tabController];
    [self.dock setSelectedIndex:tabController.selectedIndex animated:YES];
    PAHaptic(UIImpactFeedbackStyleLight);
}

- (void)dockButtonPressed:(UIButton *)sender {
    if (!self.tabController) return;
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.tabController.viewControllers.count) return;
    self.tabController.selectedIndex = index;
    [self.dock setSelectedIndex:index animated:YES];
    PAHaptic(UIImpactFeedbackStyleLight);
}

- (void)presentSettings {
    UIViewController *presenter = [self visibleControllerFrom:self.tabController ?: [self locateTabController]];
    if (!presenter || [presenter isKindOfClass:PASettingsViewController.class]) return;

    PASettingsViewController *settings = [[PASettingsViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    settings.onChanged = ^{
        [weakSelf reloadPreferences];
    };
    settings.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        settings.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        settings.sheetPresentationController.prefersGrabberVisible = YES;
        settings.sheetPresentationController.preferredCornerRadius = 28.0;
    }
    PAHaptic(UIImpactFeedbackStyleMedium);
    [presenter presentViewController:settings animated:YES completion:nil];
}

- (void)installAndStyleTabController:(UITabBarController *)tab {
    if (!PABool(@"enabled", YES)) {
        tab.tabBar.hidden = NO;
        UIView *dock = [tab.view viewWithTag:PADockTag];
        dock.hidden = YES;
        return;
    }

    self.applying = YES;
    tab.view.backgroundColor = UIColor.clearColor;
    tab.overrideUserInterfaceStyle = PABool(@"forceDark", YES) ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;

    PABackgroundView *background = (PABackgroundView *)[tab.view viewWithTag:PABackgroundTag];
    if (![background isKindOfClass:PABackgroundView.class]) {
        background = [[PABackgroundView alloc] initWithFrame:tab.view.bounds];
        background.tag = PABackgroundTag;
        [tab.view insertSubview:background atIndex:0];
    }
    [background refreshColors];

    tab.tabBar.hidden = YES;
    tab.additionalSafeAreaInsets = UIEdgeInsetsMake(0.0, 0.0, 92.0, 0.0);

    PAFloatingDock *dock = (PAFloatingDock *)[tab.view viewWithTag:PADockTag];
    if (![dock isKindOfClass:PAFloatingDock.class]) {
        dock = [[PAFloatingDock alloc] initWithFrame:CGRectZero];
        dock.tag = PADockTag;
        dock.manager = self;
        dock.translatesAutoresizingMaskIntoConstraints = NO;
        [tab.view addSubview:dock];
        [NSLayoutConstraint activateConstraints:@[
            [dock.leadingAnchor constraintEqualToAnchor:tab.view.leadingAnchor constant:16.0],
            [dock.trailingAnchor constraintEqualToAnchor:tab.view.trailingAnchor constant:-16.0],
            [dock.bottomAnchor constraintEqualToAnchor:tab.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
            [dock.heightAnchor constraintEqualToConstant:70.0]
        ]];
    }

    self.dock = dock;
    dock.hidden = NO;
    [dock refreshAppearance];
    [dock setSelectedIndex:tab.selectedIndex animated:NO];
    [tab.view bringSubviewToFront:dock];
    self.applying = NO;
}

- (void)styleController:(UIViewController *)controller {
    if (!controller || !PABool(@"enabled", YES)) return;
    controller.view.backgroundColor = UIColor.clearColor;
    controller.overrideUserInterfaceStyle = PABool(@"forceDark", YES) ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;

    UINavigationController *navigation = controller.navigationController;
    if (navigation) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: PAPrimaryTextColor(),
            NSFontAttributeName: [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold]
        };
        appearance.largeTitleTextAttributes = @{
            NSForegroundColorAttributeName: PAPrimaryTextColor(),
            NSFontAttributeName: [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold]
        };
        navigation.navigationBar.standardAppearance = appearance;
        navigation.navigationBar.scrollEdgeAppearance = appearance;
        navigation.navigationBar.compactAppearance = appearance;
        navigation.navigationBar.tintColor = PAAccentColor();
        navigation.navigationBar.prefersLargeTitles = YES;
    }

    [self styleViewTree:controller.view depth:0];
}

- (void)styleViewTree:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 12) return;
    NSString *className = NSStringFromClass(view.class);
    if ([className hasPrefix:@"PA"] || [className containsString:@"RemoteView"] || [className containsString:@"AV"] ) return;

    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)view;
        table.backgroundColor = UIColor.clearColor;
        table.separatorStyle = UITableViewCellSeparatorStyleNone;
        table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        UIEdgeInsets inset = table.contentInset;
        inset.bottom = MAX(inset.bottom, 96.0);
        table.contentInset = inset;
        table.scrollIndicatorInsets = UIEdgeInsetsMake(table.scrollIndicatorInsets.top, 0.0, 96.0, 0.0);
    } else if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection = (UICollectionView *)view;
        collection.backgroundColor = UIColor.clearColor;
        UIEdgeInsets inset = collection.contentInset;
        inset.bottom = MAX(inset.bottom, 96.0);
        collection.contentInset = inset;
    } else if ([view isKindOfClass:UITableViewCell.class]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        if (![cell.backgroundView isKindOfClass:PAInsetCellBackground.class]) {
            cell.backgroundView = [[PAInsetCellBackground alloc] initWithFrame:cell.bounds];
            PAInsetCellBackground *selected = [[PAInsetCellBackground alloc] initWithFrame:cell.bounds];
            selected.bubble.backgroundColor = [PAAccentColor() colorWithAlphaComponent:0.22];
            cell.selectedBackgroundView = selected;
        }
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.tintColor = PAAccentColor();
    } else if ([view isKindOfClass:UICollectionViewCell.class]) {
        UICollectionViewCell *cell = (UICollectionViewCell *)view;
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.075];
        cell.layer.cornerRadius = 20.0;
        cell.layer.cornerCurve = kCACornerCurveContinuous;
        cell.layer.borderWidth = 0.5;
        cell.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    } else if ([view isKindOfClass:UISearchBar.class]) {
        UISearchBar *search = (UISearchBar *)view;
        search.searchBarStyle = UISearchBarStyleMinimal;
        search.tintColor = PAAccentColor();
        search.searchTextField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
        search.searchTextField.textColor = PAPrimaryTextColor();
        search.searchTextField.layer.cornerRadius = 15.0;
        search.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
    } else if ([view isKindOfClass:UISegmentedControl.class]) {
        UISegmentedControl *segment = (UISegmentedControl *)view;
        segment.selectedSegmentTintColor = [PAAccentColor() colorWithAlphaComponent:0.72];
        segment.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        segment.layer.cornerRadius = 12.0;
        segment.layer.cornerCurve = kCACornerCurveContinuous;
    } else if ([view isKindOfClass:UIButton.class]) {
        [self styleButton:(UIButton *)view];
    } else if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.tag != 915050 && label.alpha > 0.5) {
            UIColor *current = label.textColor;
            CGFloat white = 0.0, alpha = 0.0;
            if ([current getWhite:&white alpha:&alpha] && white < 0.75) {
                label.textColor = label.font.pointSize >= 16.0 ? PAPrimaryTextColor() : PASecondaryTextColor();
            }
        }
    } else if ([view isKindOfClass:UIScrollView.class]) {
        view.backgroundColor = UIColor.clearColor;
    }

    for (UIView *subview in view.subviews) {
        [self styleViewTree:subview depth:depth + 1];
    }
}

- (void)styleButton:(UIButton *)button {
    if ([button isKindOfClass:PADockButton.class]) return;
    NSString *title = [button titleForState:UIControlStateNormal] ?: button.accessibilityLabel ?: @"";
    CGFloat width = CGRectGetWidth(button.bounds);
    CGFloat height = CGRectGetHeight(button.bounds);
    BOOL keypadLike = width >= 52.0 && width <= 104.0 && height >= 52.0 && height <= 104.0 && fabs(width - height) < 18.0;
    BOOL callButton = [title localizedCaseInsensitiveContainsString:@"call"] || [title localizedCaseInsensitiveContainsString:@"dial"];

    button.tintColor = callButton ? UIColor.whiteColor : PAAccentColor();
    if (keypadLike) {
        button.layer.cornerRadius = MIN(width, height) / 2.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.borderWidth = 0.6;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
        button.backgroundColor = callButton
            ? [UIColor.systemGreenColor colorWithAlphaComponent:0.90]
            : [UIColor colorWithWhite:1.0 alpha:0.10];
        button.layer.shadowColor = (callButton ? UIColor.systemGreenColor : PAAccentColor()).CGColor;
        button.layer.shadowOpacity = callButton ? 0.30 : 0.12;
        button.layer.shadowRadius = 12.0;
        button.layer.shadowOffset = CGSizeMake(0.0, 5.0);
        button.titleLabel.font = [UIFont systemFontOfSize:button.titleLabel.font.pointSize weight:UIFontWeightSemibold];
    }
}

- (void)updateDockVisibilityForController:(UIViewController *)controller {
    if (!self.dock || !self.tabController) return;
    BOOL shouldShow = YES;
    UIViewController *selected = self.tabController.selectedViewController;
    if ([selected isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (UINavigationController *)selected;
        shouldShow = navigation.viewControllers.count <= 1;
    }
    if (controller.presentedViewController && ![controller.presentedViewController isKindOfClass:PASettingsViewController.class]) {
        shouldShow = NO;
    }
    self.dock.hidden = !shouldShow;
}

- (UITabBarController *)tabControllerForController:(UIViewController *)controller {
    UIViewController *cursor = controller;
    while (cursor) {
        if ([cursor isKindOfClass:UITabBarController.class]) return (UITabBarController *)cursor;
        cursor = cursor.parentViewController;
    }
    return controller.tabBarController;
}

- (UITabBarController *)locateTabController {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateUnattached && [scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (!candidate.hidden && candidate.alpha > 0.0 && candidate.windowLevel == UIWindowLevelNormal) {
                    window = candidate;
                    break;
                }
            }
        }
        if (window) break;
    }
    if (!window) window = UIApplication.sharedApplication.keyWindow;
    return [self findTabControllerIn:window.rootViewController];
}

- (UITabBarController *)findTabControllerIn:(UIViewController *)controller {
    if (!controller) return nil;
    if ([controller isKindOfClass:UITabBarController.class]) return (UITabBarController *)controller;
    for (UIViewController *child in controller.childViewControllers) {
        UITabBarController *found = [self findTabControllerIn:child];
        if (found) return found;
    }
    if (controller.presentedViewController) {
        return [self findTabControllerIn:controller.presentedViewController];
    }
    return nil;
}

- (UIViewController *)visibleControllerFrom:(UIViewController *)controller {
    if (!controller) return nil;
    if (controller.presentedViewController) {
        return [self visibleControllerFrom:controller.presentedViewController];
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return [self visibleControllerFrom:((UINavigationController *)controller).visibleViewController];
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return [self visibleControllerFrom:((UITabBarController *)controller).selectedViewController];
    }
    return controller;
}

@end
