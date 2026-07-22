#import "NMRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>

extern char **environ;
static NSString * const NMDomain = @"com.nextsolution.nextmessage";
static NSString * const NMNotification = @"com.nextsolution.nextmessage/preferences.changed";
static NSString * const NMRepoURL = @"https://zeshan0727.github.io/";

@implementation NMRootListController

- (PSSpecifier *)group:(NSString *)name { return [PSSpecifier groupSpecifierWithName:name]; }
- (PSSpecifier *)toggle:(NSString *)name key:(NSString *)key value:(BOOL)value {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSwitchCell edit:nil];
    [s setProperty:key forKey:@"key"]; [s setProperty:@(value) forKey:@"default"]; return s;
}
- (PSSpecifier *)slider:(NSString *)name key:(NSString *)key value:(CGFloat)value min:(CGFloat)min max:(CGFloat)max {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setValue:specifier:) get:@selector(readValue:) detail:nil cell:PSSliderCell edit:nil];
    [s setProperty:key forKey:@"key"]; [s setProperty:@(value) forKey:@"default"]; [s setProperty:@(min) forKey:@"min"]; [s setProperty:@(max) forKey:@"max"]; [s setProperty:@YES forKey:@"showValue"]; return s;
}
- (PSSpecifier *)button:(NSString *)name action:(SEL)action destructive:(BOOL)destructive {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; [s setButtonAction:action]; if(destructive)[s setProperty:@YES forKey:@"isDestructive"]; return s;
}

- (NSArray *)specifiers {
    if(_specifiers)return _specifiers;
    NSMutableArray *a=[NSMutableArray array];
    [a addObject:[self group:@"NEXT MESSAGE"]];
    [a addObject:[self toggle:@"Enable Next Message" key:@"enabled" value:YES]];
    [a addObject:[self group:@"FULL PHONEAURA-STYLE DESIGN"]];
    [a addObject:[self toggle:@"Conversation Cards" key:@"conversationCards" value:YES]];
    [a addObject:[self toggle:@"Dark Glass Background" key:@"glassBackground" value:YES]];
    [a addObject:[self toggle:@"Styled Message Bubbles" key:@"bubbleStyling" value:YES]];
    [a addObject:[self toggle:@"Glass Message Input" key:@"inputStyling" value:YES]];
    [a addObject:[self slider:@"Card Opacity" key:@"cardOpacity" value:.96 min:.68 max:1.0]];
    [a addObject:[self slider:@"Corner Radius" key:@"cornerRadius" value:20 min:12 max:30]];
    [a addObject:[self group:@"CONVERSATION ACTIONS"]];
    [a addObject:[self toggle:@"Details Swipe Action" key:@"detailsSwipe" value:YES]];
    [a addObject:[self toggle:@"Show Message Count" key:@"showMessageCount" value:YES]];
    [a addObject:[self toggle:@"Show First Message Date" key:@"showFirstDate" value:YES]];
    [a addObject:[self toggle:@"Delete from Details Card" key:@"deleteFromCard" value:YES]];
    [a addObject:[self group:@"BEHAVIOR"]];
    [a addObject:[self toggle:@"Haptic Feedback" key:@"haptics" value:YES]];
    [a addObject:[self toggle:@"Fluid Animations" key:@"animations" value:YES]];
    [a addObject:[self button:@"Restart Messages App" action:@selector(restartMessages) destructive:NO]];
    [a addObject:[self button:@"Reset Next Message Settings" action:@selector(resetSettings) destructive:YES]];
    [a addObject:[self group:@"CREDITS & MORE"]];
    [a addObject:[self button:@"Know more about other tweaks" action:@selector(openRepo) destructive:NO]];
    _specifiers=[a copy]; return _specifiers;
}

- (UIImage *)logo {
    NSString *p=[[NSBundle bundleForClass:self.class] pathForResource:@"icon" ofType:@"png"];
    return p.length?[UIImage imageWithContentsOfFile:p]:[UIImage systemImageNamed:@"message.fill"];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Next Message"; self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    CGFloat sw=UIScreen.mainScreen.bounds.size.width; UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,0,178)]; UIView *card=[[UIView alloc]initWithFrame:CGRectMake(16,16,sw-48,142)]; card.layer.cornerRadius=26; card.layer.cornerCurve=kCACornerCurveContinuous; card.clipsToBounds=YES; [header addSubview:card];
    CAGradientLayer *g=[CAGradientLayer layer]; g.colors=@[(id)[UIColor colorWithRed:1 green:.35 blue:.37 alpha:1].CGColor,(id)[UIColor colorWithRed:.42 green:.38 blue:1 alpha:1].CGColor,(id)[UIColor colorWithRed:.05 green:.78 blue:.72 alpha:1].CGColor]; g.startPoint=CGPointMake(0,.25); g.endPoint=CGPointMake(1,.8); g.frame=card.bounds; [card.layer addSublayer:g];
    UIImageView *iv=[[UIImageView alloc]initWithFrame:CGRectMake(20,24,74,74)]; iv.image=[self logo]; iv.contentMode=UIViewContentModeScaleAspectFill; iv.clipsToBounds=YES; iv.layer.cornerRadius=18; iv.layer.borderWidth=2; iv.layer.borderColor=[UIColor colorWithWhite:1 alpha:.65].CGColor; [card addSubview:iv];
    UILabel *brand=[[UILabel alloc]initWithFrame:CGRectMake(110,24,CGRectGetWidth(card.bounds)-128,36)]; brand.text=@"Next Solution"; brand.textColor=UIColor.whiteColor; brand.font=[UIFont systemFontOfSize:26 weight:UIFontWeightBold]; [card addSubview:brand];
    UILabel *product=[[UILabel alloc]initWithFrame:CGRectMake(111,61,CGRectGetWidth(card.bounds)-128,24)]; product.text=@"Next Message 1.3.0 TEST"; product.textColor=[UIColor colorWithWhite:1 alpha:.88]; product.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; [card addSubview:product];
    UILabel *credits=[[UILabel alloc]initWithFrame:CGRectMake(111,88,CGRectGetWidth(card.bounds)-128,22)]; credits.text=@"Credits: zeshan0727"; credits.textColor=[UIColor colorWithWhite:1 alpha:.78]; credits.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; [card addSubview:credits]; self.table.tableHeaderView=header;
}

- (id)readValue:(PSSpecifier *)s {
    NSString *key=[s propertyForKey:@"key"]; NSUserDefaults *suite=[[NSUserDefaults alloc]initWithSuiteName:NMDomain]; id v=[suite objectForKey:key];
    if(!v){CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);v=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)NMDomain));}
    return v?:[s propertyForKey:@"default"];
}
- (void)setValue:(id)value specifier:(PSSpecifier *)s {
    NSString *key=[s propertyForKey:@"key"]; if(!key.length)return;
    NSUserDefaults *suite=[[NSUserDefaults alloc]initWithSuiteName:NMDomain]; [suite setObject:value forKey:key]; [suite synchronize];
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)NMDomain); CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)NMNotification,NULL,NULL,true);
}
- (void)resetSettings {
    NSArray *keys=@[@"enabled",@"conversationCards",@"glassBackground",@"bubbleStyling",@"inputStyling",@"cardOpacity",@"cornerRadius",@"detailsSwipe",@"showMessageCount",@"showFirstDate",@"deleteFromCard",@"haptics",@"animations"];
    NSUserDefaults *suite=[[NSUserDefaults alloc]initWithSuiteName:NMDomain]; for(NSString *key in keys){[suite removeObjectForKey:key];CFPreferencesSetAppValue((__bridge CFStringRef)key,NULL,(__bridge CFStringRef)NMDomain);} [suite synchronize]; CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)NMNotification,NULL,NULL,true); _specifiers=nil; [self reloadSpecifiers];
}
- (void)restartMessages { pid_t pid=0; const char *args[]={"killall","-9","MobileSMS",NULL}; posix_spawnp(&pid,"killall",NULL,NULL,(char * const *)args,environ); }
- (void)openRepo { NSURL *s=[NSURL URLWithString:[NSString stringWithFormat:@"sileo://source/%@",NMRepoURL]],*w=[NSURL URLWithString:NMRepoURL]; [[UIApplication sharedApplication]openURL:s options:@{} completionHandler:^(BOOL ok){if(!ok&&w)[[UIApplication sharedApplication]openURL:w options:@{} completionHandler:nil];}]; }
@end
