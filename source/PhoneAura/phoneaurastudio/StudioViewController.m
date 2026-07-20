#import "StudioViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>

extern char **environ;
static CFStringRef const PADomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PANotification = CFSTR("com.zeshan.phoneaura/preferences.changed");

static UIColor *PAHex(uint32_t value, CGFloat alpha) {
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                           green:((value >> 8) & 0xFF) / 255.0
                            blue:(value & 0xFF) / 255.0
                           alpha:alpha];
}

@interface StudioViewController ()
@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UILabel *previewTitle;
@property(nonatomic,strong) UIView *previewCard;
@end

@implementation StudioViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoneAura Studio";
    self.view.backgroundColor = PAHex(0x030712, 1.0);
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12.0;
    self.stack.layoutMargins = UIEdgeInsetsMake(18, 18, 34, 18);
    self.stack.layoutMarginsRelativeArrangement = YES;
    [self.scrollView addSubview:self.stack];

    [self buildHero];
    [self addSection:@"Core"];
    [self addSwitch:@"Enable PhoneAura" detail:@"Master switch for the redesigned Phone app." key:@"enabled" fallback:YES];
    [self addSwitch:@"Safe Mode" detail:@"Keeps Apple navigation visible on detail and call screens." key:@"safeMode" fallback:YES];

    [self addSection:@"Replace Apple Surfaces"];
    [self addSwitch:@"Hide Apple Keypad" detail:@"Removes the original circular dial buttons before showing Concept D." key:@"hideStockKeypad" fallback:YES];
    [self addSwitch:@"Replace Apple Favorites" detail:@"Hides the stock empty/list surface and shows Concept D favorite cards." key:@"replaceFavorites" fallback:YES];
    [self addSwitch:@"Concept D Contacts" detail:@"Applies teal cards and a hero My Card treatment." key:@"replaceContacts" fallback:YES];
    [self addSwitch:@"Concept D Recents" detail:@"Uses navy call cards with narrow status accents." key:@"replaceRecents" fallback:YES];
    [self addSwitch:@"Concept D Voicemail" detail:@"Uses pink, orange and purple voicemail cards." key:@"replaceVoicemail" fallback:YES];

    [self addSection:@"Appearance"];
    [self addSwitch:@"Header Subtitles" detail:@"Shows the Concept D descriptive line below each title." key:@"showSubtitles" fallback:YES];
    [self addSwitch:@"Smart Shortcut Cards" detail:@"Shows Family, Work, Voicemail and Create Shortcut cards." key:@"showShortcuts" fallback:YES];
    [self addSwitch:@"Haptic Feedback" detail:@"Adds feedback to dock and keypad actions." key:@"haptics" fallback:YES];
    [self addSwitch:@"Fluid Animations" detail:@"Enables spring and press animations." key:@"animations" fallback:YES];
    [self addSlider:@"Card Opacity" key:@"cardOpacity" minimum:0.70 maximum:1.0 fallback:0.96];
    [self addSlider:@"Corner Radius" key:@"cornerRadius" minimum:10.0 maximum:24.0 fallback:16.0];

    [self addSection:@"Actions"];
    [self addAction:@"Open Phone" symbol:@"phone.fill" selector:@selector(openPhone) accent:PAHex(0x31C85A,1)];
    [self addAction:@"Restart Phone App" symbol:@"arrow.clockwise" selector:@selector(restartPhone) accent:PAHex(0xFF7A1A,1)];
    [self addAction:@"Restore Stock Interface" symbol:@"arrow.uturn.backward.circle.fill" selector:@selector(restoreStock) accent:PAHex(0xFF5B61,1)];

    self.stack.frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 10);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGSize size = [self.stack systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.stack.frame = CGRectMake(0, 0, width, size.height);
    self.scrollView.contentSize = CGSizeMake(width, size.height);
}

- (void)buildHero {
    UIView *hero = [[UIView alloc] init];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.layer.cornerRadius = 26;
    hero.layer.cornerCurve = kCACornerCurveContinuous;
    hero.clipsToBounds = YES;
    [hero.heightAnchor constraintEqualToConstant:210].active = YES;

    CAGradientLayer *background = [CAGradientLayer layer];
    background.colors = @[(id)PAHex(0x111C3B,1).CGColor,(id)PAHex(0x071228,1).CGColor,(id)PAHex(0x241347,1).CGColor];
    background.startPoint = CGPointMake(0,0);
    background.endPoint = CGPointMake(1,1);
    background.frame = CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width-36,210);
    [hero.layer insertSublayer:background atIndex:0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20,18,280,37)];
    title.text = @"Bold Card Studio";
    title.font = [UIFont systemFontOfSize:29 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    [hero addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(21,55,300,24)];
    subtitle.text = @"Concept D · iOS 16 RootHide";
    subtitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    subtitle.textColor = PAHex(0xB7C1D8,1);
    [hero addSubview:subtitle];

    NSArray *colors = @[PAHex(0xFF5B61,1),PAHex(0x6F63FF,1),PAHex(0x18C8B7,1),PAHex(0xFF7A1A,1),PAHex(0xFF3E88,1)];
    NSArray *titles = @[@"Favorites",@"Recents",@"Contacts",@"Keypad",@"Voicemail"];
    CGFloat cardWidth = (UIScreen.mainScreen.bounds.size.width-36-40-24)/3.0;
    for (NSInteger i=0;i<3;i++) {
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20+i*(cardWidth+12),96,cardWidth,83)];
        card.backgroundColor = [colors[i] colorWithAlphaComponent:0.90];
        card.layer.cornerRadius = 16;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(card.bounds,10,10)];
        label.text = titles[i];
        label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        label.textColor = UIColor.whiteColor;
        label.numberOfLines = 2;
        [card addSubview:label];
        [hero addSubview:card];
    }
    [self.stack addArrangedSubview:hero];
}

- (void)addSection:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title.uppercaseString;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    label.textColor = PAHex(0x8491AC,1);
    label.layoutMargins = UIEdgeInsetsMake(8,4,0,0);
    [label.heightAnchor constraintEqualToConstant:28].active = YES;
    [self.stack addArrangedSubview:label];
}

- (UIView *)baseCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = PAHex(0x121B33,0.98);
    card.layer.cornerRadius = 17;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.7;
    card.layer.borderColor = PAHex(0x53617D,0.28).CGColor;
    return card;
}

- (void)addSwitch:(NSString *)title detail:(NSString *)detail key:(NSString *)key fallback:(BOOL)fallback {
    UIView *card = [self baseCard];
    [card.heightAnchor constraintEqualToConstant:76].active = YES;
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16,11,230,24)];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.whiteColor;
    [card addSubview:titleLabel];
    UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(16,36,250,30)];
    detailLabel.text = detail;
    detailLabel.numberOfLines = 2;
    detailLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    detailLabel.textColor = PAHex(0x9EABC4,1);
    [card addSubview:detailLabel];
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(UIScreen.mainScreen.bounds.size.width-36-69,22,51,31)];
    toggle.onTintColor = PAHex(0x18C8B7,1);
    toggle.accessibilityIdentifier = key;
    id stored = [self valueForKey:key];
    toggle.on = stored ? [stored boolValue] : fallback;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:toggle];
    [self.stack addArrangedSubview:card];
}

- (void)addSlider:(NSString *)title key:(NSString *)key minimum:(CGFloat)minimum maximum:(CGFloat)maximum fallback:(CGFloat)fallback {
    UIView *card = [self baseCard];
    [card.heightAnchor constraintEqualToConstant:78].active = YES;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16,10,220,22)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    [card addSubview:label];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16,38,UIScreen.mainScreen.bounds.size.width-36-64,28)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.minimumTrackTintColor = PAHex(0x6F63FF,1);
    slider.maximumTrackTintColor = PAHex(0x34405D,1);
    slider.accessibilityIdentifier = key;
    id stored = [self valueForKey:key];
    slider.value = stored ? [stored floatValue] : fallback;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];
    UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(UIScreen.mainScreen.bounds.size.width-36-52,39,42,24)];
    value.tag = 904;
    value.textAlignment = NSTextAlignmentRight;
    value.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    value.textColor = PAHex(0xB9C4D9,1);
    value.text = [NSString stringWithFormat:@"%.2f",slider.value];
    [card addSubview:value];
    [self.stack addArrangedSubview:card];
}

- (void)addAction:(NSString *)title symbol:(NSString *)symbol selector:(SEL)selector accent:(UIColor *)accent {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [accent colorWithAlphaComponent:0.88];
    button.layer.cornerRadius = 17;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.tintColor = UIColor.whiteColor;
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [button setTitle:[@"  " stringByAppendingString:title] forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:56].active = YES;
    [self.stack addArrangedSubview:button];
}

- (id)valueForKey:(NSString *)key {
    CFPreferencesAppSynchronize(PADomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PADomain);
    return CFBridgingRelease(value);
}

- (void)setValue:(id)value forPreferenceKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, PADomain);
    CFPreferencesAppSynchronize(PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), PANotification, NULL, NULL, true);
}

- (void)toggleChanged:(UISwitch *)sender {
    [self setValue:@(sender.on) forPreferenceKey:sender.accessibilityIdentifier];
}

- (void)sliderChanged:(UISlider *)sender {
    [self setValue:@(sender.value) forPreferenceKey:sender.accessibilityIdentifier];
    UILabel *value = [sender.superview viewWithTag:904];
    value.text = [NSString stringWithFormat:@"%.2f",sender.value];
}

- (void)openPhone {
    NSURL *url = [NSURL URLWithString:@"mobilephone://"];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)restartPhone {
    pid_t pid = 0;
    const char *argv[] = {"killall", "-9", "MobilePhone", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)argv, environ);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self openPhone]; });
}

- (void)restoreStock {
    [self setValue:@NO forPreferenceKey:@"enabled"];
    [self restartPhone];
}

@end
