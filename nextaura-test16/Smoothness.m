#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static BOOL NASwitcherVisible = NO;
static CADisplayLink *NAFrameLink = nil;
static id NAFrameTarget = nil;
static Class NAContainerClass = Nil;
static Class NAContainerViewClass = Nil;
static Class NASnapshotClass = Nil;
static Class NAAppLayoutClass = Nil;

@interface NANextAuraFrameTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end

@implementation NANextAuraFrameTarget
- (void)tick:(CADisplayLink *)link {
    (void)link;
}
@end

static BOOL NAIsSwitcherCardLayer(CALayer *layer) {
    if (!NASwitcherVisible || !layer) return NO;
    id delegate = layer.delegate;
    if (!delegate) return NO;
    return (NAContainerClass && [delegate isKindOfClass:NAContainerClass]) ||
           (NAContainerViewClass && [delegate isKindOfClass:NAContainerViewClass]) ||
           (NASnapshotClass && [delegate isKindOfClass:NASnapshotClass]) ||
           (NAAppLayoutClass && [delegate isKindOfClass:NAAppLayoutClass]);
}

static void NAStartMaximumRefreshRate(void) {
    NASwitcherVisible = YES;
    if (NAFrameLink) return;

    UIScreen *screen = UIScreen.mainScreen;
    NSInteger maximumFPS = screen.maximumFramesPerSecond;
    if (maximumFPS <= 60) return;

    NAFrameTarget = [NANextAuraFrameTarget new];
    NAFrameLink = [CADisplayLink displayLinkWithTarget:NAFrameTarget selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) {
        float fps = (float)maximumFPS;
        NAFrameLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
    } else {
        NAFrameLink.preferredFramesPerSecond = maximumFPS;
    }
    [NAFrameLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

static void NAStopMaximumRefreshRate(void) {
    NASwitcherVisible = NO;
    [NAFrameLink invalidate];
    NAFrameLink = nil;
    NAFrameTarget = nil;
}

static void (*origSwitcherWillAppear)(id, SEL, BOOL);
static void hookSwitcherWillAppear(id self, SEL _cmd, BOOL animated) {
    NAStartMaximumRefreshRate();
    if (origSwitcherWillAppear) origSwitcherWillAppear(self, _cmd, animated);
}

static void (*origSwitcherDidDisappear)(id, SEL, BOOL);
static void hookSwitcherDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origSwitcherDidDisappear) origSwitcherDidDisappear(self, _cmd, animated);
    NAStopMaximumRefreshRate();
}

static void (*origLayerSetTransform)(CALayer *, SEL, CATransform3D);
static void hookLayerSetTransform(CALayer *self, SEL _cmd, CATransform3D transform) {
    if (NAIsSwitcherCardLayer(self) && CATransform3DEqualToTransform(self.transform, transform)) return;
    if (origLayerSetTransform) origLayerSetTransform(self, _cmd, transform);
}

static void (*origLayerSetSublayerTransform)(CALayer *, SEL, CATransform3D);
static void hookLayerSetSublayerTransform(CALayer *self, SEL _cmd, CATransform3D transform) {
    if (NAIsSwitcherCardLayer(self) && CATransform3DEqualToTransform(self.sublayerTransform, transform)) return;
    if (origLayerSetSublayerTransform) origLayerSetSublayerTransform(self, _cmd, transform);
}

__attribute__((constructor)) static void NextAuraInstallSmoothnessHelper(void) {
    @autoreleasepool {
        NAContainerClass = NSClassFromString(@"SBFluidSwitcherItemContainer");
        NAContainerViewClass = NSClassFromString(@"SBFluidSwitcherItemContainerView");
        NASnapshotClass = NSClassFromString(@"SBAppSwitcherSnapshotView");
        NAAppLayoutClass = NSClassFromString(@"SBAppLayoutView");

        Class controller = NSClassFromString(@"SBFluidSwitcherViewController");
        if (!controller) controller = NSClassFromString(@"SBMainSwitcherViewController");
        if (controller) {
            if (class_getInstanceMethod(controller, @selector(viewWillAppear:)))
                MSHookMessageEx(controller, @selector(viewWillAppear:), (IMP)hookSwitcherWillAppear, (IMP *)&origSwitcherWillAppear);
            if (class_getInstanceMethod(controller, @selector(viewDidDisappear:)))
                MSHookMessageEx(controller, @selector(viewDidDisappear:), (IMP)hookSwitcherDidDisappear, (IMP *)&origSwitcherDidDisappear);
        }

        Class layerClass = [CALayer class];
        MSHookMessageEx(layerClass, @selector(setTransform:), (IMP)hookLayerSetTransform, (IMP *)&origLayerSetTransform);
        MSHookMessageEx(layerClass, @selector(setSublayerTransform:), (IMP)hookLayerSetSublayerTransform, (IMP *)&origLayerSetSublayerTransform);
    }
}
