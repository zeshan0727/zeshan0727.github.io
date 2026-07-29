#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

@interface NACoreBridgeController : UIViewController
@property(nonatomic, assign) BOOL naDidAttemptOpen;
@end

static NSString *NABridgeRootPath(void) {
    NSBundle *bundle = [NSBundle bundleForClass:[NACoreBridgeController class]];
    NSString *path = bundle.bundlePath;
    if (!path.length) return nil;
    NSString *preferenceBundles = [path stringByDeletingLastPathComponent];
    NSString *library = [preferenceBundles stringByDeletingLastPathComponent];
    return [library stringByDeletingLastPathComponent];
}

static NSString *NAPreload(NSString *root, NSString *relativePath) {
    if (!root.length || !relativePath.length) return nil;
    NSString *path = [root stringByAppendingPathComponent:relativePath];
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
    NSMutableArray<NSString *> *errors = [NSMutableArray array];

    for (NSString *relative in @[@"usr/lib/librocketbootstrap.dylib", @"usr/lib/libapplist.dylib", @"usr/lib/libST.dylib"]) {
        NSString *error = NAPreload(root, relative);
        if (error.length) [errors addObject:[NSString stringWithFormat:@"%@: %@", relative.lastPathComponent, error]];
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
        loaded = handle != NULL;
        if (!loaded) {
            const char *error = dlerror();
            if (error) [errors addObject:[NSString stringWithUTF8String:error]];
        }
    }

    if (!loaded) {
        NSMutableString *message = [NSMutableString stringWithString:@"The Working Core executable could not be loaded."];
        if (bundleError.localizedDescription.length) [message appendFormat:@"\n\n%@", bundleError.localizedDescription];
        if (errors.count) [message appendFormat:@"\n\n%@", [errors componentsJoinedByString:@"\n"]];
        if (failureReason) *failureReason = message;
        return nil;
    }

    Class controllerClass = NSClassFromString(@"STSettingsListController");
    if (!controllerClass) controllerClass = coreBundle.principalClass;
    if (!controllerClass) {
        if (failureReason) *failureReason = @"STSettingsListController was not registered after loading the Working Core bundle.";
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

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    [spinner startAnimating];
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
