ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = Cydia

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CydiaRootHideCompat
CydiaRootHideCompat_FILES = Tweak.xm
CydiaRootHideCompat_CFLAGS = -fobjc-arc
CydiaRootHideCompat_CXXFLAGS = -std=c++11
CydiaRootHideCompat_FRAMEWORKS = Foundation
CydiaRootHideCompat_LIBRARIES = roothide

include $(THEOS_MAKE_PATH)/tweak.mk
