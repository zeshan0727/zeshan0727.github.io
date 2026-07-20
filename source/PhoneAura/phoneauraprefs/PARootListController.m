#import "PARootListController.h"
#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>
#import <signal.h>

extern char **environ;

static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PANotification = @"com.zeshan.phoneaura/preferences.changed";

@implementation PARootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoneAura";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 142)];
    header.backgroundColor = UIColor.clearColor;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(id)[UIColor colorWithRed:1.0 green:0.35 blue:0.37 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.42 green:0.38 blue:1.0 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.05 green:0.78 blue:0.72 alpha:1].CGColor];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1, 0.5);
    gradient.frame = CGRectMake(18, 14, UIScreen.mainScreen.bounds.size.width - 54, 108);
    gradient.cornerRadius = 24;
    gradient.shadowColor = UIColor.blackColor.CGColor;
    gradient.shadowOpacity = 0.24;
    gradient.shadowRadius = 16;
    gradient.shadowOffset = CGSizeMake(0, 8);
    [header.layer addSublayer:gradient];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(38, 31, UIScreen.mainScreen.bounds.size.width - 120, 38)];
    title.text = @"PhoneAura";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:31 weight:UIFontWeightBold];
    [header addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(39, 71, UIScreen.mainScreen.bounds.size.width - 120, 25)];
    subtitle.text = @"Bold Card Studio · Concept D";
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    subtitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [header addSubview:subtitle];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(UIScreen.mainScreen.bounds.size.width - 102, 42, 46, 46)];
    icon.image = [UIImage systemImageNamed:@"phone.fill"];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [header addSubview:icon];

    self.table.tableHeaderView = header;
}

- (void)resetPreferences {
    NSArray *keys = @[@"enabled", @"haptics", @"animations", @"forceDark",
                      @"showSubtitles", @"showShortcuts", @"styleKeypad",
                      @"cardOpacity", @"cornerRadius"];
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

- (void)restartPhoneApp {
    pid_t pid;
    const char *args[] = {"killall", "-9", "MobilePhone", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)args, environ);
}

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/zeshan0727"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
