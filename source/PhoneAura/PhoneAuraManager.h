#import <UIKit/UIKit.h>

static void PASettingsChangedV4(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo);

NS_ASSUME_NONNULL_BEGIN

@interface PhoneAuraManager : NSObject
+ (instancetype)sharedManager;
- (void)controllerDidAppear:(UIViewController *)controller;
- (void)controllerDidLayout:(UIViewController *)controller;
- (void)tabSelectionChanged:(UITabBarController *)tabController;
- (void)tableViewDidLayout:(UITableView *)tableView;
- (void)collectionViewDidLayout:(UICollectionView *)collectionView;
- (void)reloadPreferences;
@end

NS_ASSUME_NONNULL_END
