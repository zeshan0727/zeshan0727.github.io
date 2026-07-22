#import <UIKit/UIKit.h>

extern "C" void NMStartSwiftRuntime(void);
extern "C" void NMRefreshSwiftController(void *controllerPointer);

static BOOL NMIsMessagesProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"];
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (NMIsMessagesProcess()) {
        NMRefreshSwiftController((__bridge void *)self);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (NMIsMessagesProcess()) {
        NMRefreshSwiftController((__bridge void *)self);
    }
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    if (NMIsMessagesProcess() && self.rootViewController) {
        NMRefreshSwiftController((__bridge void *)self.rootViewController);
    }
}

- (void)didBecomeKeyWindow {
    %orig;
    if (NMIsMessagesProcess() && self.rootViewController) {
        NMRefreshSwiftController((__bridge void *)self.rootViewController);
    }
}

%end

%ctor {
    if (NMIsMessagesProcess()) {
        NMStartSwiftRuntime();
    }
}
