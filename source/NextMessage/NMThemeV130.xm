#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>
#import "NMCore.h"

void NMInstallSwipeForConversationTable(UITableView *tableView);

static const NSInteger NMHeaderContainerTag = 740001;
static const NSInteger NMConversationCardTag = 740002;
static const NSInteger NMAccentStripTag = 740003;
static char NMBubbleGradientKey;

@interface CKConversationListViewController : UIViewController
- (UITableView *)tableView;
@end
@interface CKConversationViewController : UIViewController @end

static void NMCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) NMCollectLabels(subview, labels);
}

static void NMCollectImages(UIView *view, NSMutableArray<UIImageView *> *images) {
    if ([view isKindOfClass:UIImageView.class]) [images addObject:(UIImageView *)view];
    for (UIView *subview in view.subviews) NMCollectImages(subview, images);
}

static BOOL NMIsConversationListCell(UITableViewCell *cell) {
    UIViewController *controller = NMControllerForView(cell);
    return [NSStringFromClass(controller.class)
            rangeOfString:@"ConversationList"
            options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static UIColor *NMAccentForCell(UITableViewCell *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(cell.contentView, labels);
    NSString *seed = NSStringFromClass(cell.class);
    for (UILabel *label in labels) {
        NSString *text =
            [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) {
            seed = text;
            break;
        }
    }
    NSArray<UIColor *> *palette = @[
        NMColor(0xFF5B61,1),
        NMColor(0x6F63FF,1),
        NMColor(0x18C8B7,1),
        NMColor(0xFF7A1A,1)
    ];
    return palette[labs((long)seed.hash) % palette.count];
}

@interface NMMessageHeaderView : UIView
@property(nonatomic,weak) UIViewController *target;
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIButton *composeButton;
@end

@implementation NMMessageHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 25;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.32;
        self.layer.shadowRadius = 18;
        self.layer.shadowOffset = CGSizeMake(0,8);

        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[
            (id)NMColor(0xFF5B61,1).CGColor,
            (id)NMColor(0x6F63FF,1).CGColor,
            (id)NMColor(0x18C8B7,1).CGColor
        ];
        _gradient.startPoint = CGPointMake(0,0.25);
        _gradient.endPoint = CGPointMake(1,0.8);
        _gradient.cornerRadius = 25;
        [self.layer insertSublayer:_gradient atIndex:0];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"Next Message";
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont systemFontOfSize:29 weight:UIFontWeightBold];
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = @"Messages, redesigned.";
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
        _subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [self addSubview:_subtitleLabel];

        _composeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _composeButton.tintColor = UIColor.whiteColor;
        _composeButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
        _composeButton.layer.cornerRadius = 18;
        _composeButton.layer.cornerCurve = kCACornerCurveContinuous;
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:18
                                                             weight:UIImageSymbolWeightBold];
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
    self.composeButton.frame = CGRectMake(CGRectGetWidth(self.bounds)-64, 20, 46, 46);
    self.titleLabel.frame = CGRectMake(20, 15, CGRectGetWidth(self.bounds)-94, 38);
    self.subtitleLabel.frame = CGRectMake(21, 52, CGRectGetWidth(self.bounds)-94, 21);
}

- (void)composeTapped {
    NMHaptic(NO);
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

static void NMApplyNavigationTheme(UIViewController *controller) {
    UINavigationBar *bar = controller.navigationController.navigationBar;
    if (!bar) return;

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = NMColor(0x070E20,0.96);
    appearance.shadowColor = NMColor(0x6F63FF,0.18);
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
    bar.tintColor = NMColor(0x64DCCB,1);
}

static void NMApplyControllerTheme(UIViewController *controller) {
    if (!NMEnabled() || !controller.view) return;

    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    controller.view.backgroundColor = NMColor(0x050914,1);

    UIView *background = [controller.view viewWithTag:740010];
    if (!background && NMPreferenceBool(@"glassBackground", YES)) {
        background = [[UIView alloc] initWithFrame:controller.view.bounds];
        background.tag = 740010;
        background.userInteractionEnabled = NO;

        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"NMFullBackground";
        gradient.colors = @[
            (id)NMColor(0x050914,1).CGColor,
            (id)NMColor(0x11132C,1).CGColor,
            (id)NMColor(0x071C25,1).CGColor
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
    NMApplyNavigationTheme(controller);
}

static void NMInstallHeader(CKConversationListViewController *controller) {
    UITableView *tableView =
        [controller respondsToSelector:@selector(tableView)] ? [controller tableView] : nil;
    if (!tableView) return;

    UIView *header = tableView.tableHeaderView;
    if (header.tag != NMHeaderContainerTag) {
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0,0,
                                      MAX(CGRectGetWidth(tableView.bounds),320),112)];
        container.tag = NMHeaderContainerTag;
        container.backgroundColor = UIColor.clearColor;

        NMMessageHeaderView *hero =
            [[NMMessageHeaderView alloc] initWithFrame:CGRectMake(12,10,
                                      MAX(CGRectGetWidth(tableView.bounds)-24,296),92)];
        hero.target = controller;
        hero.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [container addSubview:hero];

        tableView.tableHeaderView = container;
    } else {
        header.frame = CGRectMake(0,0,CGRectGetWidth(tableView.bounds),112);
        UIView *hero = header.subviews.firstObject;
        hero.frame = CGRectMake(12,10,MAX(CGRectGetWidth(tableView.bounds)-24,296),92);
        tableView.tableHeaderView = header;
    }
}

static void NMStyleConversationCell(UITableViewCell *cell) {
    if (!NMEnabled() || !cell.window || !NMIsConversationListCell(cell)) return;

    if (!NMPreferenceBool(@"conversationCards", YES)) {
        UIView *card = [cell.contentView viewWithTag:NMConversationCardTag];
        [card removeFromSuperview];
        [[cell.contentView viewWithTag:NMAccentStripTag] removeFromSuperview];
        return;
    }

    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    CGFloat radius = MIN(MAX(NMPreferenceFloat(@"cornerRadius",20),14),30);
    CGFloat opacity = MIN(MAX(NMPreferenceFloat(@"cardOpacity",0.96),0.70),1.0);
    UIColor *accent = NMAccentForCell(cell);

    UIView *card = [cell.contentView viewWithTag:NMConversationCardTag];
    UIView *strip = [cell.contentView viewWithTag:NMAccentStripTag];
    if (!card) {
        card = [[UIView alloc] init];
        card.tag = NMConversationCardTag;
        card.userInteractionEnabled = NO;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderWidth = 0.8;
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.24;
        card.layer.shadowRadius = 11;
        card.layer.shadowOffset = CGSizeMake(0,5);

        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"NMConversationGradient";
        [card.layer addSublayer:gradient];
        [cell.contentView insertSubview:card atIndex:0];

        strip = [[UIView alloc] init];
        strip.tag = NMAccentStripTag;
        strip.userInteractionEnabled = NO;
        [cell.contentView insertSubview:strip aboveSubview:card];
    }

    card.frame = CGRectInset(cell.contentView.bounds,9,5);
    card.layer.cornerRadius = radius;
    card.layer.borderColor = [accent colorWithAlphaComponent:0.34].CGColor;
    card.alpha = opacity;

    for (CALayer *layer in card.layer.sublayers) {
        if ([layer.name isEqualToString:@"NMConversationGradient"]) {
            CAGradientLayer *gradient = (CAGradientLayer *)layer;
            gradient.frame = card.bounds;
            gradient.cornerRadius = radius;
            gradient.colors = @[
                (id)[accent colorWithAlphaComponent:0.28].CGColor,
                (id)NMColor(0x111A33,0.99).CGColor,
                (id)NMColor(0x17213D,0.99).CGColor
            ];
            gradient.startPoint = CGPointMake(0,0.5);
            gradient.endPoint = CGPointMake(1,0.5);
        }
    }

    strip.backgroundColor = accent;
    strip.layer.cornerRadius = 2.5;
    strip.frame = CGRectMake(CGRectGetMinX(card.frame)+2,
                             CGRectGetMinY(card.frame)+14,
                             5,
                             MAX(CGRectGetHeight(card.frame)-28,18));

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(cell.contentView, labels);
    CGFloat largest = 0;
    for (UILabel *label in labels) largest = MAX(largest,label.font.pointSize);
    for (UILabel *label in labels) {
        if (label.font.pointSize >= largest-0.5) {
            label.textColor = UIColor.whiteColor;
            label.font = [UIFont systemFontOfSize:label.font.pointSize
                                           weight:UIFontWeightSemibold];
        } else {
            label.textColor = NMColor(0xAEBBD5,1);
        }
    }

    NSMutableArray<UIImageView *> *images = [NSMutableArray array];
    NMCollectImages(cell.contentView, images);
    for (UIImageView *image in images) {
        if (CGRectGetWidth(image.bounds) >= 34 && CGRectGetHeight(image.bounds) >= 34) {
            image.layer.cornerRadius =
                MIN(CGRectGetWidth(image.bounds),CGRectGetHeight(image.bounds))/2;
            image.layer.borderWidth = 1.5;
            image.layer.borderColor = [accent colorWithAlphaComponent:0.62].CGColor;
            image.clipsToBounds = YES;
        }
    }
}

static BOOL NMOutgoingBubble(UIView *view) {
    if (!view.window) return NO;
    CGRect rect = [view convertRect:view.bounds toView:view.window];
    return CGRectGetMidX(rect) > CGRectGetWidth(view.window.bounds)*0.52;
}

static void NMStyleBubble(UIView *view) {
    if (!NMEnabled() || !NMPreferenceBool(@"bubbleStyling",YES) ||
        !view.window || CGRectIsEmpty(view.bounds)) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    if (width < 26 || height < 18 ||
        width > CGRectGetWidth(view.window.bounds)*0.92 || height > 520) return;

    BOOL outgoing = NMOutgoingBubble(view);
    CGFloat radius = MIN(MAX(NMPreferenceFloat(@"cornerRadius",20),18),27);
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = 0.8;
    view.layer.borderColor =
        (outgoing ? NMColor(0xFF6A79,0.58) : NMColor(0x7182AA,0.36)).CGColor;

    CAGradientLayer *gradient = objc_getAssociatedObject(view,&NMBubbleGradientKey);
    if (!gradient) {
        gradient = [CAGradientLayer layer];
        [view.layer insertSublayer:gradient atIndex:0];
        objc_setAssociatedObject(view,&NMBubbleGradientKey,gradient,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gradient.frame = view.bounds;
    gradient.cornerRadius = radius;
    gradient.startPoint = CGPointMake(0,0.5);
    gradient.endPoint = CGPointMake(1,0.5);
    gradient.colors = outgoing
        ? @[(id)NMColor(0xFF5B61,1).CGColor,(id)NMColor(0x6F63FF,1).CGColor]
        : @[(id)NMColor(0x1B2A4B,0.99).CGColor,(id)NMColor(0x10182E,0.99).CGColor];

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(view, labels);
    for (UILabel *label in labels) label.textColor = UIColor.whiteColor;
}

static void NMStyleComposer(UIView *view) {
    if (!NMEnabled() || !NMPreferenceBool(@"inputStyling",YES) || !view.window) return;
    CGFloat height = CGRectGetHeight(view.bounds);
    CGFloat width = CGRectGetWidth(view.bounds);
    if (height < 28 || height > 110 || width < 120) return;

    view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    view.backgroundColor = NMColor(0x0D172D,0.97);
    view.layer.cornerRadius = 21;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1;
    view.layer.borderColor = NMColor(0x65779F,0.34).CGColor;

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
            subview.tintColor = NMColor(0x64DCCB,1);
        }
    }
}

static void NMStyleSearch(UISearchBar *bar) {
    if (!NMIsMessagesProcess() || !NMEnabled() || !bar.window) return;
    bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    bar.backgroundImage = [UIImage new];

    UITextField *field = bar.searchTextField;
    field.backgroundColor = NMColor(0x131E36,0.97);
    field.textColor = UIColor.whiteColor;
    field.tintColor = NMColor(0x64DCCB,1);
    field.layer.cornerRadius = 15;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.borderWidth = 0.8;
    field.layer.borderColor = NMColor(0x65779F,0.30).CGColor;
    field.leftView.tintColor = NMColor(0xAEBBD5,1);
}

static void NMStyleRuntimeView(UIView *view) {
    if (!NMIsMessagesProcess() || !NMEnabled() || !view.window) return;

    NSString *name = NSStringFromClass(view.class);
    if ([name rangeOfString:@"Balloon" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"MessagePart" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"ChatItemView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NMStyleBubble(view);
    }

    if ([name rangeOfString:@"MessageEntryContent" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"EntryField" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"ComposeText" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NMStyleComposer(view);
    }

    if ([view isKindOfClass:UICollectionView.class] ||
        [view isKindOfClass:UITableView.class]) {
        UIViewController *controller = NMControllerForView(view);
        NSString *controllerName = NSStringFromClass(controller.class);
        if ([controllerName containsString:@"CK"] ||
            [controllerName containsString:@"Conversation"]) {
            view.backgroundColor = UIColor.clearColor;
        }
    }
}

typedef void (*NMLayoutIMP)(id, SEL);
static NSMutableDictionary<NSString *, NSValue *> *NMOriginalLayoutIMPs;

static void NMRuntimeLayoutSubviews(id object, SEL selector) {
    NMLayoutIMP original = NULL;
    @synchronized(NMOriginalLayoutIMPs) {
        original = [NMOriginalLayoutIMPs[NSStringFromClass([object class])] pointerValue];
    }
    if (original) original(object, selector);
    NMStyleRuntimeView((UIView *)object);
}

static BOOL NMIsUIViewClass(Class cls) {
    Class current = cls;
    while (current) {
        if (current == UIView.class) return YES;
        current = class_getSuperclass(current);
    }
    return NO;
}

static void NMInstallRuntimeViewHooks(void) {
    if (!NMIsMessagesProcess()) return;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSArray<NSString *> *needles = @[
        @"Balloon", @"MessagePart", @"ChatItemView",
        @"MessageEntryContent", @"EntryField", @"ComposeText",
        @"TranscriptCollection"
    ];

    if (!NMOriginalLayoutIMPs) NMOriginalLayoutIMPs = [NSMutableDictionary dictionary];

    for (int index = 0; index < count; index++) {
        Class cls = classes[index];
        if (!NMIsUIViewClass(cls)) continue;

        NSString *className = NSStringFromClass(cls);
        BOOL matches = NO;
        for (NSString *needle in needles) {
            if ([className rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
                matches = YES;
                break;
            }
        }
        if (!matches || NMOriginalLayoutIMPs[className]) continue;

        SEL selector = @selector(layoutSubviews);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;

        IMP original = method_getImplementation(method);
        if (original == (IMP)NMRuntimeLayoutSubviews) continue;
        NMOriginalLayoutIMPs[className] = [NSValue valueWithPointer:original];

        const char *types = method_getTypeEncoding(method);
        if (!class_addMethod(cls, selector, (IMP)NMRuntimeLayoutSubviews, types)) {
            Method ownMethod = class_getInstanceMethod(cls, selector);
            method_setImplementation(ownMethod, (IMP)NMRuntimeLayoutSubviews);
        }
    }
    free(classes);
}

%hook UIWindow

- (void)makeKeyAndVisible {
    if (NMIsMessagesProcess() && NMEnabled()) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (NMIsMessagesProcess() && NMEnabled()) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.tintColor = NMColor(0x64DCCB,1);
    }
}

%end

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!NMIsMessagesProcess() || !NMEnabled()) return;
    NSString *name = NSStringFromClass(self.class);
    if ([name containsString:@"CK"] ||
        [name containsString:@"Conversation"] ||
        [name containsString:@"SMS"]) {
        NMApplyControllerTheme(self);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!NMIsMessagesProcess() || !NMEnabled()) return;
    NSString *name = NSStringFromClass(self.class);
    if ([name containsString:@"CK"] ||
        [name containsString:@"Conversation"] ||
        [name containsString:@"SMS"]) {
        NMApplyControllerTheme(self);
    }
}

%end

%hook CKConversationListViewController

- (void)viewDidLoad {
    %orig;
    if (!NMEnabled()) return;
    self.navigationItem.title = @"";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UITableView *tableView =
        [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    NMApplyControllerTheme(self);
    NMInstallHeader(self);
    NMInstallRuntimeViewHooks();
    NMInstallSwipeForConversationTable(tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!NMEnabled()) return;
    UITableView *tableView =
        [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    NMApplyControllerTheme(self);
    NMInstallHeader(self);
    NMInstallSwipeForConversationTable(tableView);
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!NMEnabled()) return;
    UITableView *tableView =
        [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    NMInstallSwipeForConversationTable(tableView);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!NMEnabled()) return;
    UITableView *tableView =
        [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    NMApplyControllerTheme(self);
    NMInstallHeader(self);
    NMInstallSwipeForConversationTable(tableView);
}

%end

%hook CKConversationViewController

- (void)viewDidLoad {
    %orig;
    if (NMEnabled()) {
        NMApplyControllerTheme(self);
        NMInstallRuntimeViewHooks();
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (NMEnabled()) NMApplyControllerTheme(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (NMEnabled()) NMApplyControllerTheme(self);
}

%end

%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (NMIsMessagesProcess()) NMStyleConversationCell(self);
}

%end

%hook UISearchBar

- (void)layoutSubviews {
    %orig;
    NMStyleSearch(self);
}

%end

%ctor {
    if (!NMIsMessagesProcess()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NMInstallRuntimeViewHooks();
    });
}
