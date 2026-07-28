#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static BOOL NAKeepInitialSwitcherStraight = NO;
static __weak UIView *NAActiveSwitcherView = nil;
static char NAPanObserverKey;

@interface NANextAuraSwitcherGestureObserver : NSObject
+ (instancetype)sharedObserver;
- (void)nextAuraHandleSwitcherPan:(UIPanGestureRecognizer *)pan;
@end

@implementation NANextAuraSwitcherGestureObserver
+ (instancetype)sharedObserver {
    static NANextAuraSwitcherGestureObserver *observer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ observer = [NANextAuraSwitcherGestureObserver new]; });
    return observer;
}

- (void)nextAuraHandleSwitcherPan:(UIPanGestureRecognizer *)pan {
    if (!NAKeepInitialSwitcherStraight) return;
    UIGestureRecognizerState state = pan.state;
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) return;

    UIView *reference = pan.view ?: NAActiveSwitcherView;
    CGPoint translation = [pan translationInView:reference];
    CGPoint velocity = [pan velocityInView:reference];
    CGFloat horizontal = fabs(translation.x);
    CGFloat vertical = fabs(translation.y);
    CGFloat horizontalVelocity = fabs(velocity.x);
    CGFloat verticalVelocity = fabs(velocity.y);

    BOOL deliberateTranslation = horizontal >= 7.0 && horizontal > (vertical * 1.12);
    BOOL deliberateVelocity = horizontalVelocity >= 140.0 && horizontalVelocity > (verticalVelocity * 1.12);
    if (deliberateTranslation || deliberateVelocity) NAKeepInitialSwitcherStraight = NO;
}
@end

static void NAObservePansRecursively(UIView *view) {
    if (!view) return;
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if (![gesture isKindOfClass:[UIPanGestureRecognizer class]]) continue;
        if (objc_getAssociatedObject(gesture, &NAPanObserverKey)) continue;
        [gesture addTarget:[NANextAuraSwitcherGestureObserver sharedObserver]
                    action:@selector(nextAuraHandleSwitcherPan:)];
        objc_setAssociatedObject(gesture, &NAPanObserverKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *subview in view.subviews) NAObservePansRecursively(subview);
}

static void NAInstallPanObservers(id controller) {
    if (![controller respondsToSelector:@selector(view)]) return;
    UIView *view = [controller view];
    NAActiveSwitcherView = view;
    NAObservePansRecursively(view);

    static const double delays[] = {0.08, 0.22, 0.50};
    for (NSUInteger index = 0; index < (sizeof(delays) / sizeof(delays[0])); index++) {
        double delay = delays[index];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (NAKeepInitialSwitcherStraight) NAObservePansRecursively(NAActiveSwitcherView);
        });
    }
}

static void NABeginStraightOpening(id controller) {
    NAKeepInitialSwitcherStraight = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ NAInstallPanObservers(controller); });
}

static void NAEndSwitcherSession(void) {
    NAKeepInitialSwitcherStraight = NO;
    NAActiveSwitcherView = nil;
}

static void (*origFluidWillAppear)(id, SEL, BOOL);
static void hookFluidWillAppear(id self, SEL _cmd, BOOL animated) {
    NABeginStraightOpening(self);
    if (origFluidWillAppear) origFluidWillAppear(self, _cmd, animated);
    NAInstallPanObservers(self);
}

static void (*origMainWillAppear)(id, SEL, BOOL);
static void hookMainWillAppear(id self, SEL _cmd, BOOL animated) {
    NABeginStraightOpening(self);
    if (origMainWillAppear) origMainWillAppear(self, _cmd, animated);
    NAInstallPanObservers(self);
}

static void (*origFluidDidAppear)(id, SEL, BOOL);
static void hookFluidDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origFluidDidAppear) origFluidDidAppear(self, _cmd, animated);
    NAInstallPanObservers(self);
}

static void (*origMainDidAppear)(id, SEL, BOOL);
static void hookMainDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origMainDidAppear) origMainDidAppear(self, _cmd, animated);
    NAInstallPanObservers(self);
}

static void (*origFluidWillDisappear)(id, SEL, BOOL);
static void hookFluidWillDisappear(id self, SEL _cmd, BOOL animated) {
    NAEndSwitcherSession();
    if (origFluidWillDisappear) origFluidWillDisappear(self, _cmd, animated);
}

static void (*origMainWillDisappear)(id, SEL, BOOL);
static void hookMainWillDisappear(id self, SEL _cmd, BOOL animated) {
    NAEndSwitcherSession();
    if (origMainWillDisappear) origMainWillDisappear(self, _cmd, animated);
}

static inline void NAClearOnlyNextAura3DEffect(UIView *view) {
    if (!view || !NAKeepInitialSwitcherStraight) return;
    view.layer.sublayerTransform = CATransform3DIdentity;
}

static void (*origContainerLayout)(id, SEL);
static void hookContainerLayout(id self, SEL _cmd) {
    if (origContainerLayout) origContainerLayout(self, _cmd);
    NAClearOnlyNextAura3DEffect((UIView *)self);
}

static void (*origContainerViewLayout)(id, SEL);
static void hookContainerViewLayout(id self, SEL _cmd) {
    if (origContainerViewLayout) origContainerViewLayout(self, _cmd);
    NAClearOnlyNextAura3DEffect((UIView *)self);
}

static void NAHookController(NSString *name,
                             IMP willAppear, IMP *originalWillAppear,
                             IMP didAppear, IMP *originalDidAppear,
                             IMP willDisappear, IMP *originalWillDisappear) {
    Class cls = NSClassFromString(name);
    if (!cls) return;
    if (class_getInstanceMethod(cls, @selector(viewWillAppear:)))
        MSHookMessageEx(cls, @selector(viewWillAppear:), willAppear, originalWillAppear);
    if (class_getInstanceMethod(cls, @selector(viewDidAppear:)))
        MSHookMessageEx(cls, @selector(viewDidAppear:), didAppear, originalDidAppear);
    if (class_getInstanceMethod(cls, @selector(viewWillDisappear:)))
        MSHookMessageEx(cls, @selector(viewWillDisappear:), willDisappear, originalWillDisappear);
}

__attribute__((constructor)) static void NextAuraInstallOpeningGuardV3(void) {
    @autoreleasepool {
        NAHookController(@"SBFluidSwitcherViewController",
                         (IMP)hookFluidWillAppear, (IMP *)&origFluidWillAppear,
                         (IMP)hookFluidDidAppear, (IMP *)&origFluidDidAppear,
                         (IMP)hookFluidWillDisappear, (IMP *)&origFluidWillDisappear);
        NAHookController(@"SBMainSwitcherViewController",
                         (IMP)hookMainWillAppear, (IMP *)&origMainWillAppear,
                         (IMP)hookMainDidAppear, (IMP *)&origMainDidAppear,
                         (IMP)hookMainWillDisappear, (IMP *)&origMainWillDisappear);

        Class container = NSClassFromString(@"SBFluidSwitcherItemContainer");
        if (container && class_getInstanceMethod(container, @selector(layoutSubviews)))
            MSHookMessageEx(container, @selector(layoutSubviews), (IMP)hookContainerLayout, (IMP *)&origContainerLayout);

        Class containerView = NSClassFromString(@"SBFluidSwitcherItemContainerView");
        if (containerView && class_getInstanceMethod(containerView, @selector(layoutSubviews)))
            MSHookMessageEx(containerView, @selector(layoutSubviews), (IMP)hookContainerViewLayout, (IMP *)&origContainerViewLayout);
    }
}
