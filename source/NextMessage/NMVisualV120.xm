#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const NMVDomain = @"com.nextsolution.nextmessage";
static const NSInteger NMVOldCardTag = 727211;
static const NSInteger NMVAccentTag = 727212;
static char NMVHeroKey;
static char NMVInsetKey;
static char NMVBalloonGradientKey;

@interface CKConversationListViewController : UIViewController
- (UITableView *)tableView;
@end
@interface CKConversationViewController : UIViewController @end
@interface CKColoredBalloonView : UIView @end
@interface CKBalloonView : UIView @end
@interface CKTextBalloonView : UIView @end
@interface CKMessageEntryView : UIView @end
@interface CKMessageEntryContentView : UIView @end
@interface CKTranscriptCollectionView : UICollectionView @end

static BOOL NMVIsMessages(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"];
}

static UIColor *NMVColor(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF)/255.0
                           green:((hex >> 8) & 0xFF)/255.0
                            blue:(hex & 0xFF)/255.0
                           alpha:alpha];
}

static BOOL NMVBool(NSString *key, BOOL fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)NMVDomain));
    return value ? [value boolValue] : fallback;
}

static CGFloat NMVFloat(NSString *key, CGFloat fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)NMVDomain));
    return value ? [value doubleValue] : fallback;
}

static BOOL NMVEnabled(void) {
    return NMVBool(@"enabled", YES);
}

static UIViewController *NMVControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL NMVIsConversationListCell(UITableViewCell *cell) {
    UIViewController *controller = NMVControllerForView(cell);
    return [NSStringFromClass(controller.class) containsString:@"CKConversationListViewController"];
}

static void NMVCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) NMVCollectLabels(subview, labels);
}

static void NMVCollectImages(UIView *view, NSMutableArray<UIImageView *> *images) {
    if ([view isKindOfClass:UIImageView.class]) [images addObject:(UIImageView *)view];
    for (UIView *subview in view.subviews) NMVCollectImages(subview, images);
}

static NSString *NMVCellSeed(UITableViewCell *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMVCollectLabels(cell.contentView, labels);
    for (UILabel *label in labels) {
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) return text;
    }
    return NSStringFromClass(cell.class);
}

static UIColor *NMVAccentForCell(UITableViewCell *cell) {
    NSArray<UIColor *> *palette = @[
        NMVColor(0xFF5B61,1),
        NMVColor(0x6F63FF,1),
        NMVColor(0x18C8B7,1),
        NMVColor(0xFF7A1A,1)
    ];
    return palette[NMVCellSeed(cell).hash % palette.count];
}

@interface NMVHeroView : UIView
@property(nonatomic,weak) UIViewController *target;
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIButton *composeButton;
@end

@implementation NMVHeroView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 26;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.34;
        self.layer.shadowRadius = 18;
        self.layer.shadowOffset = CGSizeMake(0,8);

        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[
            (id)NMVColor(0xFF5B61,1).CGColor,
            (id)NMVColor(0x6F63FF,1).CGColor,
            (id)NMVColor(0x18C8B7,1).CGColor
        ];
        _gradient.startPoint = CGPointMake(0,0.25);
        _gradient.endPoint = CGPointMake(1,0.8);
        _gradient.cornerRadius = 26;
        [self.layer insertSublayer:_gradient atIndex:0];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"Next Message";
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = @"Your conversations, beautifully organized.";
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
        _subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [self addSubview:_subtitleLabel];

        _composeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _composeButton.tintColor = UIColor.whiteColor;
        _composeButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
        _composeButton.layer.cornerRadius = 18;
        _composeButton.layer.cornerCurve = kCACornerCurveContinuous;
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
        [_composeButton setImage:[UIImage systemImageNamed:@"square.and.pencil"
                                         withConfiguration:configuration]
                        forState:UIControlStateNormal];
        [_composeButton addTarget:self action:@selector(composeTapped)
                 forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_composeButton];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
    self.composeButton.frame = CGRectMake(CGRectGetWidth(self.bounds)-66,22,48,48);
    self.titleLabel.frame = CGRectMake(20,17,CGRectGetWidth(self.bounds)-96,40);
    self.subtitleLabel.frame = CGRectMake(21,58,CGRectGetWidth(self.bounds)-96,22);
}

- (void)composeTapped {
    UIImpactFeedbackGenerator *generator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];

    for (NSString *name in @[@"_newConversation:", @"newConversation:",
                             @"composeButtonTapped:", @"_composeButtonTapped:",
                             @"showNewMessageComposition:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([self.target respondsToSelector:selector]) {
            typedef void (*Function)(id, SEL, id);
            ((Function)objc_msgSend)(self.target, selector, self.composeButton);
            return;
        }
    }
}

@end

static void NMVApplyNavigation(UIViewController *controller) {
    UINavigationBar *bar = controller.navigationController.navigationBar;
    if (!bar) return;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = NMVColor(0x070E20,0.94);
    appearance.shadowColor = NMVColor(0x6F63FF,0.20);
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]
    };
    appearance.largeTitleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]
    };
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    bar.tintColor = NMVColor(0x64DCCB,1);
}

static void NMVApplyControllerBackground(UIViewController *controller) {
    if (!NMVEnabled() || !controller.view) return;
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    controller.view.backgroundColor = NMVColor(0x050914,1);

    UIView *background = [controller.view viewWithTag:727220];
    if (!background && NMVBool(@"glassBackground", YES)) {
        background = [[UIView alloc] initWithFrame:controller.view.bounds];
        background.tag = 727220;
        background.userInteractionEnabled = NO;
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"NMVMainGradient";
        gradient.colors = @[
            (id)NMVColor(0x050914,1).CGColor,
            (id)NMVColor(0x10122B,1).CGColor,
            (id)NMVColor(0x071C25,1).CGColor
        ];
        gradient.locations = @[@0,@0.58,@1];
        gradient.startPoint = CGPointMake(0,0);
        gradient.endPoint = CGPointMake(1,1);
        [background.layer addSublayer:gradient];
        [controller.view insertSubview:background atIndex:0];
    }
    if (background) {
        background.frame = controller.view.bounds;
        for (CALayer *layer in background.layer.sublayers) layer.frame = background.bounds;
    }
    NMVApplyNavigation(controller);
}

static void NMVInstallHero(CKConversationListViewController *controller) {
    UITableView *table = [controller respondsToSelector:@selector(tableView)] ? [controller tableView] : nil;
    if (!table) return;

    NMVHeroView *hero = objc_getAssociatedObject(controller, &NMVHeroKey);
    if (!hero) {
        hero = [[NMVHeroView alloc] init];
        hero.target = controller;
        [table addSubview:hero];
        objc_setAssociatedObject(controller,&NMVHeroKey,hero,OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (!objc_getAssociatedObject(table,&NMVInsetKey)) {
            UIEdgeInsets inset = table.contentInset;
            inset.top += 118;
            table.contentInset = inset;
            UIEdgeInsets indicators = table.scrollIndicatorInsets;
            indicators.top += 118;
            table.scrollIndicatorInsets = indicators;
            objc_setAssociatedObject(table,&NMVInsetKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    hero.frame = CGRectMake(12,-108,MAX(CGRectGetWidth(table.bounds)-24,100),92);
}

static void NMVRemoveOldCardFromNonListCell(UITableViewCell *cell) {
    UIView *card = [cell.contentView viewWithTag:NMVOldCardTag];
    if (card) [card removeFromSuperview];
    UIView *accent = [cell.contentView viewWithTag:NMVAccentTag];
    if (accent) [accent removeFromSuperview];
    cell.backgroundColor = UIColor.secondarySystemBackgroundColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
}

static void NMVStyleConversationCell(UITableViewCell *cell) {
    if (!NMVEnabled() || !cell.window) return;

    if (!NMVIsConversationListCell(cell)) {
        NMVRemoveOldCardFromNonListCell(cell);
        return;
    }

    if (!NMVBool(@"conversationCards", YES)) return;

    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    CGFloat radius = MIN(MAX(NMVFloat(@"cornerRadius",20),14),30);
    CGFloat opacity = MIN(MAX(NMVFloat(@"cardOpacity",0.96),0.70),1.0);
    UIColor *accent = NMVAccentForCell(cell);

    UIView *card = [cell.contentView viewWithTag:NMVOldCardTag];
    UIView *accentStrip = [cell.contentView viewWithTag:NMVAccentTag];
    if (!card) {
        card = [[UIView alloc] init];
        card.tag = NMVOldCardTag;
        card.userInteractionEnabled = NO;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderWidth = 0.8;
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.25;
        card.layer.shadowRadius = 12;
        card.layer.shadowOffset = CGSizeMake(0,5);
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"NMVCellGradient";
        [card.layer addSublayer:gradient];
        [cell.contentView insertSubview:card atIndex:0];

        accentStrip = [[UIView alloc] init];
        accentStrip.tag = NMVAccentTag;
        accentStrip.userInteractionEnabled = NO;
        [cell.contentView insertSubview:accentStrip aboveSubview:card];
    }

    card.frame = CGRectInset(cell.contentView.bounds,9,5);
    card.layer.cornerRadius = radius;
    card.layer.borderColor = [accent colorWithAlphaComponent:0.32].CGColor;
    card.alpha = opacity;

    for (CALayer *layer in card.layer.sublayers) {
        if ([layer.name isEqualToString:@"NMVCellGradient"] ||
            [layer.name isEqualToString:@"NMCellGradient"]) {
            CAGradientLayer *gradient = (CAGradientLayer *)layer;
            gradient.frame = card.bounds;
            gradient.cornerRadius = radius;
            gradient.colors = @[
                (id)[accent colorWithAlphaComponent:0.28].CGColor,
                (id)NMVColor(0x111A33,0.99).CGColor,
                (id)NMVColor(0x17213D,0.99).CGColor
            ];
            gradient.startPoint = CGPointMake(0,0.5);
            gradient.endPoint = CGPointMake(1,0.5);
        }
    }

    accentStrip.backgroundColor = accent;
    accentStrip.layer.cornerRadius = 2.5;
    accentStrip.frame = CGRectMake(CGRectGetMinX(card.frame)+2,
                                   CGRectGetMinY(card.frame)+14,
                                   5,
                                   MAX(CGRectGetHeight(card.frame)-28,18));

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMVCollectLabels(cell.contentView,labels);
    CGFloat maxFont = 0;
    for (UILabel *label in labels) maxFont = MAX(maxFont,label.font.pointSize);
    for (UILabel *label in labels) {
        if (label.font.pointSize >= maxFont-0.5) {
            label.textColor = UIColor.whiteColor;
            label.font = [UIFont systemFontOfSize:label.font.pointSize weight:UIFontWeightSemibold];
        } else {
            label.textColor = NMVColor(0xAEBBD5,1);
        }
    }

    NSMutableArray<UIImageView *> *images = [NSMutableArray array];
    NMVCollectImages(cell.contentView,images);
    for (UIImageView *image in images) {
        if (CGRectGetWidth(image.bounds) >= 34 && CGRectGetHeight(image.bounds) >= 34) {
            image.layer.cornerRadius = MIN(CGRectGetWidth(image.bounds),CGRectGetHeight(image.bounds))/2;
            image.layer.borderWidth = 1.5;
            image.layer.borderColor = [accent colorWithAlphaComponent:0.58].CGColor;
            image.clipsToBounds = YES;
        }
    }
}

static BOOL NMVOutgoing(UIView *view) {
    if (!view.window) return NO;
    CGRect rect = [view convertRect:view.bounds toView:view.window];
    return CGRectGetMidX(rect) > CGRectGetWidth(view.window.bounds)*0.52;
}

static void NMVStyleBalloon(UIView *view) {
    if (!NMVEnabled() || !NMVBool(@"bubbleStyling",YES) ||
        !view.window || CGRectIsEmpty(view.bounds)) return;

    BOOL outgoing = NMVOutgoing(view);
    CGFloat radius = MIN(MAX(NMVFloat(@"cornerRadius",20),18),26);
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = 0.8;
    view.layer.borderColor =
        (outgoing ? NMVColor(0xFF6A79,0.58) : NMVColor(0x7182AA,0.35)).CGColor;

    CAGradientLayer *gradient = objc_getAssociatedObject(view,&NMVBalloonGradientKey);
    if (!gradient) {
        gradient = [CAGradientLayer layer];
        [view.layer insertSublayer:gradient atIndex:0];
        objc_setAssociatedObject(view,&NMVBalloonGradientKey,gradient,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gradient.frame = view.bounds;
    gradient.cornerRadius = radius;
    gradient.startPoint = CGPointMake(0,0.5);
    gradient.endPoint = CGPointMake(1,0.5);
    gradient.colors = outgoing
        ? @[(id)NMVColor(0xFF5B61,1).CGColor,(id)NMVColor(0x6F63FF,1).CGColor]
        : @[(id)NMVColor(0x1B2A4B,0.99).CGColor,(id)NMVColor(0x10182E,0.99).CGColor];
}

static void NMVStyleComposer(UIView *view) {
    if (!NMVEnabled() || !NMVBool(@"inputStyling",YES) || !view.window) return;
    view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    view.backgroundColor = NMVColor(0x0D172D,0.97);
    view.layer.cornerRadius = 22;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1;
    view.layer.borderColor = NMVColor(0x65779F,0.34).CGColor;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.22;
    view.layer.shadowRadius = 12;
    view.layer.shadowOffset = CGSizeMake(0,4);

    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UITextView.class]) {
            UITextView *text = (UITextView *)subview;
            text.textColor = UIColor.whiteColor;
            text.keyboardAppearance = UIKeyboardAppearanceDark;
            text.backgroundColor = UIColor.clearColor;
        } else if ([subview isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)subview;
            field.textColor = UIColor.whiteColor;
            field.keyboardAppearance = UIKeyboardAppearanceDark;
            field.backgroundColor = UIColor.clearColor;
        } else if ([subview isKindOfClass:UIButton.class]) {
            subview.tintColor = NMVColor(0x64DCCB,1);
        }
    }
}

static void NMVStyleSearch(UISearchBar *bar) {
    if (!NMVIsMessages() || !NMVEnabled() || !bar.window) return;
    bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    bar.backgroundImage = [UIImage new];
    UITextField *field = bar.searchTextField;
    field.backgroundColor = NMVColor(0x131E36,0.97);
    field.textColor = UIColor.whiteColor;
    field.tintColor = NMVColor(0x64DCCB,1);
    field.layer.cornerRadius = 15;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.borderWidth = 0.8;
    field.layer.borderColor = NMVColor(0x65779F,0.30).CGColor;
    field.leftView.tintColor = NMVColor(0xAEBBD5,1);
}

%hook UIWindow

- (void)makeKeyAndVisible {
    if (NMVIsMessages() && NMVEnabled()) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (NMVIsMessages() && NMVEnabled()) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.tintColor = NMVColor(0x64DCCB,1);
    }
}

%end

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (NMVIsMessages() && NMVEnabled() &&
        [NSStringFromClass(self.class) containsString:@"CK"]) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
}

%end

%hook CKConversationListViewController

- (void)viewDidLoad {
    %orig;
    if (!NMVEnabled()) return;
    self.navigationItem.title = @"";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UITableView *table = [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    NMVApplyControllerBackground(self);
    NMVInstallHero(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!NMVEnabled()) return;
    NMVApplyControllerBackground(self);
    NMVInstallHero(self);
    UITableView *table = [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!NMVEnabled()) return;
    NMVApplyControllerBackground(self);
    NMVInstallHero(self);
}

%end

%hook CKConversationViewController

- (void)viewDidLoad {
    %orig;
    if (NMVEnabled()) NMVApplyControllerBackground(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (NMVEnabled()) NMVApplyControllerBackground(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (NMVEnabled()) NMVApplyControllerBackground(self);
}

%end

%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (NMVIsMessages()) NMVStyleConversationCell(self);
}

%end

%hook UISearchBar

- (void)layoutSubviews {
    %orig;
    NMVStyleSearch(self);
}

%end

%hook UICollectionView

- (void)didMoveToWindow {
    %orig;
    if (!NMVIsMessages() || !NMVEnabled()) return;
    NSString *name = NSStringFromClass(self.class);
    if ([name containsString:@"Transcript"] ||
        [name containsString:@"Conversation"] ||
        [name containsString:@"CK"]) {
        self.backgroundColor = UIColor.clearColor;
    }
}

%end

%hook CKColoredBalloonView
- (void)layoutSubviews {
    %orig;
    NMVStyleBalloon(self);
}
%end

%hook CKBalloonView
- (void)layoutSubviews {
    %orig;
    NMVStyleBalloon(self);
}
%end

%hook CKTextBalloonView
- (void)layoutSubviews {
    %orig;
    NMVStyleBalloon(self);
}
%end

%hook CKMessageEntryView
- (void)layoutSubviews {
    %orig;
    NMVStyleComposer(self);
}
%end

%hook CKMessageEntryContentView
- (void)layoutSubviews {
    %orig;
    NMVStyleComposer(self);
}
%end

%hook CKTranscriptCollectionView
- (void)layoutSubviews {
    %orig;
    if (NMVIsMessages() && NMVEnabled()) self.backgroundColor = UIColor.clearColor;
}
%end
