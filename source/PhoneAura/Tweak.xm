#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PhoneAuraManager.h"
#import "PAFullSurfaceFixes.h"

static BOOL PAIsPhoneProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobilephone"];
}

static const void *PAControllerLayoutGuard = &PAControllerLayoutGuard;
static const void *PATableLayoutGuard = &PATableLayoutGuard;
static const void *PACollectionLayoutGuard = &PACollectionLayoutGuard;

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] controllerDidAppear:self];
        dispatch_async(dispatch_get_main_queue(), ^{ PAApplyFullSurfaceFixes(self); });
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!PAIsPhoneProcess() || [objc_getAssociatedObject(self, PAControllerLayoutGuard) boolValue]) return;
    objc_setAssociatedObject(self, PAControllerLayoutGuard, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[PhoneAuraManager sharedManager] controllerDidLayout:self];
    PAApplyFullSurfaceFixes(self);
    objc_setAssociatedObject(self, PAControllerLayoutGuard, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%hook UITabBarController

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
        dispatch_async(dispatch_get_main_queue(), ^{ PARefreshFullSurfaceForTabController(self); });
    }
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
        dispatch_async(dispatch_get_main_queue(), ^{ PARefreshFullSurfaceForTabController(self); });
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
        PARefreshFullSurfaceForTabController(self);
    }
}

%end

%hook UITableView

- (void)layoutSubviews {
    %orig;
    if (!PAIsPhoneProcess() || [objc_getAssociatedObject(self, PATableLayoutGuard) boolValue]) return;
    objc_setAssociatedObject(self, PATableLayoutGuard, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[PhoneAuraManager sharedManager] tableViewDidLayout:self];
    objc_setAssociatedObject(self, PATableLayoutGuard, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%hook UICollectionView

- (void)layoutSubviews {
    %orig;
    if (!PAIsPhoneProcess() || [objc_getAssociatedObject(self, PACollectionLayoutGuard) boolValue]) return;
    objc_setAssociatedObject(self, PACollectionLayoutGuard, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[PhoneAuraManager sharedManager] collectionViewDidLayout:self];
    objc_setAssociatedObject(self, PACollectionLayoutGuard, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%ctor {
    if (!PAIsPhoneProcess()) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [PhoneAuraManager sharedManager]; });
}
