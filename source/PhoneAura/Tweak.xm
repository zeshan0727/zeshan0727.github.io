#import <UIKit/UIKit.h>
#import "PhoneAuraManager.h"

static BOOL PAIsPhoneProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobilephone"];
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] controllerDidAppear:self];
    }
}

%end

%hook UITabBarController

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
    }
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
    }
}

%end

%ctor {
    if (!PAIsPhoneProcess()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [PhoneAuraManager sharedManager];
    });
}
