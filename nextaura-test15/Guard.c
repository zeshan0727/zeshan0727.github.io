typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Method;
typedef void (*IMP)(void);
typedef unsigned char BOOL;
typedef unsigned long NSUInteger;
typedef long NSInteger;
typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
typedef struct {
    CGFloat m11, m12, m13, m14;
    CGFloat m21, m22, m23, m24;
    CGFloat m31, m32, m33, m34;
    CGFloat m41, m42, m43, m44;
} CATransform3D;
typedef struct {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
} Dl_info;

extern Class objc_getClass(const char *name);
extern Class object_getClass(id object);
extern const char *class_getName(Class cls);
extern SEL sel_registerName(const char *name);
extern Method class_getInstanceMethod(Class cls, SEL name);
extern IMP method_getImplementation(Method method);
extern const char *method_getTypeEncoding(Method method);
extern BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
extern IMP method_setImplementation(Method method, IMP imp);
extern void *objc_msgSend(id self, SEL op, ...);
extern int dladdr(const void *addr, Dl_info *info);

static BOOL gSwitcherSession = 0;
static BOOL gOpeningGuard = 0;
static BOOL gReadyForHorizontalSwipe = 0;
static BOOL gReleasedForBrowsing = 0;
static BOOL gEndingSession = 0;
static id gSwitcherController = 0;

static IMP gVCWillAppear = 0;
static IMP gVCDidAppear = 0;
static IMP gVCWillDisappear = 0;
static IMP gVCDidDisappear = 0;
static IMP gPanTranslation = 0;
static IMP gPanVelocity = 0;
static IMP gScrollOffset = 0;
static IMP gScrollOffsetAnimated = 0;
static IMP gViewTransform = 0;
static IMP gViewAlpha = 0;
static IMP gLayerTransform = 0;
static IMP gLayerSublayerTransform = 0;
static IMP gLayerOpacity = 0;
static IMP gLayerCornerRadius = 0;

static id Msg0(id object, const char *selector) {
    return object ? ((id (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector)) : 0;
}
static void Void0(id object, const char *selector) {
    if (object) ((void (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector));
}

static BOOL StringContains(const char *haystack, const char *needle) {
    if (!haystack || !needle || !*needle) return 0;
    for (const char *h = haystack; *h; h++) {
        const char *a = h;
        const char *b = needle;
        while (*a && *b && *a == *b) { a++; b++; }
        if (!*b) return 1;
    }
    return 0;
}

static CGFloat AbsValue(CGFloat value) { return value < 0 ? -value : value; }

static const char *ObjectClassName(id object) {
    Class cls = object ? object_getClass(object) : 0;
    return cls ? class_getName(cls) : 0;
}

static BOOL IsSwitcherNamedObject(id object) {
    const char *name = ObjectClassName(object);
    if (!name) return 0;
    return StringContains(name, "Switcher") ||
           StringContains(name, "AppLayout") ||
           StringContains(name, "SnapshotView") ||
           StringContains(name, "Fluid") ||
           StringContains(name, "Deck");
}

static BOOL IsSwitcherView(id view) {
    id current = view;
    for (int depth = 0; current && depth < 12; depth++) {
        if (IsSwitcherNamedObject(current)) return 1;
        current = Msg0(current, "superview");
    }
    return 0;
}

static BOOL IsSwitcherLayer(id layer) {
    id current = layer;
    for (int depth = 0; current && depth < 12; depth++) {
        id delegate = Msg0(current, "delegate");
        if (delegate && IsSwitcherView(delegate)) return 1;
        current = Msg0(current, "superlayer");
    }
    return 0;
}

static BOOL IsSwitcherController(id controller) {
    const char *name = ObjectClassName(controller);
    return name && StringContains(name, "Switcher") && StringContains(name, "Controller");
}

static BOOL AddressIsSafeSuite(void *caller) {
    Dl_info info = {0};
    if (!caller || !dladdr(caller, &info) || !info.dli_fname) return 0;
    return StringContains(info.dli_fname, "SafeSuite.dylib");
}

static void BeginSwitcherSession(id controller) {
    gSwitcherSession = 1;
    gOpeningGuard = 1;
    gReadyForHorizontalSwipe = 0;
    gReleasedForBrowsing = 0;
    gEndingSession = 0;
    gSwitcherController = controller;
}

static void EnableHorizontalBrowsing(void) {
    if (!gSwitcherSession || !gOpeningGuard || gReleasedForBrowsing) return;
    gReleasedForBrowsing = 1;
    gOpeningGuard = 0;
    id view = Msg0(gSwitcherController, "view");
    Void0(view, "setNeedsLayout");
}

static void EndSwitcherSession(void) {
    gEndingSession = 1;
    gOpeningGuard = 0;
    gReadyForHorizontalSwipe = 0;
    gReleasedForBrowsing = 0;
    gSwitcherSession = 0;
    gSwitcherController = 0;
}

static BOOL IsHorizontalIntent(CGPoint translation, CGPoint velocity) {
    CGFloat tx = AbsValue(translation.x), ty = AbsValue(translation.y);
    CGFloat vx = AbsValue(velocity.x), vy = AbsValue(velocity.y);
    BOOL translationIntent = tx > 18.0 && tx > ty * 1.12;
    BOOL velocityIntent = vx > 240.0 && vx > vy * 1.18;
    return translationIntent || velocityIntent;
}

static void InspectPan(id recognizer, CGPoint translation, CGPoint velocity) {
    if (!gSwitcherSession || !gOpeningGuard || !gReadyForHorizontalSwipe || gReleasedForBrowsing) return;
    id view = Msg0(recognizer, "view");
    if (!view || !IsSwitcherView(view)) return;
    if (IsHorizontalIntent(translation, velocity)) EnableHorizontalBrowsing();
}

static void HookMethod(Class cls, const char *name, IMP replacement, IMP *original) {
    if (!cls || !name || !replacement || !original) return;
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP previous = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (class_addMethod(cls, selector, replacement, types)) {
        *original = previous;
    } else {
        *original = method_setImplementation(method, replacement);
    }
}

static void GuardVCWillAppear(id self, SEL cmd, BOOL animated) {
    if (IsSwitcherController(self)) BeginSwitcherSession(self);
    if (gVCWillAppear) ((void (*)(id, SEL, BOOL))gVCWillAppear)(self, cmd, animated);
}
static void GuardVCDidAppear(id self, SEL cmd, BOOL animated) {
    if (gVCDidAppear) ((void (*)(id, SEL, BOOL))gVCDidAppear)(self, cmd, animated);
    if (IsSwitcherController(self)) {
        if (!gSwitcherSession) BeginSwitcherSession(self);
        gReadyForHorizontalSwipe = 1;
        gEndingSession = 0;
    }
}
static void GuardVCWillDisappear(id self, SEL cmd, BOOL animated) {
    if (IsSwitcherController(self)) EndSwitcherSession();
    if (gVCWillDisappear) ((void (*)(id, SEL, BOOL))gVCWillDisappear)(self, cmd, animated);
}
static void GuardVCDidDisappear(id self, SEL cmd, BOOL animated) {
    if (gVCDidDisappear) ((void (*)(id, SEL, BOOL))gVCDidDisappear)(self, cmd, animated);
    if (IsSwitcherController(self)) {
        EndSwitcherSession();
        gEndingSession = 0;
    }
}

static CGPoint GuardPanTranslation(id self, SEL cmd, id view) {
    CGPoint result = {0, 0};
    if (gPanTranslation) result = ((CGPoint (*)(id, SEL, id))gPanTranslation)(self, cmd, view);
    CGPoint velocity = {0, 0};
    if (gPanVelocity) velocity = ((CGPoint (*)(id, SEL, id))gPanVelocity)(self, sel_registerName("velocityInView:"), view);
    InspectPan(self, result, velocity);
    return result;
}
static CGPoint GuardPanVelocity(id self, SEL cmd, id view) {
    CGPoint result = {0, 0};
    if (gPanVelocity) result = ((CGPoint (*)(id, SEL, id))gPanVelocity)(self, cmd, view);
    CGPoint translation = {0, 0};
    if (gPanTranslation) translation = ((CGPoint (*)(id, SEL, id))gPanTranslation)(self, sel_registerName("translationInView:"), view);
    InspectPan(self, translation, result);
    return result;
}

static void GuardSetContentOffset(id self, SEL cmd, CGPoint offset) {
    if (gSwitcherSession && gOpeningGuard && gReadyForHorizontalSwipe) {
        id pan = Msg0(self, "panGestureRecognizer");
        if (pan && IsSwitcherView(self)) {
            CGPoint translation = ((CGPoint (*)(id, SEL, id))objc_msgSend)(pan, sel_registerName("translationInView:"), self);
            CGPoint velocity = ((CGPoint (*)(id, SEL, id))objc_msgSend)(pan, sel_registerName("velocityInView:"), self);
            if (IsHorizontalIntent(translation, velocity)) EnableHorizontalBrowsing();
        }
    }
    if (gScrollOffset) ((void (*)(id, SEL, CGPoint))gScrollOffset)(self, cmd, offset);
}
static void GuardSetContentOffsetAnimated(id self, SEL cmd, CGPoint offset, BOOL animated) {
    if (gSwitcherSession && gOpeningGuard && gReadyForHorizontalSwipe && IsSwitcherView(self)) {
        id pan = Msg0(self, "panGestureRecognizer");
        if (pan) {
            CGPoint translation = ((CGPoint (*)(id, SEL, id))objc_msgSend)(pan, sel_registerName("translationInView:"), self);
            CGPoint velocity = ((CGPoint (*)(id, SEL, id))objc_msgSend)(pan, sel_registerName("velocityInView:"), self);
            if (IsHorizontalIntent(translation, velocity)) EnableHorizontalBrowsing();
        }
    }
    if (gScrollOffsetAnimated) ((void (*)(id, SEL, CGPoint, BOOL))gScrollOffsetAnimated)(self, cmd, offset, animated);
}

static BOOL ShouldSuppressSafeSuiteForView(id view, void *caller) {
    return gSwitcherSession && gOpeningGuard && !gReleasedForBrowsing &&
           !gEndingSession && IsSwitcherView(view) && AddressIsSafeSuite(caller);
}
static BOOL ShouldSuppressSafeSuiteForLayer(id layer, void *caller) {
    return gSwitcherSession && gOpeningGuard && !gReleasedForBrowsing &&
           !gEndingSession && IsSwitcherLayer(layer) && AddressIsSafeSuite(caller);
}

static void GuardViewSetTransform(id self, SEL cmd, CGAffineTransform transform) {
    void *caller = __builtin_return_address(0);
    if (ShouldSuppressSafeSuiteForView(self, caller)) return;
    if (gViewTransform) ((void (*)(id, SEL, CGAffineTransform))gViewTransform)(self, cmd, transform);
}
static void GuardViewSetAlpha(id self, SEL cmd, CGFloat alpha) {
    void *caller = __builtin_return_address(0);
    if (ShouldSuppressSafeSuiteForView(self, caller)) return;
    if (gViewAlpha) ((void (*)(id, SEL, CGFloat))gViewAlpha)(self, cmd, alpha);
}
static void GuardLayerSetTransform(id self, SEL cmd, CATransform3D transform) {
    void *caller = __builtin_return_address(0);
    if (ShouldSuppressSafeSuiteForLayer(self, caller)) return;
    if (gLayerTransform) ((void (*)(id, SEL, CATransform3D))gLayerTransform)(self, cmd, transform);
}
static void GuardLayerSetSublayerTransform(id self, SEL cmd, CATransform3D transform) {
    void *caller = __builtin_return_address(0);
    if (ShouldSuppressSafeSuiteForLayer(self, caller)) return;
    if (gLayerSublayerTransform) ((void (*)(id, SEL, CATransform3D))gLayerSublayerTransform)(self, cmd, transform);
}
static void GuardLayerSetOpacity(id self, SEL cmd, float opacity) {
    void *caller = __builtin_return_address(0);
    if (ShouldSuppressSafeSuiteForLayer(self, caller)) return;
    if (gLayerOpacity) ((void (*)(id, SEL, float))gLayerOpacity)(self, cmd, opacity);
}
static void GuardLayerSetCornerRadius(id self, SEL cmd, CGFloat radius) {
    void *caller = __builtin_return_address(0);
    if (ShouldSuppressSafeSuiteForLayer(self, caller)) return;
    if (gLayerCornerRadius) ((void (*)(id, SEL, CGFloat))gLayerCornerRadius)(self, cmd, radius);
}

__attribute__((constructor))
static void InstallNextAuraSwitcherOpeningGuard(void) {
    HookMethod(objc_getClass("UIViewController"), "viewWillAppear:", (IMP)GuardVCWillAppear, &gVCWillAppear);
    HookMethod(objc_getClass("UIViewController"), "viewDidAppear:", (IMP)GuardVCDidAppear, &gVCDidAppear);
    HookMethod(objc_getClass("UIViewController"), "viewWillDisappear:", (IMP)GuardVCWillDisappear, &gVCWillDisappear);
    HookMethod(objc_getClass("UIViewController"), "viewDidDisappear:", (IMP)GuardVCDidDisappear, &gVCDidDisappear);
    HookMethod(objc_getClass("UIPanGestureRecognizer"), "translationInView:", (IMP)GuardPanTranslation, &gPanTranslation);
    HookMethod(objc_getClass("UIPanGestureRecognizer"), "velocityInView:", (IMP)GuardPanVelocity, &gPanVelocity);
    HookMethod(objc_getClass("UIScrollView"), "setContentOffset:", (IMP)GuardSetContentOffset, &gScrollOffset);
    HookMethod(objc_getClass("UIScrollView"), "setContentOffset:animated:", (IMP)GuardSetContentOffsetAnimated, &gScrollOffsetAnimated);
    HookMethod(objc_getClass("UIView"), "setTransform:", (IMP)GuardViewSetTransform, &gViewTransform);
    HookMethod(objc_getClass("UIView"), "setAlpha:", (IMP)GuardViewSetAlpha, &gViewAlpha);
    HookMethod(objc_getClass("CALayer"), "setTransform:", (IMP)GuardLayerSetTransform, &gLayerTransform);
    HookMethod(objc_getClass("CALayer"), "setSublayerTransform:", (IMP)GuardLayerSetSublayerTransform, &gLayerSublayerTransform);
    HookMethod(objc_getClass("CALayer"), "setOpacity:", (IMP)GuardLayerSetOpacity, &gLayerOpacity);
    HookMethod(objc_getClass("CALayer"), "setCornerRadius:", (IMP)GuardLayerSetCornerRadius, &gLayerCornerRadius);
}
