TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = RaveRayane
RaveRayane_FILES = Tweak.m
RaveRayane_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-format-security
RaveRayane_FRAMEWORKS = UIKit Foundation AVFoundation PhotosUI ImageIO UniformTypeIdentifiers
RaveRayane_INSTALL_PATH = @rpath

include $(THEOS_MAKE_PATH)/library.mk
