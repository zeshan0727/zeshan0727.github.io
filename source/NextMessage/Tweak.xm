#import <UIKit/UIKit.h>

extern "C" void NMStartSwiftRuntime(void);
extern "C" void NMRefreshSwiftController(void *controllerPointer);

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.MobileSMS"]) {
        NMRefreshSwiftController((__bridge void *)self);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.MobileSMS"]) {
        NMRefreshSwiftController((__bridge void *)self);
    }
}

%end

%ctor {
    if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.MobileSMS"]) {
        NMStartSwiftRuntime();
    }
}
