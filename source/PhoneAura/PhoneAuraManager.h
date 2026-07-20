#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

static void PASettingsChangedV4(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef _Nullable userInfo);

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
