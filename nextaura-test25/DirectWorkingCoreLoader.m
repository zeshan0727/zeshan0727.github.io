#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

static NSString *NAHostPreferenceBundlePath(void) {
    Class hostClass = NSClassFromString(@"UVRootListController");
    NSBundle *hostBundle = hostClass ? [NSBundle bundleForClass:hostClass] : nil;
    if (!hostBundle) {
        hostBundle = [NSBundle bundleWithIdentifier:@"com.nextsolution.unlockvibrateprefs"];
    }
    return hostBundle.bundlePath;
}

static NSString *NAJailbreakRootFromHostPath(NSString *hostPath) {
    if (hostPath.length == 0) return nil;
    NSString *preferenceBundlesDirectory = [hostPath stringByDeletingLastPathComponent];
    NSString *libraryDirectory = [preferenceBundlesDirectory stringByDeletingLastPathComponent];
    return [libraryDirectory stringByDeletingLastPathComponent];
}

static NSString *NALastDLError(void) {
    const char *error = dlerror();
    return error ? [NSString stringWithUTF8String:error] : @"Unknown dynamic-loader error";
}

static BOOL NAPreloadLibrary(NSString *path, NSMutableArray<NSString *> *errors) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [errors addObject:[NSString stringWithFormat:@"Missing: %@", path]];
        return NO;
    }
    dlerror();
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        [errors addObject:[NSString stringWithFormat:@"Could not load %@\n%@", path.lastPathComponent, NALastDLError()]];
        return NO;
    }
    return YES;
}

static void NAShowWorkingCoreError(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@implementation UIViewController (NextAuraDirectWorkingCore)

- (void)openNextAuraWorkingCore:(id)sender {
    (void)sender;

    NSString *hostPath = NAHostPreferenceBundlePath();
    NSString *jailbreakRoot = NAJailbreakRootFromHostPath(hostPath);
    if (hostPath.length == 0 || jailbreakRoot.length == 0) {
        NAShowWorkingCoreError(self,
                               @"NextAura Working Core",
                               @"NextAura could not determine the active RootHide jailbreak path. Close Settings, restart SpringBoard and try again.");
        return;
    }

    NSString *preferenceBundlesDirectory = [hostPath stringByDeletingLastPathComponent];
    NSString *workingCorePath = [preferenceBundlesDirectory stringByAppendingPathComponent:@"STPreferences.bundle"];

    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    NSArray<NSString *> *supportLibraries = @[
        [jailbreakRoot stringByAppendingPathComponent:@"usr/lib/librocketbootstrap.dylib"],
        [jailbreakRoot stringByAppendingPathComponent:@"usr/lib/libapplist.dylib"],
        [jailbreakRoot stringByAppendingPathComponent:@"usr/lib/libST.dylib"]
    ];

    for (NSString *libraryPath in supportLibraries) {
        NAPreloadLibrary(libraryPath, errors);
    }

    if (errors.count > 0) {
        NSString *message = [NSString stringWithFormat:
                             @"The Working Core support libraries could not be prepared from the active RootHide path:\n\n%@\n\nDetected root:\n%@",
                             [errors componentsJoinedByString:@"\n\n"], jailbreakRoot];
        NAShowWorkingCoreError(self, @"Working Core Dependency Error", message);
        return;
    }

    NSBundle *workingCoreBundle = [NSBundle bundleWithPath:workingCorePath];
    if (!workingCoreBundle) {
        NAShowWorkingCoreError(self,
                               @"Working Core Not Found",
                               [NSString stringWithFormat:@"STPreferences.bundle was not found beside NextAura.\n\nExpected path:\n%@", workingCorePath]);
        return;
    }

    NSError *loadError = nil;
    if (![workingCoreBundle loadAndReturnError:&loadError]) {
        NSString *message = [NSString stringWithFormat:
                             @"The Working Core bundle exists but iOS could not load it.\n\nPath:\n%@\n\nError:\n%@",
                             workingCorePath,
                             loadError.localizedDescription ?: @"Unknown bundle-loading error"];
        NAShowWorkingCoreError(self, @"Working Core Load Error", message);
        return;
    }

    Class controllerClass = NSClassFromString(@"STSettingsListController");
    if (!controllerClass) controllerClass = workingCoreBundle.principalClass;
    if (!controllerClass || ![controllerClass isSubclassOfClass:[UIViewController class]]) {
        NAShowWorkingCoreError(self,
                               @"Working Core Controller Missing",
                               @"The bundle loaded, but STSettingsListController was not available.");
        return;
    }

    UIViewController *workingCoreController = [[controllerClass alloc] init];
    if (!workingCoreController) {
        NAShowWorkingCoreError(self,
                               @"Working Core Controller Error",
                               @"STSettingsListController could not be created.");
        return;
    }

    workingCoreController.title = @"NextAura Working Core";
    if (self.navigationController) {
        [self.navigationController pushViewController:workingCoreController animated:YES];
    } else {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:workingCoreController];
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

@end
