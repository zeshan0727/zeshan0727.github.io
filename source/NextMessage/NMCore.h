#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const NMDomain;
FOUNDATION_EXPORT NSString * const NMPreferencesChangedNotification;

BOOL NMIsMessagesProcess(void);
UIColor *NMColor(uint32_t hex, CGFloat alpha);

void NMReloadPreferences(void);
id NMPreferenceObject(NSString *key);
BOOL NMPreferenceBool(NSString *key, BOOL fallback);
CGFloat NMPreferenceFloat(NSString *key, CGFloat fallback);
BOOL NMEnabled(void);

UIViewController *NMControllerForView(UIView *view);
void NMHaptic(BOOL warning);
