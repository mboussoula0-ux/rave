TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = Melo
Melo_FILES = Tweak.m
Melo_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-format-security -Wno-unused-function -Wno-error
Melo_FRAMEWORKS = UIKit Foundation AVFoundation PhotosUI ImageIO UniformTypeIdentifiers CoreLocation
Melo_INSTALL_PATH = @rpath

include $(THEOS_MAKE_PATH)/library.mk
