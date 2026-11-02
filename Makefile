TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = Layan
Layan_FILES = Tweak.m
Layan_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-format-security -Wno-unused-function -Wno-error
Layan_FRAMEWORKS = UIKit Foundation AVFoundation PhotosUI ImageIO UniformTypeIdentifiers AudioToolbox CoreLocation
Layan_INSTALL_PATH = @rpath

include $(THEOS_MAKE_PATH)/library.mk
