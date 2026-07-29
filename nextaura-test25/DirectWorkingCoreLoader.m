#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *NAWorkingCoreBundlePath = nil;
static NSBundle *(*NAOriginalBundleWithPath)(id, SEL, NSString *) = NULL;

static NSBundle *NARedirectedBundleWithPath(id receiver, SEL selector, NSString *path) {
    NSString *resolvedPath = path;
    NSString *workingCorePath = NAWorkingCoreBundlePath;

    if (workingCorePath.length > 0 && [path isEqualToString:@"/Library/PreferenceBundles/STPreferences.bundle"]) {
        resolvedPath = workingCorePath;
    } else if (workingCorePath.length > 0 && [path isEqualToString:@"/Library/PreferenceBundles/STPreferences.bundle/en.lproj"]) {
        resolvedPath = [workingCorePath stringByAppendingPathComponent:@"en.lproj"];
    }

    return NAOriginalBundleWithPath ? NAOriginalBundleWithPath(receiver, selector, resolvedPath) : nil;
}

static void NAInstallLegacyBundlePathRedirect(NSString *workingCorePath) {
    NAWorkingCoreBundlePath = [workingCorePath copy];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method method = class_getClassMethod([NSBundle class], @selector(bundleWithPath:));
        if (!method) return;

        NAOriginalBundleWithPath = (NSBundle *(*)(id, SEL, NSString *))method_getImplementation(method);
        method_setImplementation(method, (IMP)NARedirectedBundleWithPath);
    });
}

static NSString *NAHostPreferenceBundlePath(void) {
    Class hostClass = NSClassFromString(@"UVRootListController");
    NSBundle *hostBundle = hostClass ? [NSBundle bundleForClass:hostClass] : nil;
    if (!hostBundle) hostBundle = [NSBundle bundleWithIdentifier:@"com.nextsolution.unlockvibrateprefs"];
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

- (void)openNextAuraWorkingCoreDirect:(id)sender {
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

    // Springtomize's localisation helper uses two stock absolute paths. RootHide
    // cannot resolve those paths from Preferences. Redirect only those exact
    // bundle lookups to the currently active randomized .jbroot location.
    NAInstallLegacyBundlePathRedirect(workingCorePath);

    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    NSArray<NSString *> *supportLibraries = @[
        [jailbreakRoot stringByAppendingPathComponent:@"usr/lib/librocketbootstrap.dylib"],
        [jailbreakRoot stringByAppendingPathComponent:@"usr/lib/libapplist.dylib"],
        [jailbreakRoot stringByAppendingPathComponent:@"usr/lib/libST.dylib"]
    ];

    for (NSString *libraryPath in supportLibraries) NAPreloadLibrary(libraryPath, errors);

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

    NSString *executablePath = workingCoreBundle.executablePath;
    if (executablePath.length == 0) executablePath = [workingCorePath stringByAppendingPathComponent:@"STPreferences"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:executablePath]) {
        NAShowWorkingCoreError(self,
                               @"Working Core Executable Missing",
                               [NSString stringWithFormat:@"The bundle exists, but its executable was not found.\n\nExpected:\n%@", executablePath]);
        return;
    }

    // The imported core uses an old-style MH_DYLIB executable inside its
    // preference bundle. Match its original loader and open it with dlopen.
    dlerror();
    void *workingCoreHandle = dlopen(executablePath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!workingCoreHandle) {
        NSString *message = [NSString stringWithFormat:
                             @"The Working Core executable could not be loaded.\n\nExecutable:\n%@\n\nDynamic-loader error:\n%@",
                             executablePath,
                             NALastDLError()];
        NAShowWorkingCoreError(self, @"Working Core Dynamic-Loader Error", message);
        return;
    }

    NSString *principalClassName = [workingCoreBundle objectForInfoDictionaryKey:@"NSPrincipalClass"];
    if (principalClassName.length == 0) principalClassName = @"STSettingsListController";
    Class controllerClass = NSClassFromString(principalClassName);
    if (!controllerClass || ![controllerClass isSubclassOfClass:[UIViewController class]]) {
        NAShowWorkingCoreError(self,
                               @"Working Core Controller Missing",
                               [NSString stringWithFormat:@"The executable loaded, but %@ was not available.", principalClassName]);
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
