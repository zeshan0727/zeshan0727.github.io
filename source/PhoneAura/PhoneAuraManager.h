#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PhoneAuraManager : NSObject
+ (instancetype)sharedManager;
- (void)controllerDidAppear:(UIViewController *)controller;
- (void)tabSelectionChanged:(UITabBarController *)tabController;
- (void)tableViewDidLayout:(UITableView *)tableView;
- (void)reloadPreferences;
@end
NS_ASSUME_NONNULL_END
