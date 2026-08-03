#import <UIKit/UIKit.h>

extern "C" void NMStartSwiftRuntimeV16(void);
extern "C" void NMRefreshSwiftControllerV16(void *controllerPointer);
extern "C" void NMRegisterSwiftTableView(void *tablePointer);
extern "C" void NMRefreshSwiftConversationTables(void);

static BOOL NMIsMessagesProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"];
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (NMIsMessagesProcess()) {
        NMRefreshSwiftControllerV16((__bridge void *)self);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (NMIsMessagesProcess()) {
        NMRefreshSwiftControllerV16((__bridge void *)self);
    }
}

%end

%hook UITableView

- (void)didMoveToWindow {
    %orig;
    if (NMIsMessagesProcess() && self.window) {
        NMRegisterSwiftTableView((__bridge void *)self);
    }
}

- (void)reloadData {
    %orig;
    if (NMIsMessagesProcess() && self.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NMRegisterSwiftTableView((__bridge void *)self);
        });
    }
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    if (NMIsMessagesProcess() && self.rootViewController) {
        NMRefreshSwiftControllerV16((__bridge void *)self.rootViewController);
        NMRefreshSwiftConversationTables();
    }
}

- (void)didBecomeKeyWindow {
    %orig;
    if (NMIsMessagesProcess() && self.rootViewController) {
        NMRefreshSwiftControllerV16((__bridge void *)self.rootViewController);
        NMRefreshSwiftConversationTables();
    }
}

%end

%ctor {
    if (NMIsMessagesProcess()) {
        NMStartSwiftRuntimeV16();
    }
}
