#import "PAStudioRootController.h"
#import <ContactsUI/ContactsUI.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <spawn.h>

extern char **environ;
static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PANotification = @"com.zeshan.phoneaura/preferences.changed";
static const void *PAControlKey = &PAControlKey;

@interface PAStudioRootController () <CNContactPickerDelegate>
@property(nonatomic,strong) NSArray<NSString *> *favoriteIdentifiers;
@end

@implementation PAStudioRootController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoneAura Studio";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.035 blue:0.09 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.favoriteIdentifiers = [self arrayPreference:@"favoriteIdentifiers"] ?: @[];
    [self buildHeader];
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 190)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 18, UIScreen.mainScreen.bounds.size.width - 32, 150)];
    card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    [header addSubview:card];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = card.bounds;
    gradient.colors = @[(id)[UIColor colorWithRed:1.0 green:0.34 blue:0.37 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.43 green:0.38 blue:1.0 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.04 green:0.74 blue:0.72 alpha:1].CGColor];
    gradient.startPoint = CGPointMake(0, 0.15);
    gradient.endPoint = CGPointMake(1, 0.85);
    [card.layer addSublayer:gradient];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(22, 24, CGRectGetWidth(card.bounds)-92, 40)];
    title.text = @"Bold Card Studio";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:29 weight:UIFontWeightBold];
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(23, 67, CGRectGetWidth(card.bounds)-46, 52)];
    subtitle.text = @"Full custom Phone surfaces\nRootHide · iOS 16";
    subtitle.numberOfLines = 2;
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.86];
    subtitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:subtitle];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(CGRectGetWidth(card.bounds)-72, 23, 46, 46)];
    icon.image = [UIImage systemImageNamed:@"phone.fill"];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:icon];
    self.tableView.tableHeaderView = header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 5;
        case 1: return 2;
        case 2: return 3;
        case 3: return 1;
        case 4: return 3;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"CUSTOM SURFACES", @"APPEARANCE", @"BEHAVIOR", @"FAVORITE CONTACTS", @"TOOLS"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Each enabled surface completely covers Apple’s old root screen. Disable a surface to use the stock version for that tab.";
    if (section == 3) return @"Selected contacts appear as the large coral hero card and smaller Concept D favorite cards.";
    return nil;
}

- (UITableViewCell *)switchCell:(NSString *)title key:(NSString *)key defaultValue:(BOOL)fallback {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.onTintColor = [UIColor colorWithRed:1 green:0.35 blue:0.38 alpha:1];
    toggle.on = [self boolPreference:key fallback:fallback];
    objc_setAssociatedObject(toggle, PAControlKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)sliderCell:(NSString *)title key:(NSString *)key value:(CGFloat)value min:(CGFloat)minimum max:(CGFloat)maximum {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 155, 34)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = value;
    slider.minimumTrackTintColor = [UIColor colorWithRed:0.43 green:0.38 blue:1 alpha:1];
    objc_setAssociatedObject(slider, PAControlKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = slider;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", value];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSArray *titles = @[@"Enable PhoneAura", @"Replace Favorites Completely", @"Replace Recents Completely", @"Replace Contacts Completely", @"Replace Keypad Completely"];
        NSArray *keys = @[@"enabled", @"fullFavorites", @"fullRecents", @"fullContacts", @"fullKeypad"];
        return [self switchCell:titles[indexPath.row] key:keys[indexPath.row] defaultValue:YES];
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return [self sliderCell:@"Card Opacity" key:@"cardOpacity" value:[self floatPreference:@"cardOpacity" fallback:0.96] min:0.65 max:1.0];
        return [self sliderCell:@"Corner Radius" key:@"cornerRadius" value:[self floatPreference:@"cornerRadius" fallback:16] min:10 max:26];
    }
    if (indexPath.section == 2) {
        NSArray *titles = @[@"Header Subtitles", @"Haptic Feedback", @"Fluid Animations"];
        NSArray *keys = @[@"showSubtitles", @"haptics", @"animations"];
        return [self switchCell:titles[indexPath.row] key:keys[indexPath.row] defaultValue:YES];
    }
    if (indexPath.section == 3) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"Choose Favorite Contacts";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu selected · maximum 4 displayed", (unsigned long)self.favoriteIdentifiers.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @[@"Restart Phone App", @"Open Phone App", @"Reset PhoneAura Settings"][indexPath.row];
    cell.textLabel.textColor = indexPath.row == 2 ? UIColor.systemRedColor : UIColor.labelColor;
    cell.accessoryType = indexPath.row == 1 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        CNContactPickerViewController *picker = [[CNContactPickerViewController alloc] init];
        picker.delegate = self;
        picker.predicateForEnablingContact = [NSPredicate predicateWithFormat:@"phoneNumbers.@count > 0"];
        [self presentViewController:picker animated:YES completion:nil];
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) [self restartPhone];
        else if (indexPath.row == 1) {
            NSURL *url = [NSURL URLWithString:@"mobilephone://"];
            if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        } else [self resetSettings];
    }
}

- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContacts:(NSArray<CNContact *> *)contacts {
    NSMutableArray *identifiers = [NSMutableArray array];
    for (CNContact *contact in contacts) {
        if (contact.identifier.length) [identifiers addObject:contact.identifier];
    }
    self.favoriteIdentifiers = identifiers;
    [self writeValue:identifiers key:@"favoriteIdentifiers"];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, PAControlKey);
    [self writeValue:@(sender.on) key:key];
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = objc_getAssociatedObject(sender, PAControlKey);
    [self writeValue:@(sender.value) key:key];
    UITableViewCell *cell = (UITableViewCell *)sender.superview;
    while (cell && ![cell isKindOfClass:[UITableViewCell class]]) cell = (UITableViewCell *)cell.superview;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", sender.value];
}

- (id)preference:(NSString *)key {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PADomain));
}
- (BOOL)boolPreference:(NSString *)key fallback:(BOOL)fallback { id value = [self preference:key]; return value ? [value boolValue] : fallback; }
- (CGFloat)floatPreference:(NSString *)key fallback:(CGFloat)fallback { id value = [self preference:key]; return value ? [value doubleValue] : fallback; }
- (NSArray *)arrayPreference:(NSString *)key { id value = [self preference:key]; return [value isKindOfClass:[NSArray class]] ? value : nil; }

- (void)writeValue:(id)value key:(NSString *)key {
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)PADomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PANotification, NULL, NULL, true);
}

- (void)restartPhone {
    pid_t pid = 0;
    const char *arguments[] = {"killall", "-9", "MobilePhone", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)arguments, environ);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Phone App Restarted" message:@"Open Phone to load the latest layout." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
    NSArray *keys = @[@"enabled", @"fullFavorites", @"fullRecents", @"fullContacts", @"fullKeypad", @"cardOpacity", @"cornerRadius", @"showSubtitles", @"haptics", @"animations", @"favoriteIdentifiers"];
    for (NSString *key in keys) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)PADomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PANotification, NULL, NULL, true);
    self.favoriteIdentifiers = @[];
    [self.tableView reloadData];
}

@end
