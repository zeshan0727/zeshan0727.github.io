#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static BOOL NASwitcherVisible = NO;
static CGFloat NAMotionBlend = 0.0;
static CADisplayLink *NAFrameLink = nil;
static id NAFrameTarget = nil;
static __weak UIView *NASwitcherRootView = nil;
static NSInteger NARegistrationFrames = 0;

static NSHashTable<UIPanGestureRecognizer *> *NAPans = nil;
static NSMapTable<CALayer *, NSValue *> *NATargetTransforms = nil;
static NSHashTable<UIView *> *NAFixedHeaders = nil;

static Class NAContainerClass = Nil;
static Class NAContainerViewClass = Nil;
static Class NASnapshotClass = Nil;
static Class NAAppLayoutClass = Nil;

static void (*origLayerSetSublayerTransform)(CALayer *, SEL, CATransform3D);

static BOOL NAIsSwitcherCardDelegate(id delegate) {
    if (!delegate) return NO;
    return (NAContainerClass && [delegate isKindOfClass:NAContainerClass]) ||
           (NAContainerViewClass && [delegate isKindOfClass:NAContainerViewClass]) ||
           (NASnapshotClass && [delegate isKindOfClass:NASnapshotClass]) ||
           (NAAppLayoutClass && [delegate isKindOfClass:NAAppLayoutClass]);
}

static BOOL NAIsSwitcherCardLayer(CALayer *layer) {
    return NASwitcherVisible && layer && NAIsSwitcherCardDelegate(layer.delegate);
}

static CATransform3D NABlendTransform(CATransform3D target, CGFloat amount) {
    amount = MAX(0.0, MIN(1.0, amount));
    CATransform3D identity = CATransform3DIdentity;
    CATransform3D result;
#define NA_LERP(field) result.field = identity.field + (target.field - identity.field) * amount
    NA_LERP(m11); NA_LERP(m12); NA_LERP(m13); NA_LERP(m14);
    NA_LERP(m21); NA_LERP(m22); NA_LERP(m23); NA_LERP(m24);
    NA_LERP(m31); NA_LERP(m32); NA_LERP(m33); NA_LERP(m34);
    NA_LERP(m41); NA_LERP(m42); NA_LERP(m43); NA_LERP(m44);
#undef NA_LERP
    return result;
}

static void NAApplyStoredTransforms(void) {
    if (!origLayerSetSublayerTransform) return;
    NSEnumerator *keys = NATargetTransforms.keyEnumerator;
    CALayer *layer = nil;
    while ((layer = [keys nextObject])) {
        NSValue *value = [NATargetTransforms objectForKey:layer];
        if (!value) continue;
        CATransform3D target = value.CATransform3DValue;
        CATransform3D desired = NABlendTransform(target, NAMotionBlend);
        if (NAMotionBlend < 0.0005) desired = CATransform3DIdentity;
        if (CATransform3DEqualToTransform(layer.sublayerTransform, desired)) continue;
        origLayerSetSublayerTransform(layer, @selector(setSublayerTransform:), desired);
    }
}

static void NARegisterPans(UIView *view) {
    if (!view) return;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:[UIPanGestureRecognizer class]]) continue;
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)recognizer;
        if (![NAPans containsObject:pan]) [NAPans addObject:pan];
    }
    for (UIView *subview in view.subviews) NARegisterPans(subview);
}

static BOOL NAHorizontalMovementActive(void) {
    for (UIPanGestureRecognizer *pan in NAPans.allObjects) {
        if (!pan || !pan.enabled) continue;
        UIGestureRecognizerState state = pan.state;
        if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) continue;
        CGPoint velocity = [pan velocityInView:pan.view];
        CGFloat horizontal = fabs(velocity.x);
        CGFloat vertical = fabs(velocity.y);
        if (horizontal >= 8.0 && horizontal > vertical * 1.06) return YES;
    }
    return NO;
}

static BOOL NAClassNameContains(UIView *view, NSString *needle) {
    NSString *name = NSStringFromClass(view.class);
    return [name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void NACollectViews(UIView *view, NSMutableArray<UIView *> *result) {
    for (UIView *subview in view.subviews) {
        [result addObject:subview];
        if (subview.subviews.count) NACollectViews(subview, result);
    }
}

static BOOL NAHeaderIconCandidate(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    if (width < 14.0 || height < 14.0 || width > 72.0 || height > 72.0) return NO;
    if ([view isKindOfClass:[UIImageView class]]) return YES;
    return NAClassNameContains(view, @"Icon") && !NAClassNameContains(view, @"List");
}

static void NAClearHeaderIconShadow(UIView *icon) {
    if (!icon) return;
    NSArray<UIView *> *targets = icon.superview ? @[icon, icon.superview] : @[icon];
    for (UIView *target in targets) {
        CALayer *layer = target.layer;
        layer.shadowOpacity = 0.0f;
        layer.shadowRadius = 0.0f;
        layer.shadowOffset = CGSizeZero;
        layer.shadowPath = nil;
    }
    UIView *parent = icon.superview;
    for (UIView *sibling in parent.subviews) {
        if (sibling == icon || !NAClassNameContains(sibling, @"Shadow")) continue;
        CGRect expanded = CGRectInset(icon.frame, -14.0, -14.0);
        if (CGRectIntersectsRect(expanded, sibling.frame) &&
            CGRectGetWidth(sibling.bounds) <= 90.0 && CGRectGetHeight(sibling.bounds) <= 90.0) {
            sibling.hidden = YES;
            sibling.alpha = 0.0;
        }
    }
}

static void NAFixHeaderOnce(UIView *root) {
    if (!root || [NAFixedHeaders containsObject:root]) return;
    [NAFixedHeaders addObject:root];

    NSMutableArray<UIView *> *views = [NSMutableArray array];
    NACollectViews(root, views);
    for (UIView *candidate in views) {
        if (![candidate isKindOfClass:[UILabel class]]) continue;
        UILabel *label = (UILabel *)candidate;
        if (label.text.length == 0 || label.hidden || label.alpha < 0.05) continue;
        CGRect labelRect = [label convertRect:label.bounds toView:root];
        if (CGRectGetHeight(labelRect) > 64.0) continue;

        UIView *bestIcon = nil;
        CGFloat bestScore = CGFLOAT_MAX;
        for (UIView *icon in views) {
            if (!NAHeaderIconCandidate(icon) || icon.hidden || icon.alpha < 0.05) continue;
            CGRect iconRect = [icon convertRect:icon.bounds toView:root];
            CGFloat gap = CGRectGetMinX(labelRect) - CGRectGetMaxX(iconRect);
            CGFloat vertical = fabs(CGRectGetMidY(labelRect) - CGRectGetMidY(iconRect));
            if (gap < -12.0 || gap > 110.0 || vertical > 36.0) continue;
            CGFloat score = fabs(gap - 10.0) + vertical * 2.0;
            if (score < bestScore) { bestScore = score; bestIcon = icon; }
        }
        if (!bestIcon) continue;

        NAClearHeaderIconShadow(bestIcon);
        CGRect iconRect = [bestIcon convertRect:bestIcon.bounds toView:root];
        CGFloat deltaY = CGRectGetMidY(labelRect) - CGRectGetMidY(iconRect);
        if (fabs(deltaY) > 0.5 && fabs(deltaY) < 20.0) {
            CGPoint centre = [bestIcon.superview convertPoint:bestIcon.center toView:root];
            centre.y += deltaY;
            bestIcon.center = [bestIcon.superview convertPoint:centre fromView:root];
        }
        return;
    }
}

@interface NANextAuraSmoothFrameTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end

@implementation NANextAuraSmoothFrameTarget
- (void)tick:(CADisplayLink *)link {
    if (!NASwitcherVisible) return;

    if (NARegistrationFrames < 36 && (NAPans.allObjects.count == 0 || NARegistrationFrames % 6 == 0)) {
        NARegisterPans(NASwitcherRootView);
        NARegistrationFrames++;
    }

    CGFloat target = NAHorizontalMovementActive() ? 1.0 : 0.0;
    CFTimeInterval dt = link.targetTimestamp > link.timestamp ? (link.targetTimestamp - link.timestamp) : link.duration;
    if (dt <= 0.0 || dt > 0.05) dt = 1.0 / 120.0;

    // Fast, fluid entry and a slightly softer settle. This removes the hard
    // on/off snap from Test 17 while still returning every card to straight.
    CGFloat response = target > NAMotionBlend ? 22.0 : 14.0;
    CGFloat alpha = 1.0 - exp(-response * dt);
    NAMotionBlend += (target - NAMotionBlend) * alpha;
    if (target == 0.0 && NAMotionBlend < 0.002) NAMotionBlend = 0.0;
    if (target == 1.0 && NAMotionBlend > 0.998) NAMotionBlend = 1.0;

    NAApplyStoredTransforms();
}
@end

static void NAStartSession(id controller) {
    NASwitcherVisible = YES;
    NAMotionBlend = 0.0;
    NARegistrationFrames = 0;
    [NAPans removeAllObjects];
    [NATargetTransforms removeAllObjects];
    [NAFixedHeaders removeAllObjects];

    UIView *root = [controller isKindOfClass:[UIViewController class]] ? [(UIViewController *)controller view] : nil;
    NASwitcherRootView = root;
    NARegisterPans(root);
    dispatch_async(dispatch_get_main_queue(), ^{ NARegisterPans(root); });

    if (!NAFrameLink) {
        NSInteger maximumFPS = MAX(60, UIScreen.mainScreen.maximumFramesPerSecond);
        NAFrameTarget = [NANextAuraSmoothFrameTarget new];
        NAFrameLink = [CADisplayLink displayLinkWithTarget:NAFrameTarget selector:@selector(tick:)];
        if (@available(iOS 15.0, *)) {
            float fps = (float)maximumFPS;
            NAFrameLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0f, fps, fps);
        } else {
            NAFrameLink.preferredFramesPerSecond = maximumFPS;
        }
        [NAFrameLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

static void NAStopSession(void) {
    NAMotionBlend = 0.0;
    NAApplyStoredTransforms();
    NASwitcherVisible = NO;
    NASwitcherRootView = nil;
    [NAFrameLink invalidate];
    NAFrameLink = nil;
    NAFrameTarget = nil;
    [NAPans removeAllObjects];
    [NATargetTransforms removeAllObjects];
    [NAFixedHeaders removeAllObjects];
}

static void (*origFluidWillAppear)(id, SEL, BOOL);
static void hookFluidWillAppear(id self, SEL _cmd, BOOL animated) {
    NAStartSession(self);
    if (origFluidWillAppear) origFluidWillAppear(self, _cmd, animated);
}
static void (*origFluidDidDisappear)(id, SEL, BOOL);
static void hookFluidDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origFluidDidDisappear) origFluidDidDisappear(self, _cmd, animated);
    NAStopSession();
}
static void (*origMainWillAppear)(id, SEL, BOOL);
static void hookMainWillAppear(id self, SEL _cmd, BOOL animated) {
    NAStartSession(self);
    if (origMainWillAppear) origMainWillAppear(self, _cmd, animated);
}
static void (*origMainDidDisappear)(id, SEL, BOOL);
static void hookMainDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origMainDidDisappear) origMainDidDisappear(self, _cmd, animated);
    NAStopSession();
}

static void hookLayerSetSublayerTransform(CALayer *self, SEL _cmd, CATransform3D transform) {
    if (NAIsSwitcherCardLayer(self)) {
        [NATargetTransforms setObject:[NSValue valueWithCATransform3D:transform] forKey:self];
        CATransform3D desired = NABlendTransform(transform, NAMotionBlend);
        if (NAMotionBlend < 0.0005) desired = CATransform3DIdentity;
        if (!CATransform3DEqualToTransform(self.sublayerTransform, desired) && origLayerSetSublayerTransform) {
            origLayerSetSublayerTransform(self, _cmd, desired);
        }
        return;
    }
    if (origLayerSetSublayerTransform) origLayerSetSublayerTransform(self, _cmd, transform);
}

static void (*origContainerLayout)(id, SEL);
static void hookContainerLayout(id self, SEL _cmd) {
    if (origContainerLayout) origContainerLayout(self, _cmd);
    if (NASwitcherVisible) NAFixHeaderOnce((UIView *)self);
}

static void (*origContainerViewLayout)(id, SEL);
static void hookContainerViewLayout(id self, SEL _cmd) {
    if (origContainerViewLayout) origContainerViewLayout(self, _cmd);
    if (NASwitcherVisible) NAFixHeaderOnce((UIView *)self);
}

static void NAHookController(NSString *name, IMP willIMP, IMP *willOrig, IMP disappearIMP, IMP *disappearOrig) {
    Class cls = NSClassFromString(name);
    if (!cls) return;
    if (class_getInstanceMethod(cls, @selector(viewWillAppear:)))
        MSHookMessageEx(cls, @selector(viewWillAppear:), willIMP, willOrig);
    if (class_getInstanceMethod(cls, @selector(viewDidDisappear:)))
        MSHookMessageEx(cls, @selector(viewDidDisappear:), disappearIMP, disappearOrig);
}

__attribute__((constructor)) static void NextAuraInstallSmoothInteraction(void) {
    @autoreleasepool {
        NAPans = [NSHashTable weakObjectsHashTable];
        NATargetTransforms = [NSMapTable weakToStrongObjectsMapTable];
        NAFixedHeaders = [NSHashTable weakObjectsHashTable];

        NAContainerClass = NSClassFromString(@"SBFluidSwitcherItemContainer");
        NAContainerViewClass = NSClassFromString(@"SBFluidSwitcherItemContainerView");
        NASnapshotClass = NSClassFromString(@"SBAppSwitcherSnapshotView");
        NAAppLayoutClass = NSClassFromString(@"SBAppLayoutView");

        NAHookController(@"SBFluidSwitcherViewController", (IMP)hookFluidWillAppear, (IMP *)&origFluidWillAppear,
                         (IMP)hookFluidDidDisappear, (IMP *)&origFluidDidDisappear);
        NAHookController(@"SBMainSwitcherViewController", (IMP)hookMainWillAppear, (IMP *)&origMainWillAppear,
                         (IMP)hookMainDidDisappear, (IMP *)&origMainDidDisappear);

        if (NAContainerClass && class_getInstanceMethod(NAContainerClass, @selector(layoutSubviews)))
            MSHookMessageEx(NAContainerClass, @selector(layoutSubviews), (IMP)hookContainerLayout, (IMP *)&origContainerLayout);
        if (NAContainerViewClass && class_getInstanceMethod(NAContainerViewClass, @selector(layoutSubviews)))
            MSHookMessageEx(NAContainerViewClass, @selector(layoutSubviews), (IMP)hookContainerViewLayout, (IMP *)&origContainerViewLayout);

        MSHookMessageEx([CALayer class], @selector(setSublayerTransform:),
                        (IMP)hookLayerSetSublayerTransform, (IMP *)&origLayerSetSublayerTransform);
    }
}
