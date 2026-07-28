#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static BOOL NAOpeningSwitcher = NO;
static CFTimeInterval NAGuardUntil = 0;

static void NABeginOpeningGuard(void) {
    NAOpeningSwitcher = YES;
    NAGuardUntil = CACurrentMediaTime() + 1.10;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (CACurrentMediaTime() >= NAGuardUntil) NAOpeningSwitcher = NO;
    });
}

static void (*origFluidWillAppear)(id, SEL, BOOL);
static void hookFluidWillAppear(id self, SEL _cmd, BOOL animated) {
    NABeginOpeningGuard();
    if (origFluidWillAppear) origFluidWillAppear(self, _cmd, animated);
}

static void (*origMainWillAppear)(id, SEL, BOOL);
static void hookMainWillAppear(id self, SEL _cmd, BOOL animated) {
    NABeginOpeningGuard();
    if (origMainWillAppear) origMainWillAppear(self, _cmd, animated);
}

static void (*origFluidDidAppear)(id, SEL, BOOL);
static void hookFluidDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origFluidDidAppear) origFluidDidAppear(self, _cmd, animated);
    NAGuardUntil = MAX(NAGuardUntil, CACurrentMediaTime() + 0.22);
}

static void (*origMainDidAppear)(id, SEL, BOOL);
static void hookMainDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origMainDidAppear) origMainDidAppear(self, _cmd, animated);
    NAGuardUntil = MAX(NAGuardUntil, CACurrentMediaTime() + 0.22);
}

static inline BOOL NAGuardActive(void) {
    return NAOpeningSwitcher && CACurrentMediaTime() < NAGuardUntil;
}

static void NAClearOnlyNextAura3DEffect(UIView *view) {
    if (!view) return;
    // SafeSuite writes the swipe style to sublayerTransform. Resetting only
    // this property preserves Apple's normal app-to-switcher shrink animation.
    view.layer.sublayerTransform = CATransform3DIdentity;
}

static void (*origContainerLayout)(id, SEL);
static void hookContainerLayout(id self, SEL _cmd) {
    if (origContainerLayout) origContainerLayout(self, _cmd);
    if (NAGuardActive()) NAClearOnlyNextAura3DEffect((UIView *)self);
}

static void (*origContainerViewLayout)(id, SEL);
static void hookContainerViewLayout(id self, SEL _cmd) {
    if (origContainerViewLayout) origContainerViewLayout(self, _cmd);
    if (NAGuardActive()) NAClearOnlyNextAura3DEffect((UIView *)self);
}

static void NAHookController(NSString *name, IMP willIMP, IMP *willOrig, IMP didIMP, IMP *didOrig) {
    Class cls = NSClassFromString(name);
    if (!cls) return;
    if (class_getInstanceMethod(cls, @selector(viewWillAppear:)))
        MSHookMessageEx(cls, @selector(viewWillAppear:), willIMP, willOrig);
    if (class_getInstanceMethod(cls, @selector(viewDidAppear:)))
        MSHookMessageEx(cls, @selector(viewDidAppear:), didIMP, didOrig);
}

__attribute__((constructor)) static void NextAuraInstallOpeningGuard(void) {
    @autoreleasepool {
        NAHookController(@"SBFluidSwitcherViewController", (IMP)hookFluidWillAppear, (IMP *)&origFluidWillAppear,
                         (IMP)hookFluidDidAppear, (IMP *)&origFluidDidAppear);
        NAHookController(@"SBMainSwitcherViewController", (IMP)hookMainWillAppear, (IMP *)&origMainWillAppear,
                         (IMP)hookMainDidAppear, (IMP *)&origMainDidAppear);

        Class container = NSClassFromString(@"SBFluidSwitcherItemContainer");
        if (container && class_getInstanceMethod(container, @selector(layoutSubviews)))
            MSHookMessageEx(container, @selector(layoutSubviews), (IMP)hookContainerLayout, (IMP *)&origContainerLayout);

        Class containerView = NSClassFromString(@"SBFluidSwitcherItemContainerView");
        if (containerView && class_getInstanceMethod(containerView, @selector(layoutSubviews)))
            MSHookMessageEx(containerView, @selector(layoutSubviews), (IMP)hookContainerViewLayout, (IMP *)&origContainerViewLayout);
    }
}
