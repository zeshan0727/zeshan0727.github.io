#pragma once
#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"

@interface PhoneAuraManager (PAPhoneNumberMenuDeclarationV415)
- (void)pasteNumberIntoKeypad:(NSString *)number;
@end

@interface PAStudioKeypadView (PAKeypadPasteBridgeV415)
- (void)setDialNumber:(NSString *)number;
@end
