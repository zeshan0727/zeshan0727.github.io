#import <UIKit/UIKit.h>
#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"

static NSString *PA415BridgeCleanNumber(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        NSString *character = [value substringWithRange:NSMakeRange(index, 1)];
        if ([character rangeOfCharacterFromSet:allowed].location != NSNotFound) [clean appendString:character];
    }
    return clean;
}

static PAStudioKeypadView *PA415FindKeypad(UIView *root) {
    if (!root) return nil;
    Class keypadClass = NSClassFromString(@"PAStudioKeypadView");
    if (keypadClass && [root isKindOfClass:keypadClass]) return (PAStudioKeypadView *)root;
    for (UIView *subview in root.subviews) {
        PAStudioKeypadView *found = PA415FindKeypad(subview);
        if (found) return found;
    }
    return nil;
}

@interface PAStudioKeypadView (PA415Private)
@property(nonatomic,copy) NSString *dialValue;
- (void)updateNumberDisplay;
@end

@implementation PAStudioKeypadView (PAKeypadPasteBridgeV415)

- (void)setDialNumber:(NSString *)number {
    self.dialValue = PA415BridgeCleanNumber(number);
    [self updateNumberDisplay];
}

@end

@implementation PhoneAuraManager (PAKeypadPasteBridgeV415)

- (void)pasteNumberIntoKeypad:(NSString *)number {
    NSString *clean = PA415BridgeCleanNumber(number);
    if (!clean.length) return;

    UITabBarController *tabController = nil;
    @try { tabController = [self valueForKey:@"tabController"]; }
    @catch (__unused NSException *exception) { }
    if (!tabController) return;

    tabController.selectedIndex = 3;
    [self tabSelectionChanged:tabController];

    __weak UITabBarController *weakTab = tabController;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UITabBarController *strongTab = weakTab;
        PAStudioKeypadView *keypad = PA415FindKeypad(strongTab.view);
        if (keypad) [keypad setDialNumber:clean];
    });
}

@end
