#import "PARootListController.h"
#import <Preferences/PSSpecifier.h>

static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PANotification = @"com.zeshan.phoneaura/preferences.changed";

@implementation PARootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)resetPreferences {
    NSArray *keys = @[@"enabled", @"haptics", @"animations", @"forceDark", @"accentStyle", @"glassIntensity"];
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)PADomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PANotification,
                                         NULL,
                                         NULL,
                                         true);
    [self reloadSpecifiers];
}

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/zeshan0727"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
