typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Method;
typedef void (*IMP)(void);
typedef unsigned char BOOL;
typedef long NSInteger;
typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;

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

static IMP gViewDidAppear = 0;
static IMP gSetPreferenceValue = 0;
static IMP gReloadSpecifiers = 0;

static id Msg0(id object, const char *selector) {
    return object ? ((id (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector)) : 0;
}
static id Msg1(id object, const char *selector, id argument) {
    return object ? ((id (*)(id, SEL, id))objc_msgSend)(object, sel_registerName(selector), argument) : 0;
}
static void Void0(id object, const char *selector) {
    if (object) ((void (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector));
}
static void Void1(id object, const char *selector, id argument) {
    if (object) ((void (*)(id, SEL, id))objc_msgSend)(object, sel_registerName(selector), argument);
}
static void VoidBool(id object, const char *selector, BOOL value) {
    if (object) ((void (*)(id, SEL, BOOL))objc_msgSend)(object, sel_registerName(selector), value);
}
static void VoidDouble(id object, const char *selector, CGFloat value) {
    if (object) ((void (*)(id, SEL, CGFloat))objc_msgSend)(object, sel_registerName(selector), value);
}
static void VoidInteger(id object, const char *selector, NSInteger value) {
    if (object) ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, sel_registerName(selector), value);
}
static void VoidTransform(id object, const char *selector, CGAffineTransform value) {
    if (object) ((void (*)(id, SEL, CGAffineTransform))objc_msgSend)(object, sel_registerName(selector), value);
}

static BOOL StringEqual(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *b && *a == *b) { a++; b++; }
    return *a == 0 && *b == 0;
}
static BOOL StringContains(const char *haystack, const char *needle) {
    if (!haystack || !needle || !*needle) return 0;
    for (const char *h = haystack; *h; h++) {
        const char *a = h, *b = needle;
        while (*a && *b && *a == *b) { a++; b++; }
        if (!*b) return 1;
    }
    return 0;
}

static id S(const char *text) {
    Class cls = objc_getClass("NSString");
    return ((id (*)(id, SEL, const char *))objc_msgSend)((id)cls, sel_registerName("stringWithUTF8String:"), text);
}
static id Color(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    Class cls = objc_getClass("UIColor");
    return ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)((id)cls, sel_registerName("colorWithRed:green:blue:alpha:"), r, g, b, a);
}
static id Font(CGFloat size, CGFloat weight) {
    Class cls = objc_getClass("UIFont");
    return ((id (*)(id, SEL, CGFloat, CGFloat))objc_msgSend)((id)cls, sel_registerName("systemFontOfSize:weight:"), size, weight);
}
static id NewView(const char *className, CGRect frame) {
    Class cls = objc_getClass(className);
    id object = Msg0((id)cls, "alloc");
    return ((id (*)(id, SEL, CGRect))objc_msgSend)(object, sel_registerName("initWithFrame:"), frame);
}
static CGRect Bounds(id object) {
    CGRect zero = {{0,0},{0,0}};
    return object ? ((CGRect (*)(id, SEL))objc_msgSend)(object, sel_registerName("bounds")) : zero;
}

static id Defaults(void) {
    Class cls = objc_getClass("NSUserDefaults");
    id object = Msg0((id)cls, "alloc");
    return Msg1(object, "initWithSuiteName:", S("com.nextsolution.unlockvibrate"));
}
static id PrefValue(id defaults, const char *key) { return Msg1(defaults, "objectForKey:", S(key)); }
static CGFloat DoublePref(id defaults, const char *key, CGFloat fallback) {
    id value = PrefValue(defaults, key);
    return value ? ((CGFloat (*)(id, SEL))objc_msgSend)(value, sel_registerName("doubleValue")) : fallback;
}
static NSInteger IntegerPref(id defaults, const char *key, NSInteger fallback) {
    id value = PrefValue(defaults, key);
    return value ? ((NSInteger (*)(id, SEL))objc_msgSend)(value, sel_registerName("integerValue")) : fallback;
}
static BOOL BoolPref(id defaults, const char *key, BOOL fallback) {
    id value = PrefValue(defaults, key);
    return value ? ((BOOL (*)(id, SEL))objc_msgSend)(value, sel_registerName("boolValue")) : fallback;
}

static void Round(id view, CGFloat radius) {
    id layer = Msg0(view, "layer");
    VoidDouble(layer, "setCornerRadius:", radius);
    VoidBool(view, "setClipsToBounds:", 1);
}
static id Label(CGRect frame, const char *text, CGFloat size, CGFloat weight, id color, NSInteger alignment) {
    id label = NewView("UILabel", frame);
    Void1(label, "setText:", S(text));
    Void1(label, "setTextColor:", color);
    Void1(label, "setFont:", Font(size, weight));
    VoidInteger(label, "setTextAlignment:", alignment);
    return label;
}
static id Card(CGRect frame, const char *title, id color, CGFloat radius, CGFloat opacity, CGAffineTransform transform, BOOL showLabel) {
    id card = NewView("UIView", frame);
    Void1(card, "setBackgroundColor:", color);
    VoidDouble(card, "setAlpha:", opacity);
    Round(card, radius);
    VoidTransform(card, "setTransform:", transform);
    id shine = NewView("UIView", (CGRect){{0,0},{frame.size.width,24}});
    Void1(shine, "setBackgroundColor:", Color(1,1,1,0.10));
    Void1(card, "addSubview:", shine);
    if (showLabel) {
        id label = Label((CGRect){{0,frame.size.height-25},{frame.size.width,18}}, title, 9.5, 0.45, Color(1,1,1,0.84), 1);
        Void1(card, "addSubview:", label);
    }
    return card;
}

static CGAffineTransform Transform(CGFloat angle, CGFloat scale, CGFloat tx, CGFloat ty) {
    CGFloat squared = angle * angle;
    CGFloat cosine = 1.0 - squared * 0.5;
    CGFloat sine = angle - angle * squared / 6.0;
    CGAffineTransform result = {cosine * scale, sine * scale, -sine * scale, cosine * scale, tx, ty};
    return result;
}

static BOOL IsSwitcherPage(id controller) {
    if (!controller) return 0;
    const char *className = class_getName(object_getClass(controller));
    if (!className || (!StringContains(className, "ListController") && !StringContains(className, "SubListController"))) return 0;
    id title = Msg0(controller, "title");
    const char *utf8 = title ? ((const char *(*)(id, SEL))objc_msgSend)(title, sel_registerName("UTF8String")) : 0;
    return utf8 && StringEqual(utf8, "App Switcher");
}

static void PersistImmediateValue(id value, id specifier) {
    if (!value || !specifier) return;
    id key = Msg1(specifier, "propertyForKey:", S("key"));
    if (!key) return;
    id defaults = Defaults();
    ((void (*)(id, SEL, id, id))objc_msgSend)(defaults, sel_registerName("setObject:forKey:"), value, key);
    Void0(defaults, "synchronize");
}

static void InstallPreview(id controller) {
    if (!IsSwitcherPage(controller)) return;
    id table = Msg0(controller, "table");
    id rootView = Msg0(controller, "view");
    if (!table || !rootView) return;
    CGRect rootBounds = Bounds(rootView);
    CGFloat width = rootBounds.size.width > 280 ? rootBounds.size.width : 390;
    id defaults = Defaults();

    NSInteger style = IntegerPref(defaults, "LabSwitcherSwipeStyle", 0);
    CGFloat intensity = DoublePref(defaults, "LabSwitcherAnimationIntensity", 0.72);
    CGFloat perspective = DoublePref(defaults, "LabSwitcherPerspective", 0.78);
    CGFloat cardScale = DoublePref(defaults, "LabSwitcherCardScale", 1.0);
    CGFloat opacity = DoublePref(defaults, "LabSwitcherCardOpacity", 1.0);
    CGFloat radius = DoublePref(defaults, "LabSwitcherCornerRadius", 0.0);
    CGFloat vertical = DoublePref(defaults, "LabSwitcherVerticalOffset", 0.0);
    CGFloat spacing = DoublePref(defaults, "LabSwitcherHorizontalSpacing", 0.0);
    BOOL hideLabels = BoolPref(defaults, "LabHideSwitcherAppLabels", 0);
    BOOL hideBackground = BoolPref(defaults, "LabHideSwitcherBackground", 0);
    if (radius < 1.0) radius = 18.0;

    id header = NewView("UIView", (CGRect){{0,0},{width,238}});
    id heading = Label((CGRect){{18,10},{width-36,24}}, "Live App Switcher Preview", 17, 0.68, Color(0.08,0.50,1.0,1), 0);
    id note = Label((CGRect){{18,34},{width-36,18}}, "Preview updates now · Respring applies changes to the real switcher", 10.5, 0.38, Color(0.52,0.55,0.62,1), 0);
    Void1(header, "addSubview:", heading);
    Void1(header, "addSubview:", note);

    id stage = NewView("UIView", (CGRect){{14,58},{width-28,164}});
    Void1(stage, "setBackgroundColor:", hideBackground ? Color(0,0,0,0.03) : Color(0.025,0.035,0.065,1));
    Round(stage, 22.0);
    Void1(header, "addSubview:", stage);

    id activeBadge = Label((CGRect){{0,9},{width-28,17}}, "OPENING CARD STAYS STRAIGHT", 9.5, 0.72, Color(0.42,0.82,1.0,1), 1);
    Void1(stage, "addSubview:", activeBadge);

    CGFloat stageWidth = width - 28;
    CGFloat baseWidth = 96.0 * cardScale;
    CGFloat baseHeight = 120.0 * cardScale;
    CGFloat y = 32.0 + vertical * 0.16 + (120.0 - baseHeight) * 0.5;
    CGFloat centreX = (stageWidth - baseWidth) * 0.5;
    CGFloat sideInset = 22.0 - spacing * 0.22;
    CGFloat leftX = sideInset;
    CGFloat rightX = stageWidth - baseWidth - sideInset;
    CGFloat angle = 0.0;
    CGFloat sideScale = 0.90;
    CGFloat waveY = 0.0;
    switch (style) {
        case 1: angle = 0.17 * intensity * perspective; sideScale = 0.90; break;
        case 2: angle = 0.07 * intensity * perspective; sideScale = 0.84; break;
        case 3: angle = 0.34 * intensity * perspective; sideScale = 0.91; break;
        case 4: angle = 0.14 * intensity * perspective; sideScale = 0.83; waveY = 7.0; break;
        case 5: angle = 0.0; sideScale = 0.73 + (1.0-intensity)*0.13; break;
        case 6: angle = 0.48 * intensity * perspective; sideScale = 0.87; break;
        case 7: angle = 0.08 * intensity * perspective; sideScale = 0.89; waveY = 14.0*intensity; break;
        default: angle = 0.0; sideScale = 0.92; break;
    }

    id left = Card((CGRect){{leftX,y+waveY},{baseWidth,baseHeight}}, "APP A", Color(0.20,0.28,0.58,1), radius, opacity*0.72, Transform(-angle,sideScale,-3.0,-waveY*0.4), !hideLabels);
    id right = Card((CGRect){{rightX,y-waveY},{baseWidth,baseHeight}}, "APP B", Color(0.58,0.20,0.38,1), radius, opacity*0.72, Transform(angle,sideScale,3.0,waveY*0.4), !hideLabels);
    id active = Card((CGRect){{centreX,y-4},{baseWidth,baseHeight+8}}, "ACTIVE", Color(0.08,0.46,0.74,1), radius, opacity, Transform(0,1,0,0), !hideLabels);
    Void1(stage, "addSubview:", left);
    Void1(stage, "addSubview:", right);
    Void1(stage, "addSubview:", active);
    Void1(table, "setTableHeaderView:", header);
}

static void HookMethod(Class cls, const char *name, IMP replacement, IMP *original) {
    if (!cls || !name || !replacement || !original) return;
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP previous = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (class_addMethod(cls, selector, replacement, types)) *original = previous;
    else *original = method_setImplementation(method, replacement);
}

static void PreviewViewDidAppear(id self, SEL cmd, BOOL animated) {
    if (gViewDidAppear) ((void (*)(id, SEL, BOOL))gViewDidAppear)(self, cmd, animated);
    InstallPreview(self);
}
static void PreviewSetPreferenceValue(id self, SEL cmd, id value, id specifier) {
    if (gSetPreferenceValue) ((void (*)(id, SEL, id, id))gSetPreferenceValue)(self, cmd, value, specifier);
    PersistImmediateValue(value, specifier);
    InstallPreview(self);
}
static id PreviewReloadSpecifiers(id self, SEL cmd) {
    id result = 0;
    if (gReloadSpecifiers) result = ((id (*)(id, SEL))gReloadSpecifiers)(self, cmd);
    InstallPreview(self);
    return result;
}

__attribute__((constructor))
static void InstallNextAuraSwitcherPreview(void) {
    Class listController = objc_getClass("PSListController");
    if (!listController) listController = objc_getClass("UIViewController");
    HookMethod(listController, "viewDidAppear:", (IMP)PreviewViewDidAppear, &gViewDidAppear);
    Class psList = objc_getClass("PSListController");
    HookMethod(psList, "setPreferenceValue:specifier:", (IMP)PreviewSetPreferenceValue, &gSetPreferenceValue);
    HookMethod(psList, "reloadSpecifiers", (IMP)PreviewReloadSpecifiers, &gReloadSpecifiers);
}
