#import "PARootListController.h"
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>

static void PA47UpdateLabels(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if ([label.text hasPrefix:@"PhoneAura 0.4."]) {
            label.text = @"PhoneAura 0.4.7";
        } else if ([label.text containsString:@"Opaque stage"] ||
                   [label.text containsString:@"Concept D roots"]) {
            label.text = @"Test build · call filters · safe deletion";
        }
    }
    for (UIView *subview in view.subviews) PA47UpdateLabels(subview);
}

@interface PARootListController (PhoneAuraVersionV47)
- (NSArray *)pa47_specifiers;
- (void)pa47_viewDidLoad;
@end

@implementation PARootListController (PhoneAuraVersionV47)

- (NSArray *)pa47_specifiers {
    NSArray *specifiers = [self pa47_specifiers];
    PSSpecifier *first = specifiers.firstObject;
    if (first) {
        [first setName:@"PHONEAURA 0.4.7 TEST"];
        [first setProperty:@"This package is a private test build. It adds four Recents filters, call details, call-history deletion, contact deletion and loading optimizations. The live Sileo repository remains on the approved stable release until testing is completed."
                   forKey:@"footerText"];
    }
    return specifiers;
}

- (void)pa47_viewDidLoad {
    [self pa47_viewDidLoad];
    PA47UpdateLabels(self.view);
    PA47UpdateLabels(self.table.tableHeaderView);
}

@end

static void PA47PreferenceExchange(Class cls, SEL original, SEL replacement) {
    Method first = class_getInstanceMethod(cls, original);
    Method second = class_getInstanceMethod(cls, replacement);
    if (first && second) method_exchangeImplementations(first, second);
}

__attribute__((constructor)) static void PA47InstallPreferenceVersion(void) {
    Class cls = NSClassFromString(@"PARootListController");
    if (!cls) return;
    PA47PreferenceExchange(cls, @selector(specifiers), @selector(pa47_specifiers));
    PA47PreferenceExchange(cls, @selector(viewDidLoad), @selector(pa47_viewDidLoad));
}
