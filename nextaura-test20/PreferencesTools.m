#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const NADomain = @"com.nextsolution.unlockvibrate";
static NSString * const NAPrefsBundlePath = @"/Library/PreferenceBundles/UnlockVibratePrefs.bundle";
static NSString * const NACCBackgroundPath = @"/var/mobile/Library/NextSolutionTweaks/CCBackgrounds";

static NSBundle *NAPreferencesBundle(void) {
    for (NSBundle *bundle in [NSBundle allBundles]) {
        if ([[bundle bundleIdentifier] isEqualToString:@"com.nextsolution.unlockvibrateprefs"]) return bundle;
    }
    return [NSBundle bundleWithPath:NAPrefsBundlePath];
}

static id NASpecifierProperty(id specifier, NSString *key) {
    if (!specifier || !key) return nil;
    SEL propertySelector = NSSelectorFromString(@"propertyForKey:");
    if ([specifier respondsToSelector:propertySelector]) {
        id (*send)(id, SEL, id) = (void *)objc_msgSend;
        id value = send(specifier, propertySelector, key);
        if (value) return value;
    }
    @try {
        NSDictionary *properties = [specifier valueForKey:@"properties"];
        return [properties objectForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray<NSDictionary *> *NAItemsForSection(NSString *section) {
    if (section.length == 0) return @[];
    NSString *path = [[NAPreferencesBundle() bundlePath] stringByAppendingPathComponent:[section stringByAppendingPathExtension:@"plist"]];
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:path];
    NSArray *items = [root objectForKey:@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

static NSArray<NSString *> *NASectionNames(void) {
    NSString *bundlePath = [NAPreferencesBundle() bundlePath];
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:nil];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSSet *excluded = [NSSet setWithArray:@[@"Info", @"RootV410", @"SafeLabKeys", @"SafetyRecovery"]];
    for (NSString *file in files) {
        if (![[file pathExtension] isEqualToString:@"plist"]) continue;
        NSString *name = [file stringByDeletingPathExtension];
        if ([excluded containsObject:name]) continue;
        NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:file]];
        if ([[root objectForKey:@"items"] isKindOfClass:[NSArray class]]) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSArray<NSString *> *NAKeysForItems(NSArray<NSDictionary *> *items) {
    NSMutableOrderedSet<NSString *> *keys = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *domain = [item objectForKey:@"defaults"];
        NSString *key = [item objectForKey:@"key"];
        if ([domain isEqualToString:NADomain] && [key isKindOfClass:[NSString class]] && key.length) [keys addObject:key];
    }
    return keys.array;
}

static NSArray<NSString *> *NAAllKnownKeys(void) {
    NSMutableOrderedSet<NSString *> *keys = [NSMutableOrderedSet orderedSet];
    for (NSString *section in NASectionNames()) [keys addObjectsFromArray:NAKeysForItems(NAItemsForSection(section))];
    return keys.array;
}

static void NASynchronise(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, NULL, true);
}

static void NARequestRespring(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/respring"), NULL, NULL, true);
}

static void NAReloadController(id controller) {
    SEL reload = NSSelectorFromString(@"reloadSpecifiers");
    if ([controller respondsToSelector:reload]) {
        void (*send)(id, SEL) = (void *)objc_msgSend;
        send(controller, reload);
    }
}

static UIViewController *NAPresenter(id controller) {
    if ([controller isKindOfClass:[UIViewController class]]) return controller;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

static void NAPresentMessage(id controller, NSString *title, NSString *message) {
    UIViewController *presenter = NAPresenter(controller);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void NAClearKeys(NSArray<NSString *> *keys) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:NADomain];
    for (NSString *key in keys) {
        [defaults removeObjectForKey:key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NADomain);
    }
    [defaults synchronize];
    NASynchronise();
}

static void NAResetSectionNow(id controller, NSString *section) {
    NSArray<NSString *> *keys = NAKeysForItems(NAItemsForSection(section));
    NAClearKeys(keys);
    if ([section isEqualToString:@"CCModuleBackgrounds"]) [[NSFileManager defaultManager] removeItemAtPath:NACCBackgroundPath error:nil];
    NAReloadController(controller);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NARequestRespring(); });
}

static void NAResetCurrentSection(id self, SEL _cmd, id specifier) {
    (void)_cmd;
    NSString *section = NASpecifierProperty(specifier, @"nextAuraSectionPlist");
    NSString *label = NASpecifierProperty(specifier, @"nextAuraSectionLabel");
    if (![section isKindOfClass:[NSString class]] || section.length == 0) {
        NAPresentMessage(self, @"Reset Unavailable", @"The section identifier is missing. No settings were changed.");
        return;
    }
    if (![label isKindOfClass:[NSString class]] || label.length == 0) label = section;
    UIViewController *presenter = NAPresenter(self);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Reset %@?", label]
                                                                   message:@"Only this section will return to its original defaults. SpringBoard will restart automatically."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset & Respring" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { NAResetSectionNow(self, section); }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void NAResetAllNow(id controller) {
    NSArray<NSString *> *knownKeys = NAAllKnownKeys();
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:NADomain];
    [defaults removePersistentDomainForName:NADomain];
    for (NSString *key in knownKeys) {
        [defaults removeObjectForKey:key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NADomain);
    }
    [defaults synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:NACCBackgroundPath error:nil];
    NASynchronise();
    NAReloadController(controller);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NARequestRespring(); });
}

static void NAResetAll(id self, SEL _cmd, id specifier) {
    (void)_cmd; (void)specifier;
    NSUInteger keyCount = NAAllKnownKeys().count;
    UIViewController *presenter = NAPresenter(self);
    NSString *message = [NSString stringWithFormat:@"This will remove all %lu saved NextAura values, delete copied Control Center background images, restore every section to its original defaults, and restart SpringBoard.", (unsigned long)keyCount];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset All NextAura Settings?" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset Everything" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { NAResetAllNow(self); }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static BOOL NAValueMatchesDefaultType(id value, id defaultValue) {
    if (!defaultValue || !value) return YES;
    if ([defaultValue isKindOfClass:[NSNumber class]]) return [value isKindOfClass:[NSNumber class]];
    if ([defaultValue isKindOfClass:[NSString class]]) return [value isKindOfClass:[NSString class]];
    if ([defaultValue isKindOfClass:[NSArray class]]) return [value isKindOfClass:[NSArray class]];
    if ([defaultValue isKindOfClass:[NSDictionary class]]) return [value isKindOfClass:[NSDictionary class]];
    return YES;
}

static NSUInteger NARepairPreferences(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:NADomain];
    NSUInteger repaired = 0;
    for (NSString *section in NASectionNames()) {
        for (NSDictionary *item in NAItemsForSection(section)) {
            NSString *key = [item objectForKey:@"key"];
            if (![key isKindOfClass:[NSString class]] || key.length == 0) continue;
            id value = [defaults objectForKey:key];
            if (!value) continue;
            id defaultValue = [item objectForKey:@"default"];
            if (!NAValueMatchesDefaultType(value, defaultValue)) { [defaults removeObjectForKey:key]; repaired++; continue; }
            NSArray *validValues = [item objectForKey:@"validValues"];
            if ([validValues isKindOfClass:[NSArray class]] && validValues.count && ![validValues containsObject:value]) { [defaults removeObjectForKey:key]; repaired++; continue; }
            if ([value isKindOfClass:[NSNumber class]]) {
                NSNumber *minimum = [item objectForKey:@"min"];
                NSNumber *maximum = [item objectForKey:@"max"];
                double number = [value doubleValue];
                double corrected = number;
                if ([minimum isKindOfClass:[NSNumber class]]) corrected = MAX(corrected, minimum.doubleValue);
                if ([maximum isKindOfClass:[NSNumber class]]) corrected = MIN(corrected, maximum.doubleValue);
                if (corrected != number) { [defaults setDouble:corrected forKey:key]; repaired++; }
            }
            if ([key hasSuffix:@"Font"] && [value isKindOfClass:[NSString class]]) {
                NSString *fontName = value;
                if (![fontName isEqualToString:@"__SYSTEM__"] && ![UIFont fontWithName:fontName size:12.0]) { [defaults setObject:@"__SYSTEM__" forKey:key]; repaired++; }
            }
        }
    }
    [defaults synchronize];
    if (repaired) NASynchronise();
    return repaired;
}

static void NARepair(id self, SEL _cmd, id specifier) {
    (void)_cmd; (void)specifier;
    NSUInteger repaired = NARepairPreferences();
    NAReloadController(self);
    NSString *message = repaired ? [NSString stringWithFormat:@"Repaired %lu invalid or unsupported value%@. Valid settings were preserved. Tap Apply Changes to restart SpringBoard.", (unsigned long)repaired, repaired == 1 ? @"" : @"s"] : @"All saved values are valid. Nothing was changed.";
    NAPresentMessage(self, repaired ? @"Repair Complete" : @"No Problems Found", message);
}

static void NAInstallMethods(void) {
    Class cls = NSClassFromString(@"PSListController");
    if (!cls) return;
    class_addMethod(cls, NSSelectorFromString(@"resetAllNextAuraSettings:"), (IMP)NAResetAll, "v@:@");
    class_addMethod(cls, NSSelectorFromString(@"resetCurrentNextAuraSection:"), (IMP)NAResetCurrentSection, "v@:@");
    class_addMethod(cls, NSSelectorFromString(@"repairNextAuraSettings:"), (IMP)NARepair, "v@:@");
}

__attribute__((constructor)) static void NextAuraPreferencesToolsInit(void) {
    @autoreleasepool {
        NAInstallMethods();
        dispatch_async(dispatch_get_main_queue(), ^{ NAInstallMethods(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NAInstallMethods(); });
    }
}
