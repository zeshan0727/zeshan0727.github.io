#import "NMCore.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const NMDomain = @"com.nextsolution.nextmessage";
NSString * const NMPreferencesChangedNotification = @"com.nextsolution.nextmessage/preferences.changed";

static NSDictionary *NMCachedPreferences = nil;

BOOL NMIsMessagesProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"];
}

UIColor *NMColor(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

static NSArray<NSString *> *NMPreferencePaths(void) {
    return @[
        @"/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
        @"/private/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist"
    ];
}

static NSDictionary *NMDiskPreferences(void) {
    for (NSString *path in NMPreferencePaths()) {
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dictionary isKindOfClass:NSDictionary.class] && dictionary.count) {
            return dictionary;
        }
    }
    return @{};
}

void NMReloadPreferences(void) {
    @synchronized([NSProcessInfo processInfo]) {
        NMCachedPreferences = [NMDiskPreferences() copy];
    }
}

id NMPreferenceObject(NSString *key) {
    if (!key.length) return nil;

    CFPropertyListRef shared =
        CFPreferencesCopyValue((__bridge CFStringRef)key,
                               (__bridge CFStringRef)NMDomain,
                               kCFPreferencesCurrentUser,
                               kCFPreferencesAnyHost);
    if (shared) return CFBridgingRelease(shared);

    @synchronized([NSProcessInfo processInfo]) {
        if (!NMCachedPreferences) NMCachedPreferences = [NMDiskPreferences() copy];
        return NMCachedPreferences[key];
    }
}

BOOL NMPreferenceBool(NSString *key, BOOL fallback) {
    id value = NMPreferenceObject(key);
    return value ? [value boolValue] : fallback;
}

CGFloat NMPreferenceFloat(NSString *key, CGFloat fallback) {
    id value = NMPreferenceObject(key);
    return value ? [value doubleValue] : fallback;
}

BOOL NMEnabled(void) {
    return NMPreferenceBool(@"enabled", YES);
}

UIViewController *NMControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

void NMHaptic(BOOL warning) {
    if (!NMPreferenceBool(@"haptics", YES)) return;
    if (warning) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeWarning];
    } else {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
}
