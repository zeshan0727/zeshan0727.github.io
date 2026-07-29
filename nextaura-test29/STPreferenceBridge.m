#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const NADestinationDomain = @"com.nextsolution.unlockvibrate";
static CFStringRef const NAReloadNotification = CFSTR("com.nextsolution.unlockvibrate/preferences.changed");

static NSArray<NSString *> *NASourceDomains(void) {
    static NSArray<NSString *> *domains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        domains = @[
            @"com.st5.settings",
            @"com.st5.settings.animations",
            @"com.st5.settings.appswitcher",
            @"com.st5.settings.controlCenter",
            @"com.st5.settings.dock",
            @"com.st5.settings.dockList",
            @"com.st5.settings.folderList",
            @"com.st5.settings.folders",
            @"com.st5.settings.icons",
            @"com.st5.settings.lockscreen",
            @"com.st5.settings.misc",
            @"com.st5.settings.notificationCenter",
            @"com.st5.settings.pages",
            @"com.st5.settings.pagesList",
            @"com.st5.settings.statusbar"
        ];
    });
    return domains;
}

static id NACopyValue(NSString *domain, NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)domain);
    return CFBridgingRelease(value);
}

static id NAFirstValue(NSArray<NSString *> *domains, NSString *key) {
    for (NSString *domain in domains) {
        id value = NACopyValue(domain, key);
        if (value) return value;
    }
    return nil;
}

static void NASetValue(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)NADestinationDomain);
}

static void NAMap(NSString *domain, NSString *sourceKey, NSString *destinationKey) {
    id value = NACopyValue(domain, sourceKey);
    if (value) NASetValue(destinationKey, value);
}

static void NAMapOneToMany(NSString *domain, NSString *sourceKey, NSArray<NSString *> *destinationKeys) {
    id value = NACopyValue(domain, sourceKey);
    if (!value) return;
    for (NSString *destinationKey in destinationKeys) NASetValue(destinationKey, value);
}

static NSNumber *NAClampedScale(id rawValue, double minimum, double maximum) {
    if (![rawValue respondsToSelector:@selector(doubleValue)]) return nil;
    double value = [rawValue doubleValue];
    if (value > 10.0) value /= 100.0;
    if (value <= 0.0) value = 1.0;
    value = MAX(minimum, MIN(maximum, value));
    return @(value);
}

static void NAMapScale(NSString *domain,
                       NSString *enabledKey,
                       NSString *valueKey,
                       NSString *destinationKey,
                       double minimum,
                       double maximum) {
    id enabled = NACopyValue(domain, enabledKey);
    if (enabled && ![enabled boolValue]) {
        NASetValue(destinationKey, @1.0);
        return;
    }
    NSNumber *scale = NAClampedScale(NACopyValue(domain, valueKey), minimum, maximum);
    if (scale) NASetValue(destinationKey, scale);
}

static void NASynchronisePreferences(void) {
    @autoreleasepool {
        // Animations
        id customSpeedEnabled = NACopyValue(@"com.st5.settings.animations", @"kCustomSpeed");
        if (!customSpeedEnabled || [customSpeedEnabled boolValue]) {
            id speed = NACopyValue(@"com.st5.settings.animations", @"kAnimationSpeed");
            if (!speed) speed = NACopyValue(@"com.st5.settings.animations", @"kCustomSpeed");
            if ([speed respondsToSelector:@selector(doubleValue)]) {
                double value = [speed doubleValue];
                if (value > 0.0) NASetValue(@"AnimationSpeed", @(MAX(0.15, MIN(3.0, value))));
            }
        }

        // App Switcher
        NSString *switcher = @"com.st5.settings.appswitcher";
        NAMapOneToMany(switcher, @"kHideIcons", @[@"LabHideSwitcherAppIcons", @"LabHideSwitcherAppLabels"]);
        NAMap(switcher, @"kCornerRadius", @"LabSwitcherCornerRadius");
        NAMap(switcher, @"kHideSuggestions", @"LabHideSwitcherDismissHints");
        NAMapScale(switcher, @"kResize", @"kResizeSize", @"LabSwitcherCardScale", 0.45, 1.30);

        // Control Center
        NSString *controlCenter = @"com.st5.settings.controlCenter";
        NAMap(controlCenter, @"kDisableBlur", @"LabHideStockCCBackgroundBlur");
        id disableCC = NACopyValue(controlCenter, @"kDisableCC");
        if ([disableCC boolValue]) NASetValue(@"LabStockCCBackgroundOpacity", @0.0);

        // Dock
        NSString *dock = @"com.st5.settings.dock";
        NAMap(dock, @"kHideBackground", @"HideDockBackground");
        NAMapOneToMany(dock, @"kHideLabels", @[@"HideHomeLabels"]);
        NAMap(dock, @"kHideBadges", @"HideBadges");
        NAMapScale(dock, @"kResize", @"kResizeSize", @"DockIconScale", 0.45, 1.60);
        id hideDock = NACopyValue(dock, @"kHideDock");
        if (hideDock) NASetValue(@"LabDockOverallOpacity", [hideDock boolValue] ? @0.0 : @1.0);

        // Folders
        NSString *folders = @"com.st5.settings.folders";
        NAMap(folders, @"kHideLabels", @"HideFolderLabels");
        NAMap(folders, @"kHideBadges", @"HideBadges");
        NAMap(folders, @"kHideTitle", @"HideFolderTitle");
        NAMapOneToMany(folders, @"kHideBackground", @[@"HideFolderBackground"]);
        NAMapOneToMany(folders, @"kHideBlurBackground", @[@"HideFolderBackground"]);
        NAMapOneToMany(folders, @"kHideGrid", @[@"HideFolderIconBackground"]);
        id squared = NACopyValue(folders, @"kSquaredFolderBackground");
        if ([squared boolValue]) NASetValue(@"LabFolderIconCornerRadius", @0.0);
        NAMapScale(folders, @"kResize", @"kResizeSize", @"LabFolderIconScale", 0.45, 1.60);

        // Icons and Home Screen
        NSString *icons = @"com.st5.settings.icons";
        NAMap(icons, @"kHideLabels", @"HideHomeLabels");
        NAMap(icons, @"kHideBadges", @"HideBadges");
        NAMapOneToMany(icons, @"kDisableWiggling", @[@"HideWiggleDeleteButtons", @"HideWiggleDoneButton"]);
        NAMap(icons, @"kDisableUninstall", @"HideWiggleDeleteButtons");
        NAMapOneToMany(icons, @"kHideUpdatedDot", @[@"LabHideRecentlyDownloadedDot"]);
        NAMapOneToMany(icons, @"kHideInstalledDot", @[@"LabHideRecentlyDownloadedDot"]);
        NAMapOneToMany(icons, @"kHideBetaDot", @[@"LabHideRecentlyDownloadedDot"]);
        NAMap(icons, @"kImageTransparency", @"HomeIconOpacity");
        NAMapScale(icons, @"kResize", @"kResizeSize", @"HomeIconScale", 0.45, 1.60);

        // Lock Screen
        NSString *lockscreen = @"com.st5.settings.lockscreen";
        NAMap(lockscreen, @"kHideDate", @"HideLockDate");
        NAMap(lockscreen, @"kPreventFlashlightAccess", @"HideFlashlight");
        NAMap(lockscreen, @"kPreventCameraAccess", @"HideCamera");
        NAMap(lockscreen, @"kHideCCGrabber", @"HideControlCenterGrabber");
        NAMapOneToMany(lockscreen, @"kHideGrabber", @[@"HideSwipeHint", @"LabHideLockBottomGrabber"]);
        NAMap(lockscreen, @"kHideFaceIDLock", @"HideLockGlyph");
        NAMap(lockscreen, @"kTimeFontSize", @"NALockTimeSize");
        NAMap(lockscreen, @"kDateFontSize", @"NALockDateSize");
        NAMap(lockscreen, @"kTimeHidden", @"HideLockDate");
        NAMap(lockscreen, @"kDisableLargeBattery", @"HideChargingText");

        // Notification Center / lock-screen notification equivalents
        NSString *notificationCenter = @"com.st5.settings.notificationCenter";
        NAMap(notificationCenter, @"kDisableDNDNotification", @"LabHideLockFocusText");
        NAMap(notificationCenter, @"kHideEditButton", @"LabHideNotificationChevron");
        id blurStrength = NACopyValue(notificationCenter, @"kBlurStrength");
        if ([blurStrength respondsToSelector:@selector(doubleValue)]) {
            double opacity = 1.0 - MAX(0.0, MIN(1.0, [blurStrength doubleValue]));
            NASetValue(@"LabNotificationBackgroundOpacity", @(opacity));
        }

        // Pages / Home Screen
        NSString *pages = @"com.st5.settings.pages";
        NAMap(pages, @"kHideDots", @"HidePageDots");
        NAMap(pages, @"kDisableSearch", @"HideSearchPill");
        NAMap(pages, @"kDisableSpotlight", @"DisableAppLibrarySwipe");
        NAMap(pages, @"kHideContextMenuBlur", @"LabHideHomeEditingBackground");
        NAMapOneToMany(pages, @"kHideHomeBar", @[@"HideLockHomeIndicator", @"HideCCHomeIndicator"]);
        NAMap(pages, @"kDisableHSStatusBar", @"HideStatusBarTime");

        // Status Bar
        NSString *statusbar = @"com.st5.settings.statusbar";
        NAMap(statusbar, @"kTimeHidden", @"HideStatusBarTime");
        NAMap(statusbar, @"kBatteryImageHidden", @"HideStatusBarBatteryIcon");
        NAMap(statusbar, @"kBatteryPercentageHidden", @"HideStatusBarBatteryPercent");
        NAMap(statusbar, @"kSignalStrengthHidden", @"HideStatusBarCellular");
        NAMap(statusbar, @"kCarrierHidden", @"HideStatusBarCellular");
        NAMap(statusbar, @"kLocationHidden", @"HideStatusBarLocation");
        NAMap(statusbar, @"kAlarmHidden", @"HideStatusBarAlarm");
        NAMap(statusbar, @"kVPNHidden", @"HideStatusBarVPN");
        NAMap(statusbar, @"kAirplaneHidden", @"LabHideAirplaneIndicator");
        NAMap(statusbar, @"kBluetoothSignalHidden", @"LabHideBluetoothIndicator");
        NAMap(statusbar, @"kNetworkActivityHidden", @"HideStatusBarActivity");

        // Miscellaneous / overlays
        NSString *misc = @"com.st5.settings.misc";
        NAMap(misc, @"kDisableScreenshotSound", @"LabDisableScreenshotFlash");

        CFPreferencesAppSynchronize((__bridge CFStringRef)NADestinationDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             NAReloadNotification,
                                             NULL,
                                             NULL,
                                             true);
    }
}

static void NAExternalPreferencesChanged(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{ NASynchronisePreferences(); });
}

__attribute__((constructor)) static void NextAuraNativePreferenceBridgeInit(void) {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if (![process isEqualToString:@"SpringBoard"]) return;

        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        NSArray<NSString *> *notifications = @[
            @"com.springtomize.st4.reload",
            @"com.springtomize.st5",
            @"com.st5.settings.changed"
        ];
        for (NSString *notification in notifications) {
            CFNotificationCenterAddObserver(darwin,
                                            NULL,
                                            NAExternalPreferencesChanged,
                                            (__bridge CFStringRef)notification,
                                            NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ NASynchronisePreferences(); });
    }
}
