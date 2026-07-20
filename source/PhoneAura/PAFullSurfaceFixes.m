#import "PAFullSurfaceFixes.h"
#import "PAConceptDUI.h"
#import <objc/runtime.h>

static CFStringRef const PADomain = CFSTR("com.zeshan.phoneaura");
static const void *PAHiddenOriginalKey = &PAHiddenOriginalKey;
static const void *PAFavoritesOverlayKey = &PAFavoritesOverlayKey;

static BOOL PABool(NSString *key, BOOL fallback) {
    CFPreferencesAppSynchronize(PADomain);
    CFPropertyListRef raw = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PADomain);
    if (!raw) return fallback;
    id value = CFBridgingRelease(raw);
    return [value boolValue];
}

static UIViewController *PATop(UITabBarController *tab) {
    UIViewController *selected = tab.selectedViewController;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController *)selected).topViewController;
    }
    return selected;
}

static BOOL PAIsProtectedView(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"PAStudioKeypadView"] || [name containsString:@"PAFavoritesReplacementView"];
}

static void PAHideOriginalChildren(UIView *root, UIView *replacement) {
    for (UIView *subview in root.subviews) {
        if (subview == replacement || PAIsProtectedView(subview)) continue;
        if (![objc_getAssociatedObject(subview, PAHiddenOriginalKey) boolValue]) {
            objc_setAssociatedObject(subview, PAHiddenOriginalKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        subview.hidden = YES;
        subview.userInteractionEnabled = NO;
    }
}

static void PARestoreOriginalChildren(UIView *root) {
    for (UIView *subview in root.subviews) {
        if ([objc_getAssociatedObject(subview, PAHiddenOriginalKey) boolValue]) {
            subview.hidden = NO;
            subview.userInteractionEnabled = YES;
            objc_setAssociatedObject(subview, PAHiddenOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

@interface PAFavoriteActionCard : UIControl
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon colors:(NSArray<UIColor *> *)colors;
@end

@implementation PAFavoriteActionCard
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.cornerRadius = 20;
        self.clipsToBounds = YES;
        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0,0);
        _gradient.endPoint = CGPointMake(1,1);
        [self.layer insertSublayer:_gradient atIndex:0];
        _iconView = [[UIImageView alloc] init];
        _iconView.tintColor = UIColor.whiteColor;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        [self addSubview:_titleLabel];
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
        _subtitleLabel.numberOfLines = 2;
        [self addSubview:_subtitleLabel];
        [self addTarget:self action:@selector(pressDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(pressUp) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    }
    return self;
}
- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon colors:(NSArray<UIColor *> *)colors {
    self.titleLabel.text = title; self.subtitleLabel.text = subtitle;
    self.iconView.image = [UIImage systemImageNamed:icon];
    NSMutableArray *cg = [NSMutableArray array]; for (UIColor *color in colors) [cg addObject:(id)color.CGColor];
    self.gradient.colors = cg;
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.gradient.frame = self.bounds;
    CGFloat h = CGRectGetHeight(self.bounds);
    self.iconView.frame = CGRectMake(16, 16, h > 110 ? 48 : 34, h > 110 ? 48 : 34);
    CGFloat textX = CGRectGetMaxX(self.iconView.frame)+12;
    self.titleLabel.frame = CGRectMake(textX, 17, CGRectGetWidth(self.bounds)-textX-12, 26);
    self.subtitleLabel.frame = CGRectMake(textX, 44, CGRectGetWidth(self.bounds)-textX-12, h-51);
}
- (void)pressDown { [UIView animateWithDuration:0.10 animations:^{ self.transform=CGAffineTransformMakeScale(0.97,0.97); }]; }
- (void)pressUp { [UIView animateWithDuration:0.14 animations:^{ self.transform=CGAffineTransformIdentity; }]; }
@end

@interface PAFavoritesReplacementView : UIView
@property(nonatomic,weak) UIViewController *hostController;
@property(nonatomic,strong) UILabel *sectionLabel;
@property(nonatomic,strong) PAFavoriteActionCard *heroCard;
@property(nonatomic,strong) PAFavoriteActionCard *familyCard;
@property(nonatomic,strong) PAFavoriteActionCard *workCard;
@property(nonatomic,strong) PAStudioShortcutsView *shortcuts;
@end

@implementation PAFavoritesReplacementView
- (instancetype)initWithHost:(UIViewController *)host {
    if ((self=[super initWithFrame:host.view.bounds])) {
        self.hostController=host;
        self.backgroundColor=PAColorHex(0x030712,1);
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _sectionLabel=[[UILabel alloc] init];
        _sectionLabel.text=@"YOUR FAVORITES";
        _sectionLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        _sectionLabel.textColor=PAColorHex(0x94A1BC,1);
        [self addSubview:_sectionLabel];
        _heroCard=[[PAFavoriteActionCard alloc] init];
        [_heroCard configureTitle:@"Add your first favorite" subtitle:@"Choose a contact for one-tap calling, messaging and FaceTime." icon:@"person.crop.circle.badge.plus" colors:@[PAColorHex(0xFF5B61,1),PAColorHex(0xFF7858,1)]];
        [_heroCard addTarget:self action:@selector(addFavorite) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_heroCard];
        _familyCard=[[PAFavoriteActionCard alloc] init];
        [_familyCard configureTitle:@"Family" subtitle:@"Message your group" icon:@"person.3.fill" colors:@[PAColorHex(0x7C4DFF,1),PAColorHex(0x5134BD,1)]];
        [_familyCard addTarget:self action:@selector(openMessages) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_familyCard];
        _workCard=[[PAFavoriteActionCard alloc] init];
        [_workCard configureTitle:@"Quick Dial" subtitle:@"Open Concept D keypad" icon:@"phone.fill" colors:@[PAColorHex(0x18C8B7,1),PAColorHex(0x087E80,1)]];
        [_workCard addTarget:self action:@selector(openKeypad) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_workCard];
        _shortcuts=[[PAStudioShortcutsView alloc] init];
        __weak typeof(self) weakSelf=self;
        _shortcuts.tapHandler=^(NSUInteger index){ [weakSelf shortcut:index]; };
        [self addSubview:_shortcuts];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=CGRectGetWidth(self.bounds), y=8;
    self.sectionLabel.frame=CGRectMake(20,y,w-40,22); y+=31;
    self.heroCard.frame=CGRectMake(18,y,w-36,132); y+=144;
    CGFloat gap=10, small=(w-36-gap)/2.0;
    self.familyCard.frame=CGRectMake(18,y,small,96);
    self.workCard.frame=CGRectMake(18+small+gap,y,small,96); y+=109;
    self.shortcuts.frame=CGRectMake(0,y,w,160);
}
- (void)addFavorite {
    UIBarButtonItem *item=self.hostController.navigationItem.rightBarButtonItem ?: self.hostController.navigationItem.rightBarButtonItems.lastObject;
    if (item.target && item.action) [UIApplication.sharedApplication sendAction:item.action to:item.target from:item forEvent:nil];
}
- (void)openMessages { NSURL *u=[NSURL URLWithString:@"sms:"]; if(u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }
- (void)openKeypad { self.hostController.tabBarController.selectedIndex=3; }
- (void)shortcut:(NSUInteger)index {
    if(index==0){ [self openMessages]; return; }
    if(index==1){ [self openKeypad]; return; }
    if(index==2){ self.hostController.tabBarController.selectedIndex=4; return; }
    [self addFavorite];
}
@end

void PARestoreFullSurfaceFixes(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;
    PAFavoritesReplacementView *favorites = objc_getAssociatedObject(controller.view, PAFavoritesOverlayKey);
    favorites.hidden = YES;
    PARestoreOriginalChildren(controller.view);
}

void PAApplyFullSurfaceFixes(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;
    UITabBarController *tab=controller.tabBarController;
    if(!tab || PATop(tab)!=controller) return;
    NSUInteger index=MIN(tab.selectedIndex,4);

    if(index==3 && PABool(@"hideStockKeypad",YES)) {
        UIView *keypad=nil;
        for(UIView *subview in controller.view.subviews) if([NSStringFromClass(subview.class) containsString:@"PAStudioKeypadView"]) { keypad=subview; break; }
        if(keypad){ PAHideOriginalChildren(controller.view,keypad); keypad.hidden=NO; keypad.userInteractionEnabled=YES; [controller.view bringSubviewToFront:keypad]; }
        return;
    }

    if(index==0 && PABool(@"replaceFavorites",YES)) {
        PAFavoritesReplacementView *favorites=objc_getAssociatedObject(controller.view,PAFavoritesOverlayKey);
        if(!favorites){ favorites=[[PAFavoritesReplacementView alloc] initWithHost:controller]; [controller.view addSubview:favorites]; objc_setAssociatedObject(controller.view,PAFavoritesOverlayKey,favorites,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        favorites.hidden=NO; favorites.frame=controller.view.bounds;
        PAHideOriginalChildren(controller.view,favorites);
        [controller.view bringSubviewToFront:favorites];
        return;
    }

    PARestoreFullSurfaceFixes(controller);
}

void PARefreshFullSurfaceForTabController(UITabBarController *tabController) {
    UIViewController *top=PATop(tabController);
    if(top) PAApplyFullSurfaceFixes(top);
}
