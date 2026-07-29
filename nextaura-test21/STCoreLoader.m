#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

static NSString * const NACoreBundlePath = @"/Library/PreferenceBundles/STPreferences.bundle";
static NSString * const NANextAuraDomain = @"com.nextsolution.unlockvibrate";
static NSString * const NAWorkingCoreDomain = @"com.st5.settings";
static NSString * const NABackgroundsPath = @"/var/mobile/Library/NextSolutionTweaks/CCBackgrounds";

static void NAAlert(id controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [(UIViewController *)controller presentViewController:alert animated:YES completion:nil];
}

static void NAOpenWorkingCore(id self, SEL _cmd, id specifier) {
    (void)_cmd; (void)specifier;
    NSBundle *bundle = [NSBundle bundleWithPath:NACoreBundlePath];
    if (!bundle || (![bundle isLoaded] && ![bundle load])) {
        NAAlert(self, @"NextAura Working Core", @"The working core bundle could not be loaded. Reinstall this package and make sure PreferenceLoader, AppList and RocketBootstrap are installed.");
        return;
    }

    Class controllerClass = NSClassFromString(@"STSettingsListController");
    if (!controllerClass) {
        NAAlert(self, @"NextAura Working Core", @"The working core controller is unavailable. Restart Settings or respring and try again.");
        return;
    }

    UIViewController *controller = [[controllerClass alloc] init];
    if (!controller) {
        NAAlert(self, @"NextAura Working Core", @"The working core could not be opened.");
        return;
    }
    controller.title = @"NextAura Working Core";
    UINavigationController *navigation = [(UIViewController *)self navigationController];
    if (navigation) [navigation pushViewController:controller animated:YES];
    else NAAlert(self, @"NextAura Working Core", @"No Settings navigation controller was found.");
}

static NSUInteger NAClearDomain(NSString *domain) {
    CFStringRef appID = (__bridge CFStringRef)domain;
    CFArrayRef keys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSUInteger count = keys ? CFArrayGetCount(keys) : 0;
    if (keys) {
        CFPreferencesSetMultiple(NULL, keys, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    return count;
}

static void NARespring(void) {
    const char *paths[] = {"/usr/bin/sbreload", "/var/jb/usr/bin/sbreload", NULL};
    for (int i = 0; paths[i]; i++) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:[NSString stringWithUTF8String:paths[i]]]) {
            pid_t pid = 0;
            char *const argv[] = {(char *)paths[i], NULL};
            if (posix_spawn(&pid, paths[i], NULL, NULL, argv, environ) == 0) return;
        }
    }
    const char *killall = "/usr/bin/killall";
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/killall"]) {
        pid_t pid = 0;
        char *const argv[] = {(char *)killall, (char *)"-9", (char *)"SpringBoard", NULL};
        posix_spawn(&pid, killall, NULL, NULL, argv, environ);
    }
}

static void NAResetUnifiedSettings(id self, SEL _cmd, id specifier) {
    (void)_cmd; (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset All NextAura Settings?"
                                                                    message:@"This removes all NextAura and Working Core settings, deletes copied Control Center module images, restores stock defaults, and restarts SpringBoard."
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset Everything" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSUInteger nextAuraCount = NAClearDomain(NANextAuraDomain);
        NSUInteger coreCount = NAClearDomain(NAWorkingCoreDomain);
        [[NSFileManager defaultManager] removeItemAtPath:NABackgroundsPath error:nil];

        notify_post("com.nextsolution.unlockvibrate/preferences.changed");
        notify_post("com.springtomize.st4.reload");

        NSString *message = [NSString stringWithFormat:@"Reset %lu NextAura values and %lu Working Core values. SpringBoard will now restart.", (unsigned long)nextAuraCount, (unsigned long)coreCount];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Reset Complete" message:message preferredStyle:UIAlertControllerStyleAlert];
        [(UIViewController *)self presentViewController:done animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NARespring(); });
    }]];
    [(UIViewController *)self presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor)) static void NextAuraSTCoreLoaderInit(void) {
    @autoreleasepool {
        Class controller = NSClassFromString(@"PSListController");
        if (!controller) return;
        class_addMethod(controller, NSSelectorFromString(@"openNextAuraWorkingCore:"), (IMP)NAOpenWorkingCore, "v@:@");
        class_addMethod(controller, NSSelectorFromString(@"resetAllUnifiedSettings:"), (IMP)NAResetUnifiedSettings, "v@:@");
    }
}
