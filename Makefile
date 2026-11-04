TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = 8ubah
8ubah_FILES = Tweak.m
8ubah_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-format-security -Wno-unused-function -Wno-error
8ubah_FRAMEWORKS = UIKit Foundation AVFoundation PhotosUI ImageIO UniformTypeIdentifiers CoreLocation
8ubah_INSTALL_PATH = @rpath

include $(THEOS_MAKE_PATH)/library.mk
