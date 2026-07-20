#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

void PAApplyFullSurfaceFixes(UIViewController *controller);
void PARefreshFullSurfaceForTabController(UITabBarController *tabController);
void PARestoreFullSurfaceFixes(UIViewController *controller);

#ifdef __cplusplus
}
#endif
