#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static NSString * const NADomain = @"com.nextsolution.unlockvibrate";
static NSInteger const NAPreviewTag = 150727;

static BOOL NAIsSwitcherController(id controller) {
    if (!controller) return NO;
    NSString *title = [controller title];
    return [title isEqualToString:@"App Switcher"];
}

static NSUserDefaults *NADefaults(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:NADomain];
    [d synchronize];
    return d;
}

static double NADouble(NSUserDefaults *d, NSString *key, double fallback) {
    id v = [d objectForKey:key];
    return v ? [v doubleValue] : fallback;
}
static NSInteger NAInteger(NSUserDefaults *d, NSString *key, NSInteger fallback) {
    id v = [d objectForKey:key];
    return v ? [v integerValue] : fallback;
}
static BOOL NABool(NSUserDefaults *d, NSString *key, BOOL fallback) {
    id v = [d objectForKey:key];
    return v ? [v boolValue] : fallback;
}

static UILabel *NALabel(CGRect frame, NSString *text, CGFloat size, UIFontWeight weight, UIColor *colour, NSTextAlignment alignment) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = colour;
    label.textAlignment = alignment;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    return label;
}

static UIView *NACard(CGRect frame, NSString *name, UIColor *colour, CGFloat radius, CGFloat opacity, BOOL hideIcons, BOOL hideLabels) {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = colour;
    card.alpha = opacity;
    card.layer.cornerRadius = radius;
    card.clipsToBounds = YES;

    UIView *toolbar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 24)];
    toolbar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.11];
    [card addSubview:toolbar];

    if (!hideIcons) {
        UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(8, 6, 12, 12)];
        icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.82];
        icon.layer.cornerRadius = 3;
        [toolbar addSubview:icon];
    }
    if (!hideLabels) {
        UILabel *label = NALabel(CGRectMake(5, frame.size.height - 26, frame.size.width - 10, 18), name, 9.5, UIFontWeightSemibold,
                                 [UIColor colorWithWhite:1 alpha:0.90], NSTextAlignmentCenter);
        [card addSubview:label];
    }
    return card;
}

static CGAffineTransform NATransformForStyle(NSInteger style, CGFloat signedDirection, CGFloat intensity, CGFloat perspective, CGFloat sideScale) {
    CGFloat angle = 0;
    CGFloat tx = signedDirection * 4;
    CGFloat ty = 0;
    switch (style) {
        case 1: angle = 0.16 * intensity * perspective; break;
        case 2: angle = 0.055 * intensity * perspective; break;
        case 3: angle = 0.34 * intensity * perspective; break;
        case 4: angle = 0.13 * intensity * perspective; ty = signedDirection * 5; break;
        case 5: sideScale = MAX(0.70, sideScale - 0.14 * intensity); angle = 0; break;
        case 6: angle = 0.48 * intensity * perspective; break;
        case 7: angle = 0.07 * intensity * perspective; ty = signedDirection * 16 * intensity; break;
        default: angle = 0; tx = 0; break;
    }
    CGAffineTransform t = CGAffineTransformMakeRotation(signedDirection * angle);
    t = CGAffineTransformScale(t, sideScale, sideScale);
    t = CGAffineTransformTranslate(t, tx, ty);
    return t;
}

static void NAUpdatePreview(id controller) {
    if (!NAIsSwitcherController(controller)) return;
    UITableView *table = nil;
    if ([controller respondsToSelector:@selector(table)]) table = [controller table];
    if (!table) return;

    NSUserDefaults *d = NADefaults();
    NSInteger style = NAInteger(d, @"LabSwitcherSwipeStyle", 0);
    CGFloat intensity = NADouble(d, @"LabSwitcherAnimationIntensity", 0.72);
    CGFloat perspective = NADouble(d, @"LabSwitcherPerspective", 0.78);
    CGFloat cardScale = NADouble(d, @"LabSwitcherCardScale", 1.0);
    CGFloat opacity = NADouble(d, @"LabSwitcherCardOpacity", 1.0);
    CGFloat radius = NADouble(d, @"LabSwitcherCornerRadius", 0.0);
    CGFloat vertical = NADouble(d, @"LabSwitcherVerticalOffset", 0.0) * 0.18;
    CGFloat spacing = NADouble(d, @"LabSwitcherHorizontalSpacing", 0.0) * 0.38;
    BOOL hideIcons = NABool(d, @"LabHideSwitcherAppIcons", NO);
    BOOL hideLabels = NABool(d, @"LabHideSwitcherAppLabels", NO);
    BOOL hideBackground = NABool(d, @"LabHideSwitcherBackground", NO);
    BOOL hideHome = NABool(d, @"LabHideSwitcherHomeCard", NO);

    CGFloat width = MAX(table.bounds.size.width, 320);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 258)];
    header.tag = NAPreviewTag;

    [header addSubview:NALabel(CGRectMake(18, 9, width - 36, 25), @"Live Switcher Preview", 17, UIFontWeightSemibold,
                               [UIColor systemBlueColor], NSTextAlignmentLeft)];
    [header addSubview:NALabel(CGRectMake(18, 34, width - 36, 18), @"Changes appear here immediately. Respring applies them to SpringBoard.", 11,
                               UIFontWeightRegular, [UIColor secondaryLabelColor], NSTextAlignmentLeft)];

    UIView *screen = [[UIView alloc] initWithFrame:CGRectMake(16, 59, width - 32, 184)];
    screen.backgroundColor = hideBackground ? [UIColor colorWithWhite:0.08 alpha:0.20] : [UIColor colorWithRed:0.035 green:0.045 blue:0.075 alpha:1];
    screen.layer.cornerRadius = 22;
    screen.clipsToBounds = YES;
    [header addSubview:screen];

    UILabel *badge = NALabel(CGRectMake(12, 9, 96, 20), @"PREVIEW ONLY", 9.5, UIFontWeightBold,
                             [UIColor colorWithRed:0.42 green:0.80 blue:1 alpha:1], NSTextAlignmentCenter);
    [screen addSubview:badge];

    CGFloat sw = screen.bounds.size.width;
    CGFloat cw = 102 * cardScale;
    CGFloat ch = 130 * cardScale;
    CGFloat y = 39 + vertical + (130 - ch) / 2.0;
    CGFloat centreX = (sw - cw) / 2.0;
    CGFloat sideInset = MAX(8, sw * 0.055 - spacing);
    CGFloat leftX = sideInset;
    CGFloat rightX = sw - cw - sideInset;
    CGFloat radiusShown = radius > 0.5 ? MIN(radius, 34) : 15;

    UIView *left = NACard(CGRectMake(leftX, y, cw, ch), hideHome ? @"APP A" : @"HOME", [UIColor colorWithRed:0.20 green:0.30 blue:0.58 alpha:1],
                          radiusShown, opacity * 0.76, hideIcons, hideLabels);
    UIView *right = NACard(CGRectMake(rightX, y, cw, ch), @"APP B", [UIColor colorWithRed:0.55 green:0.22 blue:0.38 alpha:1],
                           radiusShown, opacity * 0.76, hideIcons, hideLabels);
    left.transform = NATransformForStyle(style, -1, intensity, perspective, 0.90);
    right.transform = NATransformForStyle(style, 1, intensity, perspective, 0.90);
    [screen addSubview:left];
    [screen addSubview:right];

    UIView *active = NACard(CGRectMake(centreX, y - 4, cw, ch + 8), @"ACTIVE — STRAIGHT",
                            [UIColor colorWithRed:0.12 green:0.48 blue:0.72 alpha:1], radiusShown, opacity, hideIcons, hideLabels);
    active.layer.borderWidth = 1.5;
    active.layer.borderColor = [UIColor colorWithRed:0.45 green:0.82 blue:1 alpha:0.9].CGColor;
    [screen addSubview:active];

    table.tableHeaderView = header;
}

static void (*origPSViewDidAppear)(id, SEL, BOOL);
static void hookPSViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origPSViewDidAppear) origPSViewDidAppear(self, _cmd, animated);
    NAUpdatePreview(self);
}

static void (*origPSSetPreference)(id, SEL, id, id);
static void hookPSSetPreference(id self, SEL _cmd, id value, id specifier) {
    if (origPSSetPreference) origPSSetPreference(self, _cmd, value, specifier);
    dispatch_async(dispatch_get_main_queue(), ^{ NAUpdatePreview(self); });
}

__attribute__((constructor)) static void NextAuraInstallPreview(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"PSListController");
        if (!cls) return;
        if (class_getInstanceMethod(cls, @selector(viewDidAppear:)))
            MSHookMessageEx(cls, @selector(viewDidAppear:), (IMP)hookPSViewDidAppear, (IMP *)&origPSViewDidAppear);
        SEL setPref = NSSelectorFromString(@"setPreferenceValue:specifier:");
        if (class_getInstanceMethod(cls, setPref))
            MSHookMessageEx(cls, setPref, (IMP)hookPSSetPreference, (IMP *)&origPSSetPreference);
    }
}
