#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static BOOL NASwitcherVisible = NO;
static BOOL NAHorizontalMotion = NO;
static CADisplayLink *NAFrameLink = nil;
static id NAFrameTarget = nil;
static NSHashTable<UIPanGestureRecognizer *> *NAPanRecognizers = nil;
static NSHashTable<CALayer *> *NACardLayers = nil;
static NSHashTable<UIView *> *NAFixedContainers = nil;
static Class NAContainerClass = Nil;
static Class NAContainerViewClass = Nil;
static Class NASnapshotClass = Nil;
static Class NAAppLayoutClass = Nil;

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

static void NAResetCardEffects(void) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in NACardLayers.allObjects) {
        if (layer && !CATransform3DIsIdentity(layer.sublayerTransform)) layer.sublayerTransform = CATransform3DIdentity;
    }
    [CATransaction commit];
}

static void NASetHorizontalMotion(BOOL moving) {
    if (NAHorizontalMotion == moving) return;
    NAHorizontalMotion = moving;
    if (!moving) NAResetCardEffects();
}

static void NARegisterPansInView(UIView *view) {
    if (!view) return;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:[UIPanGestureRecognizer class]]) continue;
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)recognizer;
        if (![NAPanRecognizers containsObject:pan]) [NAPanRecognizers addObject:pan];
    }
    for (UIView *subview in view.subviews) NARegisterPansInView(subview);
}

static BOOL NAHasRealHorizontalMotion(void) {
    for (UIPanGestureRecognizer *pan in NAPanRecognizers.allObjects) {
        if (!pan || !pan.enabled) continue;
        UIGestureRecognizerState state = pan.state;
        if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) continue;
        CGPoint velocity = [pan velocityInView:pan.view];
        CGFloat vx = fabs(velocity.x);
        CGFloat vy = fabs(velocity.y);
        if (vx >= 10.0 && vx > vy * 1.08) return YES;
    }
    return NO;
}

static BOOL NAClassNameContains(UIView *view, NSString *needle) {
    NSString *name = NSStringFromClass(view.class);
    return [name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void NACollectDescendants(UIView *view, NSMutableArray<UIView *> *views) {
    for (UIView *subview in view.subviews) {
        [views addObject:subview];
        if (subview.subviews.count) NACollectDescendants(subview, views);
    }
}

static BOOL NAIsSmallHeaderIcon(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    if (width < 14.0 || height < 14.0 || width > 72.0 || height > 72.0) return NO;
    if ([view isKindOfClass:[UIImageView class]]) return YES;
    return NAClassNameContains(view, @"Icon") && !NAClassNameContains(view, @"List");
}

static void NAClearIconShadow(UIView *icon) {
    if (!icon) return;
    NSArray<UIView *> *targets = icon.superview ? @[icon, icon.superview] : @[icon];
    for (UIView *target in targets) {
        target.layer.shadowOpacity = 0.0f;
        target.layer.shadowRadius = 0.0f;
        target.layer.shadowOffset = CGSizeZero;
        target.layer.shadowPath = nil;
    }
    UIView *parent = icon.superview;
    for (UIView *sibling in parent.subviews) {
        if (sibling == icon || !NAClassNameContains(sibling, @"Shadow")) continue;
        CGRect expanded = CGRectInset(icon.frame, -14.0, -14.0);
        if (CGRectIntersectsRect(expanded, sibling.frame) && CGRectGetWidth(sibling.bounds) <= 90.0 && CGRectGetHeight(sibling.bounds) <= 90.0) {
            sibling.hidden = YES;
            sibling.alpha = 0.0;
        }
    }
}

static void NAFixHeaderIconAndTitle(UIView *root) {
    if (!root || [NAFixedContainers containsObject:root]) return;
    [NAFixedContainers addObject:root];
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    NACollectDescendants(root, views);
    for (UIView *candidate in views) {
        if (![candidate isKindOfClass:[UILabel class]]) continue;
        UILabel *label = (UILabel *)candidate;
        if (label.text.length == 0 || label.hidden || label.alpha < 0.05) continue;
        CGRect labelRect = [label convertRect:label.bounds toView:root];
        if (CGRectGetHeight(labelRect) > 64.0) continue;
        UIView *bestIcon = nil;
        CGFloat bestScore = CGFLOAT_MAX;
        for (UIView *icon in views) {
            if (!NAIsSmallHeaderIcon(icon) || icon.hidden || icon.alpha < 0.05) continue;
            CGRect iconRect = [icon convertRect:icon.bounds toView:root];
            CGFloat gap = CGRectGetMinX(labelRect) - CGRectGetMaxX(iconRect);
            CGFloat vertical = fabs(CGRectGetMidY(labelRect) - CGRectGetMidY(iconRect));
            if (gap < -12.0 || gap > 110.0 || vertical > 36.0) continue;
            CGFloat score = fabs(gap - 10.0) + vertical * 2.0;
            if (score < bestScore) { bestScore = score; bestIcon = icon; }
        }
        if (!bestIcon) continue;
        NAClearIconShadow(bestIcon);
        CGRect iconRect = [bestIcon convertRect:bestIcon.bounds toView:root];
        CGFloat deltaY = CGRectGetMidY(labelRect) - CGRectGetMidY(iconRect);
        if (fabs(deltaY) > 0.5 && fabs(deltaY) < 20.0) {
            CGPoint centreInRoot = [bestIcon.superview convertPoint:bestIcon.center toView:root];
            centreInRoot.y += deltaY;
            bestIcon.center = [bestIcon.superview convertPoint:centreInRoot fromView:root];
        }
        return;
    }
}

@interface NANextAuraInteractionFrameTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end
@implementation NANextAuraInteractionFrameTarget
- (void)tick:(CADisplayLink *)link {
    (void)link;
    if (NASwitcherVisible) NASetHorizontalMotion(NAHasRealHorizontalMotion());
}
@end

static void NAStartSwitcherSession(id controller) {
    NASwitcherVisible = YES;
    NAHorizontalMotion = NO;
    [NAPanRecognizers removeAllObjects];
    [NACardLayers removeAllObjects];
    [NAFixedContainers removeAllObjects];
    UIView *view = [controller isKindOfClass:[UIViewController class]] ? [(UIViewController *)controller view] : nil;
    NARegisterPansInView(view);
    dispatch_async(dispatch_get_main_queue(), ^{ NARegisterPansInView(view); });
    if (!NAFrameLink) {
        NSInteger maximumFPS = MAX(60, UIScreen.mainScreen.maximumFramesPerSecond);
        NAFrameTarget = [NANextAuraInteractionFrameTarget new];
        NAFrameLink = [CADisplayLink displayLinkWithTarget:NAFrameTarget selector:@selector(tick:)];
        if (@available(iOS 15.0, *)) {
            float fps = (float)maximumFPS;
            NAFrameLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0f, fps, fps);
        } else {
            NAFrameLink.preferredFramesPerSecond = maximumFPS;
        }
        [NAFrameLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    NAResetCardEffects();
}

static void NAStopSwitcherSession(void) {
    NASetHorizontalMotion(NO);
    NASwitcherVisible = NO;
    [NAFrameLink invalidate];
    NAFrameLink = nil;
    NAFrameTarget = nil;
    [NAPanRecognizers removeAllObjects];
    [NACardLayers removeAllObjects];
    [NAFixedContainers removeAllObjects];
}

static void (*origFluidWillAppear)(id, SEL, BOOL);
static void hookFluidWillAppear(id self, SEL _cmd, BOOL animated) { NAStartSwitcherSession(self); if (origFluidWillAppear) origFluidWillAppear(self, _cmd, animated); }
static void (*origFluidDidDisappear)(id, SEL, BOOL);
static void hookFluidDidDisappear(id self, SEL _cmd, BOOL animated) { if (origFluidDidDisappear) origFluidDidDisappear(self, _cmd, animated); NAStopSwitcherSession(); }
static void (*origMainWillAppear)(id, SEL, BOOL);
static void hookMainWillAppear(id self, SEL _cmd, BOOL animated) { NAStartSwitcherSession(self); if (origMainWillAppear) origMainWillAppear(self, _cmd, animated); }
static void (*origMainDidDisappear)(id, SEL, BOOL);
static void hookMainDidDisappear(id self, SEL _cmd, BOOL animated) { if (origMainDidDisappear) origMainDidDisappear(self, _cmd, animated); NAStopSwitcherSession(); }

static void (*origLayerSetSublayerTransform)(CALayer *, SEL, CATransform3D);
static void hookLayerSetSublayerTransform(CALayer *self, SEL _cmd, CATransform3D transform) {
    if (NAIsSwitcherCardLayer(self)) {
        [NACardLayers addObject:self];
        CATransform3D desired = NAHorizontalMotion ? transform : CATransform3DIdentity;
        if (CATransform3DEqualToTransform(self.sublayerTransform, desired)) return;
        if (origLayerSetSublayerTransform) origLayerSetSublayerTransform(self, _cmd, desired);
        return;
    }
    if (origLayerSetSublayerTransform) origLayerSetSublayerTransform(self, _cmd, transform);
}

static void (*origContainerLayout)(id, SEL);
static void hookContainerLayout(id self, SEL _cmd) {
    if (origContainerLayout) origContainerLayout(self, _cmd);
    if (!NASwitcherVisible) return;
    CALayer *layer = [(UIView *)self layer];
    [NACardLayers addObject:layer];
    if (!NAHorizontalMotion && !CATransform3DIsIdentity(layer.sublayerTransform)) {
        [CATransaction begin]; [CATransaction setDisableActions:YES]; layer.sublayerTransform = CATransform3DIdentity; [CATransaction commit];
    }
    NAFixHeaderIconAndTitle((UIView *)self);
}

static void (*origContainerViewLayout)(id, SEL);
static void hookContainerViewLayout(id self, SEL _cmd) {
    if (origContainerViewLayout) origContainerViewLayout(self, _cmd);
    if (!NASwitcherVisible) return;
    CALayer *layer = [(UIView *)self layer];
    [NACardLayers addObject:layer];
    if (!NAHorizontalMotion && !CATransform3DIsIdentity(layer.sublayerTransform)) {
        [CATransaction begin]; [CATransaction setDisableActions:YES]; layer.sublayerTransform = CATransform3DIdentity; [CATransaction commit];
    }
    NAFixHeaderIconAndTitle((UIView *)self);
}

static void NAHookSwitcherController(NSString *name, IMP willIMP, IMP *willOrig, IMP disappearIMP, IMP *disappearOrig) {
    Class cls = NSClassFromString(name);
    if (!cls) return;
    if (class_getInstanceMethod(cls, @selector(viewWillAppear:))) MSHookMessageEx(cls, @selector(viewWillAppear:), willIMP, willOrig);
    if (class_getInstanceMethod(cls, @selector(viewDidDisappear:))) MSHookMessageEx(cls, @selector(viewDidDisappear:), disappearIMP, disappearOrig);
}

__attribute__((constructor)) static void NextAuraInstallTest17Interaction(void) {
    @autoreleasepool {
        NAPanRecognizers = [NSHashTable weakObjectsHashTable];
        NACardLayers = [NSHashTable weakObjectsHashTable];
        NAFixedContainers = [NSHashTable weakObjectsHashTable];
        NAContainerClass = NSClassFromString(@"SBFluidSwitcherItemContainer");
        NAContainerViewClass = NSClassFromString(@"SBFluidSwitcherItemContainerView");
        NASnapshotClass = NSClassFromString(@"SBAppSwitcherSnapshotView");
        NAAppLayoutClass = NSClassFromString(@"SBAppLayoutView");
        NAHookSwitcherController(@"SBFluidSwitcherViewController", (IMP)hookFluidWillAppear, (IMP *)&origFluidWillAppear, (IMP)hookFluidDidDisappear, (IMP *)&origFluidDidDisappear);
        NAHookSwitcherController(@"SBMainSwitcherViewController", (IMP)hookMainWillAppear, (IMP *)&origMainWillAppear, (IMP)hookMainDidDisappear, (IMP *)&origMainDidDisappear);
        if (NAContainerClass && class_getInstanceMethod(NAContainerClass, @selector(layoutSubviews))) MSHookMessageEx(NAContainerClass, @selector(layoutSubviews), (IMP)hookContainerLayout, (IMP *)&origContainerLayout);
        if (NAContainerViewClass && class_getInstanceMethod(NAContainerViewClass, @selector(layoutSubviews))) MSHookMessageEx(NAContainerViewClass, @selector(layoutSubviews), (IMP)hookContainerViewLayout, (IMP *)&origContainerViewLayout);
        MSHookMessageEx([CALayer class], @selector(setSublayerTransform:), (IMP)hookLayerSetSublayerTransform, (IMP *)&origLayerSetSublayerTransform);
    }
}
