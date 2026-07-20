#import "AppDelegate.h"
#import "StudioViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    StudioViewController *studio = [[StudioViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:studio];
    navigation.navigationBar.prefersLargeTitles = NO;
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
