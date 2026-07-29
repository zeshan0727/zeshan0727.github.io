#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

@interface PSListController : UIViewController
@end

@interface NACoreBridgeController : PSListController
@property(nonatomic, assign) BOOL naDidAttemptOpen;
@end

static NSString *NABridgeRootPath(void) {
    NSBundle *bridgeBundle = [NSBundle bundleForClass:[NACoreBridgeController class]];
    NSString *bundlePath = bridgeBundle.bundlePath;
    if (bundlePath.length == 0) return nil;
    NSString *preferenceBundles = [bundlePath stringByDeletingLastPathComponent];
    NSString *library = [preferenceBundles stringByDeletingLastPathComponent];
    return [library stringByDeletingLastPathComponent];
}

static NSString *NAPreloadLibrary(NSString *root, NSString *name) {
    if (root.length == 0 || name.length == 0) return nil;
    NSString *path = [[root stringByAppendingPathComponent:@"usr/lib"] stringByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    dlerror();
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (handle) return nil;
    const char *error = dlerror();
    return error ? [NSString stringWithUTF8String:error] : @"Unknown dynamic-loader error";
}

static UIViewController *NALoadWorkingCore(NSString **failureReason) {
    NSBundle *bridgeBundle = [NSBundle bundleForClass:[NACoreBridgeController class]];
    NSString *preferenceBundles = [bridgeBundle.bundlePath stringByDeletingLastPathComponent];
    NSString *root = NABridgeRootPath();

    NSMutableArray<NSString *> *loaderErrors = [NSMutableArray array];
    for (NSString *library in @[@"librocketbootstrap.dylib", @"libapplist.dylib", @"libST.dylib"]) {
        NSString *error = NAPreloadLibrary(root, library);
        if (error.length) [loaderErrors addObject:[NSString stringWithFormat:@"%@: %@", library, error]];
    }

    NSString *corePath = [preferenceBundles stringByAppendingPathComponent:@"STPreferences.bundle"];
    NSBundle *coreBundle = [NSBundle bundleWithPath:corePath];
    if (!coreBundle) {
        if (failureReason) *failureReason = [NSString stringWithFormat:@"Working Core bundle was not found at:\n%@", corePath ?: @"unknown path"];
        return nil;
    }

    NSError *bundleError = nil;
    BOOL loaded = coreBundle.isLoaded || [coreBundle loadAndReturnError:&bundleError];
    if (!loaded && coreBundle.executablePath.length) {
        dlerror();
        void *handle = dlopen(coreBundle.executablePath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        loaded = (handle != NULL);
        if (!loaded) {
            const char *error = dlerror();
            if (error) [loaderErrors addObject:[NSString stringWithUTF8String:error]];
        }
    }

    if (!loaded) {
        NSMutableString *message = [NSMutableString stringWithString:@"The Working Core executable could not be loaded."];
        if (bundleError.localizedDescription.length) [message appendFormat:@"\n\n%@", bundleError.localizedDescription];
        if (loaderErrors.count) [message appendFormat:@"\n\n%@", [loaderErrors componentsJoinedByString:@"\n"]];
        if (failureReason) *failureReason = message;
        return nil;
    }

    Class controllerClass = NSClassFromString(@"STSettingsListController");
    if (!controllerClass) controllerClass = coreBundle.principalClass;
    if (!controllerClass) {
        if (failureReason) *failureReason = @"STSettingsListController was not registered after loading the bundle.";
        return nil;
    }

    UIViewController *controller = [[controllerClass alloc] init];
    if (!controller) {
        if (failureReason) *failureReason = @"The Working Core controller could not be created.";
        return nil;
    }
    controller.title = @"NextAura Working Core";
    return controller;
}

@implementation NACoreBridgeController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Opening Working Core…";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.naDidAttemptOpen) return;
    self.naDidAttemptOpen = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *failure = nil;
        UIViewController *workingCore = NALoadWorkingCore(&failure);
        if (workingCore) {
            UINavigationController *navigation = self.navigationController;
            if (navigation) {
                NSMutableArray<UIViewController *> *stack = navigation.viewControllers.mutableCopy;
                NSUInteger index = [stack indexOfObjectIdenticalTo:self];
                if (index != NSNotFound) {
                    stack[index] = workingCore;
                    [navigation setViewControllers:stack animated:NO];
                } else {
                    [navigation pushViewController:workingCore animated:YES];
                }
            } else {
                UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:workingCore];
                [self presentViewController:wrapper animated:YES completion:nil];
            }
            return;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Working Core Could Not Open"
                                                                       message:failure ?: @"Unknown loading error."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            self.naDidAttemptOpen = NO;
            [self viewDidAppear:NO];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Back" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
