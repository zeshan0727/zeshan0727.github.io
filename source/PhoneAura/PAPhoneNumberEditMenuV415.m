#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"

static const void *PA415MenuDelegateKey = &PA415MenuDelegateKey;
static const void *PA415LongPressKey = &PA415LongPressKey;

static NSString *PA415CleanPhoneNumber(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        NSString *character = [value substringWithRange:NSMakeRange(index, 1)];
        if ([character rangeOfCharacterFromSet:allowed].location != NSNotFound) [clean appendString:character];
    }
    return clean;
}

static BOOL PA415LooksLikePhoneNumber(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length < 5 || trimmed.length > 48) return NO;

    NSCharacterSet *validCharacters = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#-().  "];
    if ([trimmed rangeOfCharacterFromSet:validCharacters.invertedSet].location != NSNotFound) return NO;

    NSUInteger digitCount = 0;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        if ([NSCharacterSet.decimalDigitCharacterSet characterIsMember:[trimmed characterAtIndex:index]]) digitCount++;
    }
    return digitCount >= 5;
}

static PAStudioKeypadView *PA415KeypadAncestor(UIView *view) {
    UIView *cursor = view;
    Class keypadClass = NSClassFromString(@"PAStudioKeypadView");
    while (cursor) {
        if (keypadClass && [cursor isKindOfClass:keypadClass]) return (PAStudioKeypadView *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

@interface PA415PhoneNumberMenuDelegate : NSObject <UIEditMenuInteractionDelegate>
@property(nonatomic,weak) UILabel *label;
@property(nonatomic,weak) UIEditMenuInteraction *interaction;
- (void)showMenu:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation PA415PhoneNumberMenuDelegate

- (NSString *)currentNumber {
    NSString *text = self.label.text ?: self.label.attributedText.string ?: @"";
    return PA415CleanPhoneNumber(text);
}

- (void)copyNumber {
    NSString *number = [self currentNumber];
    if (number.length) UIPasteboard.generalPasteboard.string = number;
}

- (void)cutNumber {
    PAStudioKeypadView *keypad = PA415KeypadAncestor(self.label);
    if (!keypad) return;
    [self copyNumber];
    [keypad setDialNumber:@""];
}

- (void)pasteNumber {
    NSString *number = PA415CleanPhoneNumber(UIPasteboard.generalPasteboard.string ?: @"");
    if (!number.length) return;
    PAStudioKeypadView *keypad = PA415KeypadAncestor(self.label);
    if (keypad) [keypad setDialNumber:number];
    else [[PhoneAuraManager sharedManager] pasteNumberIntoKeypad:number];
}

- (void)showMenu:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || !self.label.window || !self.interaction) return;
    CGPoint point = [recognizer locationInView:self.label];
    UIEditMenuConfiguration *configuration = [UIEditMenuConfiguration configurationWithIdentifier:nil sourcePoint:point];
    [self.interaction presentEditMenuWithConfiguration:configuration];
}

- (UIMenu *)editMenuInteraction:(UIEditMenuInteraction *)interaction
            menuForConfiguration:(UIEditMenuConfiguration *)configuration
                suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions API_AVAILABLE(ios(16.0)) {
    __weak typeof(self) weakSelf = self;
    UIAction *cut = [UIAction actionWithTitle:@"Cut"
                                        image:[UIImage systemImageNamed:@"scissors"]
                                   identifier:nil
                                      handler:^(__kindof UIAction *action) { [weakSelf cutNumber]; }];
    if (!PA415KeypadAncestor(self.label)) cut.attributes = UIMenuElementAttributesDisabled;

    UIAction *copy = [UIAction actionWithTitle:@"Copy"
                                         image:[UIImage systemImageNamed:@"doc.on.doc"]
                                    identifier:nil
                                       handler:^(__kindof UIAction *action) { [weakSelf copyNumber]; }];

    NSString *clipboardNumber = PA415CleanPhoneNumber(UIPasteboard.generalPasteboard.string ?: @"");
    UIAction *paste = [UIAction actionWithTitle:@"Paste"
                                          image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *action) { [weakSelf pasteNumber]; }];
    if (!clipboardNumber.length) paste.attributes = UIMenuElementAttributesDisabled;

    return [UIMenu menuWithTitle:@"Phone Number" children:@[cut, copy, paste]];
}

- (CGRect)editMenuInteraction:(UIEditMenuInteraction *)interaction
 targetRectForConfiguration:(UIEditMenuConfiguration *)configuration API_AVAILABLE(ios(16.0)) {
    return self.label.bounds;
}

@end

@interface UILabel (PAPhoneNumberEditMenuV415)
- (void)pa415_setText:(NSString *)text;
- (void)pa415_setAttributedText:(NSAttributedString *)attributedText;
- (void)pa415_didMoveToWindow;
- (void)pa415_refreshPhoneNumberMenu;
@end

@implementation UILabel (PAPhoneNumberEditMenuV415)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSArray<NSString *> *> *pairs = @[
            @[@"setText:", @"pa415_setText:"],
            @[@"setAttributedText:", @"pa415_setAttributedText:"],
            @[@"didMoveToWindow", @"pa415_didMoveToWindow"]
        ];
        for (NSArray<NSString *> *pair in pairs) {
            Method original = class_getInstanceMethod(self, NSSelectorFromString(pair[0]));
            Method replacement = class_getInstanceMethod(self, NSSelectorFromString(pair[1]));
            if (original && replacement) method_exchangeImplementations(original, replacement);
        }
    });
}

- (void)pa415_setText:(NSString *)text {
    [self pa415_setText:text];
    [self pa415_refreshPhoneNumberMenu];
}

- (void)pa415_setAttributedText:(NSAttributedString *)attributedText {
    [self pa415_setAttributedText:attributedText];
    [self pa415_refreshPhoneNumberMenu];
}

- (void)pa415_didMoveToWindow {
    [self pa415_didMoveToWindow];
    [self pa415_refreshPhoneNumberMenu];
}

- (void)pa415_refreshPhoneNumberMenu {
    if (@available(iOS 16.0, *)) {
        NSString *value = self.text ?: self.attributedText.string ?: @"";
        BOOL shouldEnable = self.window && PA415LooksLikePhoneNumber(value);
        PA415PhoneNumberMenuDelegate *delegate = objc_getAssociatedObject(self, PA415MenuDelegateKey);
        UILongPressGestureRecognizer *longPress = objc_getAssociatedObject(self, PA415LongPressKey);

        if (!shouldEnable) {
            if (longPress) [self removeGestureRecognizer:longPress];
            if (delegate.interaction) [self removeInteraction:delegate.interaction];
            objc_setAssociatedObject(self, PA415LongPressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, PA415MenuDelegateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }

        if (!delegate) {
            delegate = [[PA415PhoneNumberMenuDelegate alloc] init];
            delegate.label = self;
            UIEditMenuInteraction *interaction = [[UIEditMenuInteraction alloc] initWithDelegate:delegate];
            delegate.interaction = interaction;
            [self addInteraction:interaction];
            objc_setAssociatedObject(self, PA415MenuDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        if (!longPress) {
            longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:delegate action:@selector(showMenu:)];
            longPress.minimumPressDuration = 0.45;
            longPress.cancelsTouchesInView = YES;
            [self addGestureRecognizer:longPress];
            objc_setAssociatedObject(self, PA415LongPressKey, longPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        self.userInteractionEnabled = YES;
        self.accessibilityHint = @"Long press for Cut, Copy and Paste options";
    }
}

@end
