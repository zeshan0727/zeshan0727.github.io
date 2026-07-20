ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhoneAura
PhoneAura_FILES = Tweak.xm PhoneAuraManagerV4.m PAConceptDUI.m PAConceptDSurfaces.m PADataStore.m
PhoneAura_FRAMEWORKS = UIKit QuartzCore Contacts ContactsUI
PhoneAura_LIBRARIES = sqlite3
PhoneAura_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
PhoneAura_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += phoneauraprefs phoneaurastudio
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 MobilePhone PhoneAuraStudio 2>/dev/null || true"
