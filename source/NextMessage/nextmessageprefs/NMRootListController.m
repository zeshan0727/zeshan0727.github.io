#import "NMRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static NSString * const NMDomain = @"com.nextsolution.nextmessage";
static NSString * const NMNotification = @"com.nextsolution.nextmessage/preferences.changed";
static NSString * const NMRepoURL = @"https://zeshan0727.github.io/";

@implementation NMRootListController

- (NSString *)preferencesPath {
    return @"/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist";
}

- (NSMutableDictionary *)diskPreferences {
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:[self preferencesPath]];
    return dictionary ? [dictionary mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)writeDiskPreferences:(NSDictionary *)dictionary {
    NSString *path = [self preferencesPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [dictionary writeToFile:path atomically:YES];
}

- (PSSpecifier *)groupNamed:(NSString *)name {
    return [PSSpecifier groupSpecifierWithName:name];
}

- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)defaultValue {
    PSSpecifier *specifier =
        [PSSpecifier preferenceSpecifierNamed:name
                                       target:self
                                          set:@selector(setPreferenceValue:specifier:)
                                          get:@selector(readPreferenceValue:)
                                       detail:nil
                                         cell:PSSwitchCell
                                         edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];
    return specifier;
}

- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action destructive:(BOOL)destructive {
    PSSpecifier *specifier =
        [PSSpecifier preferenceSpecifierNamed:name
                                       target:self
                                          set:nil
                                          get:nil
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    [specifier setButtonAction:action];
    if (destructive) [specifier setProperty:@YES forKey:@"isDestructive"];
    return specifier;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[self groupNamed:@"NEXT MESSAGE"]];
    [items addObject:[self switchNamed:@"Enable Next Message" key:@"enabled" defaultValue:YES]];

    [items addObject:[self groupNamed:@"FLOATING APP INFORMATION"]];
    [items addObject:[self switchNamed:@"Show Floating Information Button" key:@"floatingInfoButton" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Haptic Feedback" key:@"haptics" defaultValue:YES]];

    [items addObject:[self groupNamed:@"ACTIONS"]];
    [items addObject:[self buttonNamed:@"Apply and Restart Messages" action:@selector(restartMessagesApp) destructive:NO]];
    [items addObject:[self buttonNamed:@"Reset Next Message Settings" action:@selector(resetPreferences) destructive:YES]];

    [items addObject:[self groupNamed:@"CREDITS & MORE"]];
    [items addObject:[self buttonNamed:@"Know more about other tweaks" action:@selector(openSileoRepo) destructive:NO]];

    _specifiers = [items copy];
    return _specifiers;
}

- (UIImage *)nextSolutionLogo {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:@"icon" ofType:@"png"];
    UIImage *image = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
    return image ?: [UIImage systemImageNamed:@"message.fill"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Next Message";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 178)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 16, screenWidth - 48, 142)];
    card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    [header addSubview:card];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:1.0 green:0.32 blue:0.37 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.43 green:0.37 blue:1.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.04 green:0.80 blue:0.72 alpha:1].CGColor
    ];
    gradient.startPoint = CGPointMake(0, 0.25);
    gradient.endPoint = CGPointMake(1, 0.8);
    gradient.frame = card.bounds;
    [card.layer insertSublayer:gradient atIndex:0];

    UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake(20, 24, 74, 74)];
    logo.image = [self nextSolutionLogo];
    logo.contentMode = UIViewContentModeScaleAspectFill;
    logo.clipsToBounds = YES;
    logo.layer.cornerRadius = 18;
    logo.layer.borderWidth = 2;
    logo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.65].CGColor;
    [card addSubview:logo];

    UILabel *brand = [[UILabel alloc] initWithFrame:CGRectMake(110, 24, CGRectGetWidth(card.bounds)-128, 36)];
    brand.text = @"Next Solution";
    brand.textColor = UIColor.whiteColor;
    brand.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    brand.adjustsFontSizeToFitWidth = YES;
    brand.minimumScaleFactor = 0.72;
    [card addSubview:brand];

    UILabel *product = [[UILabel alloc] initWithFrame:CGRectMake(111, 61, CGRectGetWidth(card.bounds)-128, 24)];
    product.text = @"Next Message 1.5.0 TEST";
    product.textColor = [UIColor colorWithWhite:1 alpha:0.90];
    product.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:product];

    UILabel *credits = [[UILabel alloc] initWithFrame:CGRectMake(111, 88, CGRectGetWidth(card.bounds)-128, 22)];
    credits.text = @"Credits: zeshan0727";
    credits.textColor = [UIColor colorWithWhite:1 alpha:0.80];
    credits.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [card addSubview:credits];
    self.table.tableHeaderView = header;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return nil;
    NSDictionary *dictionary = [self diskPreferences];
    id value = dictionary[key];
    if (value) return value;
    CFPropertyListRef shared = CFPreferencesCopyValue((__bridge CFStringRef)key,
                                                      (__bridge CFStringRef)NMDomain,
                                                      kCFPreferencesCurrentUser,
                                                      kCFPreferencesAnyHost);
    if (shared) return CFBridgingRelease(shared);
    return [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    NSMutableDictionary *dictionary = [self diskPreferences];
    if (value) dictionary[key] = value;
    else [dictionary removeObjectForKey:key];
    [self writeDiskPreferences:dictionary];

    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          (__bridge CFStringRef)NMDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)NMDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)NMNotification,
                                         NULL, NULL, true);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restartMessagesApp) object:nil];
    [self performSelector:@selector(restartMessagesApp) withObject:nil afterDelay:0.30];
}

- (void)openSileoRepo {
    NSURL *sileoURL = [NSURL URLWithString:[NSString stringWithFormat:@"sileo://source/%@", NMRepoURL]];
    NSURL *webURL = [NSURL URLWithString:NMRepoURL];
    [[UIApplication sharedApplication] openURL:sileoURL options:@{} completionHandler:^(BOOL success) {
        if (!success && webURL) [[UIApplication sharedApplication] openURL:webURL options:@{} completionHandler:nil];
    }];
}

- (void)resetPreferences {
    NSDictionary *defaults = @{@"enabled": @YES, @"floatingInfoButton": @YES, @"haptics": @YES};
    [self writeDiskPreferences:defaults];
    for (NSString *key in defaults) {
        CFPreferencesSetValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)defaults[key],
                              (__bridge CFStringRef)NMDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
    }
    CFPreferencesSynchronize((__bridge CFStringRef)NMDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)NMNotification,
                                         NULL, NULL, true);
    _specifiers = nil;
    [self reloadSpecifiers];
    [self restartMessagesApp];
}

- (void)restartMessagesApp {
    const char *paths[] = {"/usr/bin/killall", "/var/jb/usr/bin/killall", "/bootstrap/usr/bin/killall"};
    for (NSUInteger index = 0; index < sizeof(paths)/sizeof(paths[0]); index++) {
        if (access(paths[index], X_OK) == 0) {
            pid_t pid = 0;
            const char *arguments[] = {paths[index], "-9", "MobileSMS", NULL};
            posix_spawn(&pid, paths[index], NULL, NULL, (char * const *)arguments, environ);
            return;
        }
    }
    pid_t pid = 0;
    const char *arguments[] = {"killall", "-9", "MobileSMS", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)arguments, environ);
}

@end
