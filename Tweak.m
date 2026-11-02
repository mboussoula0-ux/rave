// Layan — local feature set for Rave on iPhone (injected dylib)
// Pure Objective-C runtime: no Substrate / no Logos, so it works with Feather / ESign / Sideloadly injection.
// UNTESTED on a device: class names are tunable from Settings > Advanced.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <math.h>

#pragma mark - Config / storage

#define RY_CFG @"ry.cfg.v1"
#define RY_ROOM_DEFAULT @"MeshContentViewController"
#define RY_CHAT_DEFAULT @"MeshChatBarController"
#define RY_BRAND_TOKENS @"rave,logo,wordmark,c7d7409e"

static NSMutableDictionary *gCfg;

static void RYLoad(void) {
    @try {
        NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:RY_CFG];
        gCfg = d ? [d mutableCopy] : [NSMutableDictionary new];
    } @catch (__unused id e) { gCfg = [NSMutableDictionary new]; }
}
static id CF(NSString *k, id def) { id v = gCfg[k]; return v ?: def; }
static void CS(NSString *k, id v) {
    if (v) gCfg[k] = v; else [gCfg removeObjectForKey:k];
    @try { [[NSUserDefaults standardUserDefaults] setObject:gCfg forKey:RY_CFG]; } @catch (__unused id e) {}
}
static NSString *RYDir(NSString *sub) {
    NSString *b = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Rayane"] copy];
    if (sub) b = [b stringByAppendingPathComponent:sub];
    [[NSFileManager defaultManager] createDirectoryAtPath:b withIntermediateDirectories:YES attributes:nil error:nil];
    return b;
}

#pragma mark - Language / colours

static BOOL RYAr(void) {
    NSString *l = CF(@"lang", @"ar"); // Arabic-first default
    if ([l isEqual:@"ar"]) return YES;
    if ([l isEqual:@"en"]) return NO;
    return [[[NSLocale preferredLanguages].firstObject lowercaseString] hasPrefix:@"ar"];
}
#define T(ar, en) (RYAr() ? (ar) : (en))

static UIColor *RYHex(NSString *h) {
    if (![h isKindOfClass:NSString.class]) return UIColor.blackColor;
    NSString *s = [h stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned v = 0; [[NSScanner scannerWithString:s] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1];
}
static NSString *RYHexFrom(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0; [c getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
}
static NSArray *RYAccents(void) { return @[@"#7C5CFF", @"#2DD4BF", @"#F43F5E", @"#F59E0B", @"#3B82F6", @"#22C55E"]; }
static UIColor *RYAccent(void) {
    NSInteger i = [CF(@"accent", @0) integerValue];
    NSArray *a = RYAccents(); if (i < 0 || i >= (NSInteger)a.count) i = 0;
    return RYHex(a[i]);
}
#define RY_BG RYHex(@"#0E1014")
#define RY_CARD RYHex(@"#1A1D25")
#define RY_CARD2 RYHex(@"#252A35")
#define RY_MUTED RYHex(@"#8A90A0")

static NSString *RYHash(NSString *s) {
    NSData *d = [[@"rayane|" stringByAppendingString:s ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *o = [NSMutableString new];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [o appendFormat:@"%02x", h[i]];
    return o;
}
static BOOL RYLocked(void) {
    NSString *h = CF(@"keyHash", @"");
    return h.length > 0 && ![CF(@"unlocked", @NO) boolValue];
}

#pragma mark - UI helpers

static UISemanticContentAttribute RYSem(void) { return RYAr() ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight; }

static UILabel *RYLabel(NSString *t, CGFloat sz, UIFontWeight w, UIColor *c) {
    UILabel *l = [UILabel new]; l.text = t; l.font = [UIFont systemFontOfSize:sz weight:w];
    l.textColor = c ?: UIColor.whiteColor; l.numberOfLines = 0; l.textAlignment = NSTextAlignmentNatural;
    l.semanticContentAttribute = RYSem();
    return l;
}
static UIButton *RYBtn(NSString *t, BOOL filled, void (^act)(void)) {
    UIButtonConfiguration *c = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    c.title = t; c.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    c.baseBackgroundColor = filled ? RYAccent() : RY_CARD2; c.baseForegroundColor = UIColor.whiteColor;
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { if (act) act(); }]];
    b.semanticContentAttribute = RYSem();
    return b;
}
static UIStackView *RYVStack(NSArray *v, CGFloat sp) {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:v]; s.axis = UILayoutConstraintAxisVertical; s.spacing = sp;
    s.semanticContentAttribute = RYSem(); return s;
}
static UIStackView *RYHStack(NSArray *v, CGFloat sp) {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:v]; s.axis = UILayoutConstraintAxisHorizontal; s.spacing = sp;
    s.alignment = UIStackViewAlignmentCenter; s.semanticContentAttribute = RYSem(); return s;
}
static void RYPin(UIView *v, UIView *to, CGFloat pad) {
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:to.topAnchor constant:pad], [v.bottomAnchor constraintEqualToAnchor:to.bottomAnchor constant:-pad],
        [v.leadingAnchor constraintEqualToAnchor:to.leadingAnchor constant:pad], [v.trailingAnchor constraintEqualToAnchor:to.trailingAnchor constant:-pad]]];
}
static UIView *RYCard(NSArray *views) {
    UIView *c = [UIView new]; c.backgroundColor = RY_CARD; c.layer.cornerRadius = 14;
    UIStackView *s = RYVStack(views, 10); [c addSubview:s]; RYPin(s, c, 12); return c;
}
static UIView *RYSlider(NSString *title, float mn, float mx, float val, void (^chg)(float)) {
    UILabel *l = RYLabel(title, 14, UIFontWeightMedium, nil);
    UISlider *s = [UISlider new]; s.minimumValue = mn; s.maximumValue = mx; s.value = val; s.minimumTrackTintColor = RYAccent();
    __weak UISlider *ws = s;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { if (ws && chg) chg(ws.value); }] forControlEvents:UIControlEventValueChanged];
    return RYCard(@[l, s]);
}
static UIView *RYGrid(NSArray *views, int cols) {
    NSMutableArray *rows = [NSMutableArray new];
    for (NSUInteger i = 0; i < views.count; i += cols) {
        NSMutableArray *r = [NSMutableArray new];
        for (int j = 0; j < cols; j++) {
            NSUInteger k = i + j; [r addObject:k < views.count ? views[k] : [UIView new]];
        }
        UIStackView *h = RYHStack(r, 8); h.distribution = UIStackViewDistributionFillEqually; h.alignment = UIStackViewAlignmentFill; [rows addObject:h];
    }
    return RYVStack(rows, 8);
}
static UIImage *RYGradImage(NSString *pair) {
    NSArray *p = [pair componentsSeparatedByString:@","]; if (p.count < 2) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(80, 44)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)@[(id)RYHex(p[0]).CGColor, (id)RYHex(p[1]).CGColor], NULL);
        CGContextDrawLinearGradient(ctx.CGContext, g, CGPointZero, CGPointMake(80, 44), 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
    }];
}

#pragma mark - View-controller discovery
#pragma mark - Visibility (hidden pre-loaded screens must not count as "on screen")

static BOOL RYVisible(UIView *v) {
    if (!v.window) return NO;
    for (UIView *p = v; p; p = p.superview) if (p.hidden || p.alpha < 0.05) return NO;
    CGRect f = CGRectIntersection([v convertRect:v.bounds toView:nil], v.window.bounds);
    return !CGRectIsNull(f) && f.size.width > 40 && f.size.height > 40;
}
static UIScrollView *RYBiggestList(void);
static NSArray<UIView *> *RYVisibleCells(UIScrollView *sv);
static void RYCellTexts(UIView *v, NSMutableString *o, int d);
static id RYInviteCtl(UIView *cell);
static void RYScanAll(UIViewController *vc, NSString *needle, int d, NSMutableArray *out) {
    if (!vc || d > 14) return;
    if ([NSStringFromClass(vc.class) containsString:needle] && vc.isViewLoaded && vc.view.window) [out addObject:vc];
    for (UIViewController *c in vc.childViewControllers) RYScanAll(c, needle, d + 1, out);
    RYScanAll(vc.presentedViewController, needle, d + 1, out);
}


@class RYWindow;
static UIViewController *RYScan(UIViewController *vc, NSString *needle, int d) {
    if (!vc || d > 14) return nil;
    if ([NSStringFromClass(vc.class) containsString:needle] && vc.isViewLoaded && vc.view.window) return vc;
    for (UIViewController *c in vc.childViewControllers) { UIViewController *r = RYScan(c, needle, d + 1); if (r) return r; }
    return RYScan(vc.presentedViewController, needle, d + 1);
}
static NSArray<UIWindow *> *RYAppWindows(void) {
    NSMutableArray *a = [NSMutableArray new];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) { if (![NSStringFromClass(w.class) isEqual:@"RYWindow"]) [a addObject:w]; }
    }
    return a;
}
static UIViewController *RYFindVC(NSString *needle) {
    if (!needle.length) return nil;
    for (UIWindow *w in RYAppWindows()) { UIViewController *r = RYScan(w.rootViewController, needle, 0); if (r) return r; }
    return nil;
}
static void RYDump(UIViewController *vc, int d, NSMutableString *o) {
    if (!vc || d > 14) return;
    [o appendFormat:@"%@%@\n", [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0], NSStringFromClass(vc.class)];
    for (UIViewController *c in vc.childViewControllers) RYDump(c, d + 1, o);
    RYDump(vc.presentedViewController, d + 1, o);
}

#pragma mark - Sounds

static NSData *RYWav(double dur, double (^f)(double)) {
    const int sr = 44100; int n = (int)(dur * sr);
    NSMutableData *d = [NSMutableData dataWithLength:44 + n * 2]; uint8_t *p = d.mutableBytes;
    memcpy(p, "RIFF", 4); uint32_t v = 36 + n * 2; memcpy(p + 4, &v, 4); memcpy(p + 8, "WAVEfmt ", 8);
    v = 16; memcpy(p + 16, &v, 4); uint16_t s16 = 1; memcpy(p + 20, &s16, 2); memcpy(p + 22, &s16, 2);
    v = sr; memcpy(p + 24, &v, 4); v = sr * 2; memcpy(p + 28, &v, 4); s16 = 2; memcpy(p + 32, &s16, 2); s16 = 16; memcpy(p + 34, &s16, 2);
    memcpy(p + 36, "data", 4); v = n * 2; memcpy(p + 40, &v, 4);
    int16_t *o = (int16_t *)(p + 44);
    for (int i = 0; i < n; i++) { double x = f((double)i / sr); if (x > 1) x = 1; if (x < -1) x = -1; o[i] = (int16_t)(x * 32000); }
    return d;
}
static NSArray *RYBuiltinNames(void) {
    return @[@[@"جرس", @"Ding"], @[@"ليزر", @"Laser"], @[@"بوزر", @"Buzzer"], @[@"بوق", @"Air horn"], @[@"حزين", @"Sad trombone"], @[@"تصفيق", @"Applause"], @[@"طبلة", @"Kick drum"]];
}
static NSData *RYBuiltinData(NSInteger i) {
    static NSMutableDictionary *cache; if (!cache) cache = [NSMutableDictionary new];
    NSData *c = cache[@(i)]; if (c) return c;
    NSData *d = nil;
    switch (i) {
        case 0: d = RYWav(1.2, ^double(double t) { return sin(2 * M_PI * 880 * t) * exp(-4 * t) * 0.6 + sin(2 * M_PI * 1320 * t) * exp(-6 * t) * 0.25; }); break;
        case 1: d = RYWav(0.5, ^double(double t) { return sin(2 * M_PI * (1800 * t - 1500 * t * t)) * exp(-3 * t) * 0.6; }); break;
        case 2: d = RYWav(0.6, ^double(double t) { return (t < 0.55 ? 1 : 0) * (sin(2 * M_PI * 140 * t) > 0 ? 0.4 : -0.4); }); break;
        case 3: d = RYWav(1.0, ^double(double t) {
            double e = MIN(1.0, t / 0.03) * (t > 0.85 ? (1.0 - t) / 0.15 : 1);
            double a = sin(2 * M_PI * 466 * t) > 0 ? 1 : -1, b = sin(2 * M_PI * 554 * t) > 0 ? 1 : -1, c = sin(2 * M_PI * 698 * t) > 0 ? 1 : -1;
            return (a + b + c) * 0.12 * e; }); break;
        case 4: d = RYWav(1.8, ^double(double t) {
            double fr = t < 0.4 ? 311 : t < 0.8 ? 294 : t < 1.2 ? 277 : 262 * (1 - 0.04 * sin(2 * M_PI * 6 * t));
            double env = t > 1.5 ? MAX(0, (1.8 - t) / 0.3) : 1; return (2 * fmod(fr * t, 1.0) - 1) * 0.35 * env; }); break;
        case 5: d = RYWav(1.6, ^double(double t) {
            double env = MIN(1.0, t / 0.1) * (t > 1.2 ? (1.6 - t) / 0.4 : 1); double m = pow(sin(2 * M_PI * 9 * t) * 0.5 + 0.5, 2) + 0.3;
            return (arc4random_uniform(2000) / 1000.0 - 1) * 0.5 * env * m; }); break;
        default: d = RYWav(0.4, ^double(double t) { return sin(2 * M_PI * (60 * t + (90 / 12.0) * (1 - exp(-12 * t)))) * exp(-8 * t) * 0.9; }); break;
    }
    cache[@(i)] = d; return d;
}
static NSMutableArray<AVAudioPlayer *> *gPlayers;
static void RYPlayData(NSData *d, NSURL *url) {
    if (!gPlayers) gPlayers = [NSMutableArray new];
    NSMutableArray *dead = [NSMutableArray new]; for (AVAudioPlayer *p in gPlayers) if (!p.playing) [dead addObject:p]; [gPlayers removeObjectsInArray:dead];
    NSError *e = nil; AVAudioPlayer *p = d ? [[AVAudioPlayer alloc] initWithData:d error:&e] : [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&e];
    if (!p) return; p.volume = [CF(@"vol", @0.8) floatValue]; [gPlayers addObject:p]; [p prepareToPlay]; [p play];
}
static void RYStopAll(void) { for (AVAudioPlayer *p in gPlayers) [p stop]; [gPlayers removeAllObjects]; }
static NSArray<NSString *> *RYSoundFiles(void) {
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:RYDir(@"sounds") error:nil] ?: @[];
    return [all sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Mic booster (hooks AudioUnitRender on the mic bus used by WebRTC)

static volatile BOOL gMicOn = NO;
static volatile float gMicGain = 2.0f;
static volatile BOOL gNoIso = YES; // turn off voice processing (noise suppression / AGC / echo cancel) on the mic unit

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);

static inline float RYSoft(float x) { // x in -1..1 range, soft knee above 0.6 so boosted peaks don't harsh-clip
    float a = fabsf(x);
    if (a <= 0.6f) return x;
    float o = 0.6f + 0.4f * tanhf((a - 0.6f) / 0.4f);
    return x < 0 ? -o : o;
}
static void RYApplyGain(AudioUnit u, AudioBufferList *io) {
    static AudioUnit lastU = NULL; static BOOL isFloat = NO; static BOOL is16 = YES;
    if (u != lastU) {
        AudioStreamBasicDescription d; UInt32 sz = sizeof(d); memset(&d, 0, sizeof(d));
        if (AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &d, &sz) == noErr && d.mBitsPerChannel) {
            isFloat = (d.mFormatFlags & kAudioFormatFlagIsFloat) != 0; is16 = d.mBitsPerChannel == 16;
        } else { isFloat = NO; is16 = YES; }
        lastU = u;
    }
    float g = gMicGain; if (g < 1.0f) g = 1.0f; if (g > 8.0f) g = 8.0f;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        void *p = io->mBuffers[b].mData; UInt32 bytes = io->mBuffers[b].mDataByteSize; if (!p || !bytes) continue;
        if (isFloat) { float *f = p; UInt32 n = bytes / 4; for (UInt32 i = 0; i < n; i++) f[i] = RYSoft(f[i] * g); }
        else if (is16) {
            int16_t *s = p; UInt32 n = bytes / 2;
            for (UInt32 i = 0; i < n; i++) { float x = RYSoft((s[i] / 32768.0f) * g); s[i] = (int16_t)(x * 32767.0f); }
        }
    }
}
static OSStatus ry_AudioUnitRender(AudioUnit u, AudioUnitRenderActionFlags *f, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io) {
    OSStatus r = orig_AudioUnitRender(u, f, ts, bus, frames, io);
    if (r == noErr && bus == 1 && io && gMicOn) RYApplyGain(u, io);
    return r;
}

static OSStatus (*orig_AudioUnitInitialize)(AudioUnit);
static OSStatus ry_AudioUnitInitialize(AudioUnit u) {
    if (gNoIso) {
        UInt32 one = 1, zero = 0;
        AudioUnitSetProperty(u, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &one, sizeof(one));
        AudioUnitSetProperty(u, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, &zero, sizeof(zero));
    }
    return orig_AudioUnitInitialize(u);
}

// minimal fishhook (arm64): rebinds the lazy / non-lazy symbol pointers of every loaded image
static void RYRebindSection(const struct section_64 *sec, intptr_t slide, struct nlist_64 *symtab, char *strtab, uint32_t *indirect, const char *name, void *repl, void **orig) {
    BOOL isConst = strcmp(sec->segname, "__DATA_CONST") == 0;
    uint32_t *idx = indirect + sec->reserved1;
    void **bind = (void **)((uintptr_t)slide + sec->addr);
    uintptr_t pg = (uintptr_t)bind & ~(uintptr_t)0x3FFF; size_t plen = (((uintptr_t)bind + sec->size) - pg + 0x3FFF) & ~(uintptr_t)0x3FFF;
    if (isConst) mprotect((void *)pg, plen, PROT_READ | PROT_WRITE);
    for (uint32_t i = 0; i < sec->size / sizeof(void *); i++) {
        uint32_t si = idx[i];
        if (si == INDIRECT_SYMBOL_ABS || si == INDIRECT_SYMBOL_LOCAL || si == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        char *sn = strtab + symtab[si].n_un.n_strx;
        if (sn[0] && sn[1] && strcmp(sn + 1, name) == 0) {
            if (orig && *orig == NULL && bind[i] != repl) *orig = bind[i];
            bind[i] = repl;
        }
    }
    if (isConst) mprotect((void *)pg, plen, PROT_READ);
}
static void RYAddImage(const struct mach_header *mh, intptr_t slide) {
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    if (h->magic != MH_MAGIC_64) return;
    const struct segment_command_64 *linkedit = NULL; const struct symtab_command *st = NULL; const struct dysymtab_command *dst = NULL;
    uintptr_t cur = (uintptr_t)h + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) { const struct segment_command_64 *sg = (const void *)lc; if (strcmp(sg->segname, SEG_LINKEDIT) == 0) linkedit = sg; }
        else if (lc->cmd == LC_SYMTAB) st = (const void *)lc;
        else if (lc->cmd == LC_DYSYMTAB) dst = (const void *)lc;
        cur += lc->cmdsize;
    }
    if (!linkedit || !st || !dst || !dst->nindirectsyms) return;
    uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    struct nlist_64 *symtab = (struct nlist_64 *)(base + st->symoff); char *strtab = (char *)(base + st->stroff);
    uint32_t *indirect = (uint32_t *)(base + dst->indirectsymoff);
    cur = (uintptr_t)h + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sg = (const void *)lc;
            if (strcmp(sg->segname, "__DATA") == 0 || strcmp(sg->segname, "__DATA_CONST") == 0) {
                const struct section_64 *sec = (const void *)(cur + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < sg->nsects; j++) {
                    uint32_t t = sec[j].flags & SECTION_TYPE;
                    if (t == S_LAZY_SYMBOL_POINTERS || t == S_NON_LAZY_SYMBOL_POINTERS)
                        RYRebindSection(&sec[j], slide, symtab, strtab, indirect, "AudioUnitRender", (void *)ry_AudioUnitRender, (void **)&orig_AudioUnitRender);
                    if (t == S_LAZY_SYMBOL_POINTERS || t == S_NON_LAZY_SYMBOL_POINTERS)
                        RYRebindSection(&sec[j], slide, symtab, strtab, indirect, "AudioUnitInitialize", (void *)ry_AudioUnitInitialize, (void **)&orig_AudioUnitInitialize);
                }
            }
        }
        cur += lc->cmdsize;
    }
}
static void RYSetNoIso(BOOL on) { gNoIso = on; CS(@"noIso", @(on)); }
static void RYSetMic(BOOL on, float gain) {
    gMicOn = on; gMicGain = gain; CS(@"micOn", @(on)); CS(@"micGain", @(gain));
}

#pragma mark - Branding

static NSString *RYBrand(void) {
    NSString *s = CF(@"brandName", @"Layan");
    return ([s isKindOfClass:NSString.class] && s.length) ? s : @"Layan";
}
static NSString *RYImgName(UIImage *im) {
    if (!im) return @"";
    @try { NSString *n = [im.imageAsset valueForKey:@"assetName"]; return n ?: @""; } @catch (__unused id e) { return @""; }
}
static BOOL RYInCell(UIView *v) {
    for (UIView *p = v; p; p = p.superview) if ([p isKindOfClass:UITableViewCell.class] || [p isKindOfClass:UICollectionViewCell.class]) return YES;
    return NO;
}
static NSString *const kRaveRx = @"\\brave\\b";
// returns the replaced text, or nil when there is nothing to replace
static NSString *RYRepl(NSString *s) {
    if (![s isKindOfClass:NSString.class] || !s.length || s.length > 40) return nil;
    if ([s rangeOfString:RYBrand() options:NSCaseInsensitiveSearch].location != NSNotFound) return nil;
    if ([s rangeOfString:kRaveRx options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location == NSNotFound) return nil;
    return [s stringByReplacingOccurrencesOfString:kRaveRx withString:[NSRegularExpression escapedTemplateForString:RYBrand()]
                                           options:NSRegularExpressionSearch | NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
}
static UIImage *RYTextImage(NSString *t, CGSize sz, UIColor *c) {
    static NSCache *cache; if (!cache) cache = [NSCache new];
    NSString *ck = [NSString stringWithFormat:@"%@|%.0fx%.0f|%@", t, sz.width, sz.height, RYHexFrom(c)];
    UIImage *hit = [cache objectForKey:ck]; if (hit) return hit;
    CGFloat fs = MAX(10, sz.height * 0.85); NSDictionary *a = nil; CGSize ts = CGSizeZero;
    for (int k = 0; k < 16; k++) {
        UIFont *f = [UIFont systemFontOfSize:fs weight:UIFontWeightBlack];
        UIFontDescriptor *rd = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (rd) f = [UIFont fontWithDescriptor:rd size:fs];
        a = @{NSFontAttributeName: f, NSForegroundColorAttributeName: c, NSKernAttributeName: @(fs * 0.02)};
        ts = [t sizeWithAttributes:a];
        if (ts.width <= sz.width && ts.height <= sz.height) break;
        fs *= 0.88;
    }
    NSDictionary *fa = a; CGSize fts = ts;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz];
    UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext *x) {
        [t drawAtPoint:CGPointMake((sz.width - fts.width) / 2, (sz.height - fts.height) / 2) withAttributes:fa];
    }];
    [cache setObject:out forKey:ck]; return out;
}
static void RYBrandWalk(UIView *v, NSArray *toks) {
    if ([v isKindOfClass:UIImageView.class]) {
        UIImageView *iv = (UIImageView *)v; CGSize s = iv.bounds.size;
        if (iv.image && iv.window && !iv.hidden && s.width > 24 && s.height > 8 && s.height <= 140 && s.width / s.height >= 1.3 && !RYInCell(iv)) {
            NSString *n = [RYImgName(iv.image) lowercaseString], *i = [iv.accessibilityIdentifier lowercaseString] ?: @"", *a = [iv.accessibilityLabel lowercaseString] ?: @"";
            BOOL hit = NO; for (NSString *t in toks) if ([n containsString:t] || [i containsString:t] || [a containsString:t]) { hit = YES; break; }
            if (hit) {
                UIColor *c = iv.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight ? UIColor.blackColor : UIColor.whiteColor;
                iv.image = RYTextImage(RYBrand(), s, c); iv.contentMode = UIViewContentModeScaleAspectFit;
            }
        }
    } else if ([v isKindOfClass:UILabel.class]) {
        UILabel *l = (UILabel *)v; NSAttributedString *at = l.attributedText;
        if (at.length && at.length <= 40 && !RYInCell(l) && RYRepl(at.string)) {
            NSMutableAttributedString *m = [at mutableCopy];
            [m.mutableString replaceOccurrencesOfString:kRaveRx withString:[NSRegularExpression escapedTemplateForString:RYBrand()]
                                                options:NSRegularExpressionSearch | NSCaseInsensitiveSearch range:NSMakeRange(0, m.length)];
            l.attributedText = m;
        }
    } else if ([v isKindOfClass:UIButton.class] && !RYInCell(v)) {
        UIButton *b = (UIButton *)v;
        NSString *n = RYRepl([b titleForState:UIControlStateNormal]); if (n) [b setTitle:n forState:UIControlStateNormal];
        UIButtonConfiguration *cfg = b.configuration; NSString *cn = RYRepl(cfg.title);
        if (cn) { cfg.title = cn; b.configuration = cfg; }
    }
    for (UIView *s in v.subviews) RYBrandWalk(s, toks);
}
static void RYImageWalk(UIView *v, NSMutableOrderedSet *o) {
    if ([v isKindOfClass:UIImageView.class]) {
        UIImageView *iv = (UIImageView *)v; NSString *n = RYImgName(iv.image);
        if (iv.window && n.length) [o addObject:[NSString stringWithFormat:@"%@  %.0fx%.0f", n, iv.bounds.size.width, iv.bounds.size.height]];
    }
    for (UIView *s in v.subviews) RYImageWalk(s, o);
}
static NSString *RYImageReport(void) {
    NSMutableOrderedSet *o = [NSMutableOrderedSet new];
    for (UIWindow *w in RYAppWindows()) RYImageWalk(w, o);
    return [[o array] componentsJoinedByString:@"\n"];
}

#pragma mark - Background view

@interface RYBGView : UIView
@property (nonatomic, strong) UIImageView *img;
@property (nonatomic, strong) CAGradientLayer *grad;
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIView *dim;
@property (nonatomic) NSInteger stamp;
- (void)apply;
@end
@implementation RYBGView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO; self.clipsToBounds = YES;
        self.grad = [CAGradientLayer layer]; self.grad.startPoint = CGPointMake(0, 0); self.grad.endPoint = CGPointMake(1, 1); [self.layer addSublayer:self.grad];
        self.img = [UIImageView new]; self.img.contentMode = UIViewContentModeScaleAspectFill; self.img.clipsToBounds = YES; [self addSubview:self.img];
        self.blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]]; [self addSubview:self.blur];
        self.dim = [UIView new]; self.dim.backgroundColor = UIColor.blackColor; [self addSubview:self.dim];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.grad.frame = self.bounds; self.img.frame = self.bounds; self.blur.frame = self.bounds; self.dim.frame = self.bounds; }
- (void)apply {
    NSString *m = CF(@"bgMode", @"none"), *v = CF(@"bgValue", @"");
    self.img.hidden = YES; self.grad.hidden = YES; self.backgroundColor = UIColor.blackColor;
    if ([m isEqual:@"image"]) {
        UIImage *im = [UIImage imageWithContentsOfFile:[RYDir(nil) stringByAppendingPathComponent:@"bg.jpg"]];
        if (im) { self.img.image = im; self.img.hidden = NO; }
    } else if ([m isEqual:@"color"]) { self.backgroundColor = RYHex(v); }
    else if ([m isEqual:@"gradient"]) {
        NSArray *p = [v componentsSeparatedByString:@","];
        if (p.count >= 2) { self.grad.colors = @[(id)RYHex(p[0]).CGColor, (id)RYHex(p[1]).CGColor]; self.grad.hidden = NO; }
    }
    self.blur.alpha = [CF(@"blur", @0) floatValue] / 100.0;
    self.dim.alpha = [CF(@"dim", @30) floatValue] / 100.0 * 0.9;
}
@end

#pragma mark - Room helpers (see-through views, chat input, diagnostics)

static NSMapTable *gOrigBG;
static BOOL RYSkipClass(UIView *v) {
    NSString *c = NSStringFromClass(v.class), *l = NSStringFromClass(v.layer.class);
    for (NSString *k in @[@"Video", @"Player", @"Metal", @"MTK", @"Camera", @"Preview", @"Flutter", @"WK", @"WebView", @"SampleBuffer"])
        if ([c containsString:k] || [l containsString:k]) return YES;
    return NO;
}
static void RYClear(UIView *v) {
    if (!gOrigBG) gOrigBG = [NSMapTable weakToStrongObjectsMapTable];
    if (![gOrigBG objectForKey:v]) [gOrigBG setObject:(v.backgroundColor ?: (id)NSNull.null) forKey:v];
    v.backgroundColor = UIColor.clearColor;
}
static void RYRestoreAll(void) {
    for (UIView *v in [gOrigBG.keyEnumerator allObjects]) {
        id o = [gOrigBG objectForKey:v]; v.backgroundColor = [o isKindOfClass:UIColor.class] ? o : nil;
    }
    [gOrigBG removeAllObjects];
}
static BOOL RYHasBG(UIView *v) { return v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor) > 0.05; }
// highest full-screen container above the room view (the room VC's own view can be only a small part of the screen)
static UIView *RYFullHost(UIView *v) {
    UIWindow *w = v.window; if (!w) return v;
    UIView *best = v;
    for (UIView *p = v.superview; p && p != w; p = p.superview) {
        CGSize s = [p convertRect:p.bounds toView:w].size;
        if (s.width >= w.bounds.size.width * 0.9 && s.height >= w.bounds.size.height * 0.8) best = p;
    }
    return best;
}
static void RYClearBig(UIView *v, UIView *host, UIView *skip, int d) {
    if (d > 10) return;
    for (UIView *s in v.subviews) {
        if (s == skip || RYSkipClass(s)) continue;
        if (RYHasBG(s) && ![s isKindOfClass:UIImageView.class]) {
            CGRect f = [s convertRect:s.bounds toView:host];
            if (f.size.width >= host.bounds.size.width * 0.85 && f.size.height >= host.bounds.size.height * 0.4) RYClear(s);
        }
        RYClearBig(s, host, skip, d + 1);
    }
}

static void RYCollectInputs(UIView *v, NSMutableArray *o, int d) {
    if (d > 40) return;
    BOOL tf = [v isKindOfClass:UITextField.class] && !((UITextField *)v).secureTextEntry;
    BOOL tv = [v isKindOfClass:UITextView.class] && ((UITextView *)v).isEditable;
    if ((tf || tv) && !v.hidden && v.alpha > 0.01 && v.window && v.userInteractionEnabled) [o addObject:v];
    for (UIView *s in v.subviews) RYCollectInputs(s, o, d + 1);
}
// chat bars sit at the bottom: pick the lowest visible input
static UIView *RYBottomInput(UIView *root) {
    NSMutableArray *c = [NSMutableArray new]; RYCollectInputs(root, c, 0);
    UIView *best = nil; CGFloat by = -1e9;
    for (UIView *x in c) { CGFloat y = CGRectGetMaxY([x convertRect:x.bounds toView:nil]); if (y > by) { by = y; best = x; } }
    return best;
}
static NSString *RYGetText(UIView *in) { return [in isKindOfClass:UITextField.class] ? ((UITextField *)in).text : ((UITextView *)in).text; }
static void RYSetText(UIView *in, NSString *msg) {
    if ([in isKindOfClass:UITextField.class]) {
        UITextField *tf = (UITextField *)in; tf.text = msg;
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextFieldTextDidChangeNotification object:tf];
    } else {
        UITextView *tv = (UITextView *)in; tv.text = msg;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) [tv.delegate textViewDidChange:tv];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:tv];
    }
}
static void RYPressReturn(UIView *in) {
    if ([in isKindOfClass:UITextField.class]) {
        UITextField *tf = (UITextField *)in;
        if ([tf.delegate respondsToSelector:@selector(textFieldShouldReturn:)]) [tf.delegate textFieldShouldReturn:tf];
        [tf sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
        [tf sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    } else {
        UITextView *tv = (UITextView *)in;
        if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)])
            [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(tv.text.length, 0) replacementText:@"\n"];
    }
}
static void RYCollectCtl(UIView *v, NSMutableArray *o, int d) {
    if (d > 8) return;
    if ([v isKindOfClass:UIControl.class] && !v.hidden && v.alpha > 0.01 && ((UIControl *)v).enabled && v.window) [o addObject:v];
    for (UIView *s in v.subviews) RYCollectCtl(s, o, d + 1);
}
static NSString *RYCtlKey(UIControl *b) {
    NSMutableString *k = [NSMutableString new];
    [k appendFormat:@"%@|%@|", b.accessibilityLabel ?: @"", b.accessibilityIdentifier ?: @""];
    if ([b isKindOfClass:UIButton.class]) {
        UIButton *ub = (UIButton *)b;
        [k appendFormat:@"%@|%@|%@", [ub titleForState:UIControlStateNormal] ?: @"", ub.configuration.title ?: @"", RYImgName([ub imageForState:UIControlStateNormal])];
    }
    return k.lowercaseString;
}
// SwiftUI rows are not UIControls: reach their buttons through the accessibility tree
static void RYA11yCollect(id o, NSMutableArray *out, int d) {
    if (!o || d > 9) return;
    if ([o isKindOfClass:UIView.class]) {
        UIView *v = o; if (v.hidden) return;
        if (v.isAccessibilityElement) [out addObject:v];
        NSArray *e = v.accessibilityElements; if (e) for (id x in e) RYA11yCollect(x, out, d + 1);
        for (UIView *sv in v.subviews) RYA11yCollect(sv, out, d + 1);
    } else {
        if ([o isAccessibilityElement]) [out addObject:o];
        NSArray *e = [o accessibilityElements]; if (e) for (id x in e) RYA11yCollect(x, out, d + 1);
    }
}
static NSString *RYA11yKey(id e) {
    NSString *l = [e accessibilityLabel] ?: @"", *i = [e respondsToSelector:@selector(accessibilityIdentifier)] ? ([e accessibilityIdentifier] ?: @"") : @"";
    return [NSString stringWithFormat:@"%@|%@|%llu", l, i, (unsigned long long)[e accessibilityTraits]].lowercaseString;
}
static UIControl *RYSendBtnNear(UIView *in) {
    NSArray *good = @[@"send", @"إرسال", @"ارسال", @"submit", @"paperplane", @"paper_plane", @"arrow.up", @"arrow_up"];
    NSArray *bad = @[@"sticker", @"emoji", @"gif", @"mic", @"voice", @"camera", @"attach", @"photo", @"gift"];
    UIView *p = in;
    for (int i = 0; i < 6 && p.superview; i++) {
        p = p.superview;
        NSMutableArray *c = [NSMutableArray new]; RYCollectCtl(p, c, 0);
        for (UIControl *b in c) {
            if ((UIView *)b == in || [b isKindOfClass:UITextField.class]) continue;
            NSString *k = RYCtlKey(b); BOOL skip = NO;
            for (NSString *w in bad) if ([k containsString:w]) { skip = YES; break; }
            if (skip) continue;
            for (NSString *w in good) if ([k containsString:w]) return b;
        }
        if (p.bounds.size.height > 400) break;
    }
    return nil;
}

static void RYWalk(UIView *v, int d, void (^blk)(UIView *, int)) { blk(v, d); for (UIView *s in v.subviews) RYWalk(s, d + 1, blk); }
static NSString *RYClip(NSString *s, NSUInteger n) {
    if (!s.length) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return s.length > n ? [s substringToIndex:n] : s;
}
static NSString *RYReport(void) {
    NSMutableString *o = [NSMutableString new];
    NSDictionary *inf = NSBundle.mainBundle.infoDictionary;
    [o appendFormat:@"app %@ (%@) | iOS %@ | %@\n", inf[@"CFBundleShortVersionString"], inf[@"CFBundleVersion"], UIDevice.currentDevice.systemVersion, UIDevice.currentDevice.model];
    UIViewController *room = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT)), *chat = RYFindVC(CF(@"chatClass", RY_CHAT_DEFAULT));
    [o appendFormat:@"room: %@\nchat: %@\n", room ? NSStringFromClass(room.class) : @"NOT FOUND", chat ? NSStringFromClass(chat.class) : @"not found"];
    __block BOOL flutter = NO;
    for (UIWindow *w in RYAppWindows()) RYWalk(w, 0, ^(UIView *x, int d) { if ([NSStringFromClass(x.class) containsString:@"Flutter"]) flutter = YES; });
    [o appendFormat:@"flutter views: %@\n\n-- screens --\n", flutter ? @"yes" : @"no"];
    for (UIWindow *w in RYAppWindows()) RYDump(w.rootViewController, 0, o);
    UIView *host = room ? RYFullHost(room.view) : nil;
    if (host) {
        [o appendFormat:@"\n-- host %@ %.0fx%.0f | room view %.0fx%.0f --\n", NSStringFromClass(host.class), host.bounds.size.width, host.bounds.size.height, room.view.bounds.size.width, room.view.bounds.size.height];
        RYWalk(host, 0, ^(UIView *x, int d) {
            if (o.length > 8000) return;
            CGRect f = [x convertRect:x.bounds toView:host];
            if (f.size.width >= host.bounds.size.width * 0.8 && f.size.height >= host.bounds.size.height * 0.4) {
                CGFloat a = x.backgroundColor ? CGColorGetAlpha(x.backgroundColor.CGColor) : 0;
                [o appendFormat:@"%@%@ %.0fx%.0f bg=%.2f%@\n", [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0], NSStringFromClass(x.class), f.size.width, f.size.height, a, x.hidden ? @" hidden" : @""];
            }
        });
    }
    [o appendString:@"\n-- inputs / buttons --\n"];
    for (UIWindow *w in RYAppWindows()) RYWalk(w, 0, ^(UIView *x, int d) {
        if (o.length > 14000 || x.hidden || !x.window) return;
        CGRect f = [x convertRect:x.bounds toView:nil];
        if ([x isKindOfClass:UITextField.class] || [x isKindOfClass:UITextView.class])
            [o appendFormat:@"INPUT %@ y=%.0f %.0fx%.0f text=\"%@\"\n", NSStringFromClass(x.class), f.origin.y, f.size.width, f.size.height, RYClip(RYGetText(x), 20)];
        else if ([x isKindOfClass:UIButton.class] && !RYInCell(x))
            [o appendFormat:@"BTN y=%.0f x=%.0f %.0fx%.0f key=%@\n", f.origin.y, f.origin.x, f.size.width, f.size.height, RYClip(RYCtlKey((UIControl *)x), 50)];
    });
    [o appendString:@"\n-- list rows (accessibility) --\n"];
    __block int rows = 0;
    for (UIWindow *w in RYAppWindows()) RYWalk(w, 0, ^(UIView *x, int d) {
        if (rows >= 4 || o.length > 22000 || x.hidden || !x.window) return;
        if (![x isKindOfClass:UICollectionView.class] && ![x isKindOfClass:UITableView.class]) return;
        NSArray *cells = [x isKindOfClass:UITableView.class] ? ((UITableView *)x).visibleCells : ((UICollectionView *)x).visibleCells;
        for (UIView *c in cells) {
            if (rows >= 4) break; rows++;
            NSMutableString *t = [NSMutableString new]; RYWalk(c, 0, ^(UIView *y, int dd) { if ([y isKindOfClass:UILabel.class] && ((UILabel *)y).text.length) [t appendFormat:@"%@ ; ", RYClip(((UILabel *)y).text, 20)]; });
            NSMutableArray *a = [NSMutableArray new]; RYA11yCollect(c, a, 0);
            [o appendFormat:@"ROW %@ texts=%@\n", NSStringFromClass(c.class), t];
            for (id e in a) [o appendFormat:@"   A11Y %@ %@\n", NSStringFromClass([e class]), RYClip(RYA11yKey(e), 70)];
        }
    });
    [o appendString:@"\n-- invite screen --\n"];
    {
        NSMutableArray *vcs = [NSMutableArray new];
        for (UIWindow *w in RYAppWindows()) RYScanAll(w.rootViewController, CF(@"inviteClass", @"FriendsManagementViewController"), 0, vcs);
        [o appendFormat:@"invite VCs: %lu, visible: ", (unsigned long)vcs.count];
        int vis = 0; for (UIViewController *vc in vcs) if (RYVisible(vc.view)) vis++;
        [o appendFormat:@"%d\n", vis];
        UIScrollView *l = RYBiggestList();
        if (!l) [o appendString:@"NO visible list (open the Invite/Friends screen first)\n"];
        else {
            [o appendFormat:@"list %@ %.0fx%.0f\n", NSStringFromClass(l.class), l.bounds.size.width, l.bounds.size.height];
            int n = 0;
            for (UIView *c in RYVisibleCells(l)) {
                if (n++ >= 5) break;
                NSMutableString *t = [NSMutableString new]; RYCellTexts(c, t, 0);
                id b = RYInviteCtl(c);
                [o appendFormat:@"CELL %@ texts=%@ invite=%@\n", NSStringFromClass(c.class), RYClip(t, 50), b ? (([b isKindOfClass:UIControl.class]) ? RYClip(RYCtlKey(b), 50) : RYClip(RYA11yKey(b), 50)) : @"NONE"];
                NSMutableArray *ax = [NSMutableArray new]; RYA11yCollect(c, ax, 0);
                for (id e in ax) [o appendFormat:@"   A11Y %@ %@\n", NSStringFromClass([e class]), RYClip(RYA11yKey(e), 70)];
            }
        }
    }
    [o appendString:@"\n-- logo candidates --\n"];
    for (UIWindow *w in RYAppWindows()) RYWalk(w, 0, ^(UIView *x, int d) {
        if (o.length > 18000 || x.hidden || !x.window) return;
        CGRect f = [x convertRect:x.bounds toView:nil];
        if ([x isKindOfClass:UIImageView.class] && ((UIImageView *)x).image && f.size.height <= 140 && f.size.height > 8 && f.size.width / f.size.height >= 1.3)
            [o appendFormat:@"IMG \"%@\" id=\"%@\" %.0fx%.0f y=%.0f\n", RYImgName(((UIImageView *)x).image), x.accessibilityIdentifier ?: @"", f.size.width, f.size.height, f.origin.y];
        else if ([x isKindOfClass:UILabel.class] && [[((UILabel *)x).text lowercaseString] containsString:@"rave"])
            [o appendFormat:@"LABEL \"%@\" y=%.0f\n", RYClip(((UILabel *)x).text, 30), f.origin.y];
    });
    return o;
}

#pragma mark - Window / root

@interface RYWindow : UIWindow @end
@implementation RYWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (self.rootViewController.presentedViewController) return v;
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
- (BOOL)canBecomeKeyWindow { return self.rootViewController.presentedViewController != nil; }
@end

@interface RYCore : NSObject
@property (nonatomic, strong) RYWindow *win;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL wasIn;
@property (nonatomic, weak) UIWindow *prevKey;
@property (nonatomic, strong) RYBGView *bgView;
@property (nonatomic, weak) UIView *bgHost;
@property (nonatomic, strong) UIColor *origBg;
@property (nonatomic) NSInteger stamp;
+ (instancetype)shared;
- (void)start; - (void)openPanel; - (void)panelClosed; - (void)bump;
- (void)sendMessage:(NSString *)msg done:(void (^)(NSInteger code))done;
// one-shot invite pass over the visible list (Recents / Friends screen)
@property (nonatomic) BOOL invRunning;
@property (nonatomic) NSInteger invSent;
@property (nonatomic, copy) NSString *invStatus;
- (void)startInvites; - (void)stopInvites; - (NSInteger)invCooldownLeft;
@end

#pragma mark - Panel

@interface RYPanel : UIViewController <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic) NSInteger tab;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *invLabel;
@property (nonatomic, strong) NSTimer *invUI;
@end

@implementation RYPanel
- (void)viewDidLoad { [super viewDidLoad]; [self rebuild]; }
- (void)viewDidDisappear:(BOOL)a { [super viewDidDisappear:a]; [self.invUI invalidate]; self.invUI = nil; if (self.isBeingDismissed) [[RYCore shared] panelClosed]; }

- (void)toast:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *l = RYLabel(s, 14, UIFontWeightMedium, nil); l.textAlignment = NSTextAlignmentCenter; l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        l.layer.cornerRadius = 12; l.clipsToBounds = YES;
        CGSize z = [l sizeThatFits:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX)];
        l.frame = CGRectMake(0, 0, z.width + 28, z.height + 18); l.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height - 90);
        [self.view addSubview:l];
        [UIView animateWithDuration:0.4 delay:1.8 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
    });
}
- (void)ask:(NSString *)title ph:(NSString *)ph secure:(BOOL)sec ok:(void (^)(NSString *))cb {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) { t.placeholder = ph; t.secureTextEntry = sec; t.autocorrectionType = UITextAutocorrectionTypeNo; t.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addAction:[UIAlertAction actionWithTitle:T(@"إلغاء", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:T(@"تم", @"OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { cb(a.textFields.firstObject.text ?: @""); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)rebuild {
    for (UIView *v in self.view.subviews) [v removeFromSuperview];
    __weak typeof(self) ws = self;
    self.view.backgroundColor = RY_BG; self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; self.view.semanticContentAttribute = RYSem();

    UILabel *title = RYLabel(RYBrand(), 22, UIFontWeightHeavy, nil); title.numberOfLines = 1;
    UIView *spacer = [UIView new]; [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *close = RYBtn(T(@"إغلاق", @"Close"), NO, ^{ [ws dismissViewControllerAnimated:YES completion:nil]; });
    UIStackView *head = RYHStack(@[title, spacer, close], 8);
    UIScrollView *tabsScroll = [UIScrollView new]; tabsScroll.showsHorizontalScrollIndicator = NO;
    NSArray *names = @[T(@"الخلفيات", @"Backgrounds"), T(@"الدعوات", @"Invites"), T(@"رسائل سريعة", @"Quick messages"), T(@"الأصوات", @"Sounds"), T(@"المايك", @"Mic"), T(@"الإعدادات", @"Settings")];
    NSMutableArray *tb = [NSMutableArray new];
    for (NSInteger i = 0; i < (NSInteger)names.count; i++) { [tb addObject:RYBtn(names[i], i == self.tab, ^{ ws.tab = i; [ws rebuild]; })]; }
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil;
    UIStackView *tabStack = RYHStack(tb, 8); tabStack.alignment = UIStackViewAlignmentFill;
    UIScrollView *scroll = [UIScrollView new]; scroll.alwaysBounceVertical = YES; scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.stack = RYVStack(@[], 12);

    for (UIView *v in @[head, tabsScroll, scroll]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:v]; }
    [tabsScroll addSubview:tabStack]; [scroll addSubview:self.stack];
    tabStack.translatesAutoresizingMaskIntoConstraints = NO; self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *sg = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:18],
        [head.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor constant:16], [head.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor constant:-16],
        [tabsScroll.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:12],
        [tabsScroll.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor], [tabsScroll.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor],
        [tabsScroll.heightAnchor constraintEqualToConstant:40],
        [tabStack.topAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.topAnchor], [tabStack.bottomAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.bottomAnchor],
        [tabStack.leadingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.leadingAnchor constant:16], [tabStack.trailingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.trailingAnchor constant:-16],
        [tabStack.heightAnchor constraintEqualToAnchor:tabsScroll.frameLayoutGuide.heightAnchor],
        [scroll.topAnchor constraintEqualToAnchor:tabsScroll.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16], [self.stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-60],
        [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];

    if (RYLocked()) { [self renderLocked]; return; }
    switch (self.tab) { case 0: [self renderBG]; break; case 1: [self renderInvites]; break; case 2: [self renderMsgs]; break; case 3: [self renderSounds]; break; case 4: [self renderMic]; break; default: [self renderSettings]; }
}

#pragma mark Locked
- (void)renderLocked {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"اللوحة مقفلة", @"Panel is locked"), 17, UIFontWeightBold, nil),
        RYLabel(T(@"اكتب المفتاح مرة وحدة عشان تفتحها.", @"Type your key once to unlock."), 14, UIFontWeightRegular, RY_MUTED),
        RYBtn(T(@"فتح", @"Unlock"), YES, ^{
            [ws ask:T(@"المفتاح", @"Key") ph:@"" secure:YES ok:^(NSString *s) {
                if ([RYHash(s) isEqualToString:CF(@"keyHash", @"")]) { CS(@"unlocked", @YES); [ws rebuild]; }
                else [ws toast:T(@"المفتاح غلط", @"Wrong key")];
            }];
        })])];
}

#pragma mark Backgrounds
- (void)setBG:(NSString *)mode value:(NSString *)v { CS(@"bgMode", mode); CS(@"bgValue", v); [[RYCore shared] bump]; }
- (void)renderBG {
    __weak typeof(self) ws = self;
    UIButton *photo = RYBtn(T(@"من الاستوديو", @"Photo library"), YES, ^{
        PHPickerConfiguration *c = [PHPickerConfiguration new]; c.filter = [PHPickerFilter imagesFilter]; c.selectionLimit = 1;
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c]; p.delegate = ws; [ws presentViewController:p animated:YES completion:nil];
    });
    UIButton *url = RYBtn(T(@"رابط صورة", @"Image URL"), NO, ^{
        [ws ask:T(@"رابط الصورة (https)", @"Image URL (https)") ph:@"https://" secure:NO ok:^(NSString *s) {
            NSURL *u = [NSURL URLWithString:[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
            if (!u || ![u.scheme isEqual:@"https"]) { [ws toast:T(@"لازم رابط https", @"Needs an https link")]; return; }
            [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { [ws saveBGData:d]; }] resume];
        }];
    });
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"خلفية الغرفة (تشوفها أنت بس)", @"Room background (only you see it)"), 15, UIFontWeightBold, nil), RYHStack(@[photo, url], 8)])];

    NSMutableArray *sw = [NSMutableArray new];
    for (NSString *h in @[@"#000000", @"#111827", @"#1E1B4B", @"#052E16", @"#450A0A", @"#3B0764", @"#0C4A6E", @"#78350F"]) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.backgroundColor = RYHex(h); b.layer.cornerRadius = 10; b.layer.borderWidth = 1; b.layer.borderColor = RY_MUTED.CGColor;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws setBG:@"color" value:h]; [ws toast:T(@"تم", @"Done")]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:40].active = YES; [sw addObject:b];
    }
    UIButton *custom = RYBtn(T(@"لون مخصص", @"Custom colour"), NO, ^{
        UIColorPickerViewController *cp = [UIColorPickerViewController new]; cp.delegate = ws; [ws presentViewController:cp animated:YES completion:nil];
    });
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"لون ثابت", @"Solid colour"), 15, UIFontWeightBold, nil), RYGrid(sw, 4), custom])];

    NSMutableArray *gs = [NSMutableArray new];
    for (NSString *g in @[@"#0F2027,#2C5364", @"#41295A,#2F0743", @"#FF512F,#DD2476", @"#00C6FF,#0072FF", @"#11998E,#38EF7D", @"#232526,#414345"]) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; [b setBackgroundImage:RYGradImage(g) forState:UIControlStateNormal]; b.layer.cornerRadius = 10; b.clipsToBounds = YES;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws setBG:@"gradient" value:g]; [ws toast:T(@"تم", @"Done")]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:44].active = YES; [gs addObject:b];
    }
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"تدرجات", @"Gradients"), 15, UIFontWeightBold, nil), RYGrid(gs, 3)])];

    [self.stack addArrangedSubview:RYSlider(T(@"التمويه (Blur)", @"Blur"), 0, 100, [CF(@"blur", @0) floatValue], ^(float v) { CS(@"blur", @(v)); [[RYCore shared] bump]; })];
    [self.stack addArrangedSubview:RYSlider(T(@"التعتيم (Dim)", @"Dim"), 0, 100, [CF(@"dim", @30) floatValue], ^(float v) { CS(@"dim", @(v)); [[RYCore shared] bump]; })];
    [self.stack addArrangedSubview:RYBtn(T(@"رجوع للافتراضي", @"Reset to default"), NO, ^{
        [ws setBG:@"none" value:@""]; CS(@"blur", @0); CS(@"dim", @30); [ws rebuild]; [ws toast:T(@"تم الرجوع للافتراضي", @"Reset")];
    })];
}
- (void)saveBGData:(NSData *)d {
    if (!d.length) { [self toast:T(@"فشل التحميل", @"Failed to load")]; return; }
    if (d.length > 12 * 1024 * 1024) { [self toast:T(@"الصورة كبيرة (أكثر من 12MB)", @"Image too large (>12MB)")]; return; }
    CGImageSourceRef s = CGImageSourceCreateWithData((__bridge CFDataRef)d, NULL); if (!s) { [self toast:T(@"ملف غير صالح", @"Invalid image")]; return; }
    NSDictionary *pr = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(s, 0, NULL)); CFRelease(s);
    if (MAX([pr[@"PixelWidth"] intValue], [pr[@"PixelHeight"] intValue]) > 4096) { [self toast:T(@"أبعاد الصورة كبيرة (أكثر من 4096px)", @"Image dimensions too large (>4096px)")]; return; }
    UIImage *im = [UIImage imageWithData:d]; NSData *j = im ? UIImageJPEGRepresentation(im, 0.9) : nil;
    if (!j || ![j writeToFile:[RYDir(nil) stringByAppendingPathComponent:@"bg.jpg"] atomically:YES]) { [self toast:T(@"تعذر الحفظ", @"Could not save")]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self setBG:@"image" value:@"bg.jpg"]; [self toast:T(@"تم تعيين الخلفية", @"Background set")]; });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *r = results.firstObject; if (!r) return;
    __weak typeof(self) ws = self;
    [r.itemProvider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *d, NSError *e) { [ws saveBGData:d]; }];
}
- (void)colorPickerViewController:(UIColorPickerViewController *)vc didSelectColor:(UIColor *)color continuously:(BOOL)c { [self setBG:@"color" value:RYHexFrom(color)]; }

#pragma mark Invites
- (NSString *)invText {
    RYCore *c = [RYCore shared];
    if (c.invRunning) return [NSString stringWithFormat:T(@"شغّال… انرسل %ld دعوة\n%@", @"Running… %ld sent\n%@"), (long)c.invSent, c.invStatus ?: @""];
    NSInteger left = [c invCooldownLeft];
    if (left > 0) return [NSString stringWithFormat:T(@"آخر تشغيل: %ld دعوة. تقدر تشغّل بعد %ld:%02ld", @"Last run: %ld sent. Available again in %ld:%02ld"), (long)c.invSent, (long)(left / 60), (long)(left % 60)];
    return c.invStatus.length ? c.invStatus : T(@"جاهز", @"Ready");
}
- (void)renderInvites {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYCard(@[
        RYLabel(T(@"دعوة كل اللي بالقائمة", @"Invite everyone in the list"), 16, UIFontWeightBold, nil),
        RYLabel(T(@"افتح شاشة الريسنت (أو الأصدقاء) في Rave، وخلّها ظاهرة، وبعدين اضغط ابدأ. يمر على كل شخص مرة وحدة بس، وبعدها يوقف. ما يعيد الإرسال لنفس الناس.", @"Open the Recents (or Friends) screen in Rave and keep it visible, then press Start. It goes through each person once and stops. It never re-sends to the same people."), 13, UIFontWeightRegular, RY_MUTED)])];
    self.invLabel = RYLabel([self invText], 14, UIFontWeightMedium, nil);
    UIButton *go = RYBtn(T(@"ابدأ الدعوات", @"Start invites"), YES, ^{
        RYCore *c = [RYCore shared];
        if (c.invRunning) return;
        if ([c invCooldownLeft] > 0) { [ws toast:T(@"انتظر انتهاء المؤقت (4 دقايق)", @"Wait for the 4-minute cooldown")]; return; }
        UIAlertController *a = [UIAlertController alertControllerWithTitle:T(@"تأكيد", @"Confirm") message:T(@"إرسال دعوة لكل شخص ظاهر في القائمة الحالية (مرة وحدة)؟", @"Send one invite to everyone in the current list?") preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:T(@"إلغاء", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:T(@"ابدأ", @"Start") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [c startInvites]; [ws startInvUI]; }]];
        [ws presentViewController:a animated:YES completion:nil];
    });
    UIButton *stop = RYBtn(T(@"إيقاف", @"Stop"), NO, ^{ [[RYCore shared] stopInvites]; });
    [self.stack addArrangedSubview:RYCard(@[self.invLabel, RYHStack(@[go, stop], 8)])];
    [self.stack addArrangedSubview:RYLabel(T(@"ملاحظة: يعتمد على أزرار الدعوة الموجودة بالشاشة. لو ما اشتغل انسخ \"تقرير تشخيصي\" من الإعدادات وأرسله لي.", @"Note: it drives the invite buttons that are on screen. If nothing happens, copy the diagnostic report from Settings and send it to me."), 12, UIFontWeightRegular, RY_MUTED)];
    [self startInvUI];
}
- (void)startInvUI {
    [self.invUI invalidate]; __weak typeof(self) ws = self;
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { ws.invLabel.text = [ws invText]; }];
}

#pragma mark Quick messages
- (void)renderMsgs {
    __weak typeof(self) ws = self;
    NSArray *msgs = CF(@"messages", @[@"👋", @"😂", @"🔥", @"ثواني وأرجع"]);
    [self.stack addArrangedSubview:RYLabel(T(@"اضغط على الرسالة لإرسالها مرة وحدة للدردشة.", @"Tap a message to send it once to the room chat."), 13, UIFontWeightRegular, RY_MUTED)];
    for (NSUInteger i = 0; i < msgs.count; i++) {
        NSString *m = msgs[i];
        UIButton *send = RYBtn(m, YES, ^{
            [[RYCore shared] sendMessage:m done:^(NSInteger code) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [ws toast:code == 0 ? T(@"تم الإرسال", @"Sent") : code == 1 ? T(@"ما لقيت خانة الدردشة", @"Chat input not found") : T(@"ما انرسلت، افتح الدردشة وجرّب", @"Not sent, open the chat and retry")];
                });
            }];
        });
        UIButton *del = RYBtn(@"✕", NO, ^{ NSMutableArray *a = [msgs mutableCopy]; [a removeObjectAtIndex:i]; CS(@"messages", a); [ws rebuild]; });
        [del setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row = RYHStack(@[send, del], 8); row.alignment = UIStackViewAlignmentFill; [self.stack addArrangedSubview:row];
    }
    [self.stack addArrangedSubview:RYBtn(T(@"+ إضافة رسالة", @"+ Add message"), NO, ^{
        [ws ask:T(@"الرسالة", @"Message") ph:@"" secure:NO ok:^(NSString *s) {
            s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!s.length) return;
            NSMutableArray *a = [msgs mutableCopy]; [a addObject:s]; CS(@"messages", a); [ws rebuild];
        }];
    })];
}

#pragma mark Sounds
- (void)renderSounds {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYLabel(T(@"الأصوات تشتغل على جوالك بس (ما تنرسل للغرفة).", @"Sounds play on your device only (not sent to the room)."), 13, UIFontWeightRegular, RY_MUTED)];
    [self.stack addArrangedSubview:RYSlider(T(@"مستوى الصوت", @"Volume"), 0, 1, [CF(@"vol", @0.8) floatValue], ^(float v) { CS(@"vol", @(v)); })];
    NSMutableArray *bs = [NSMutableArray new]; NSArray *nm = RYBuiltinNames();
    for (NSInteger i = 0; i < (NSInteger)nm.count; i++) [bs addObject:RYBtn(T(nm[i][0], nm[i][1]), NO, ^{ RYPlayData(RYBuiltinData(i), nil); })];
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"أصوات جاهزة", @"Built-in"), 15, UIFontWeightBold, nil), RYGrid(bs, 2)])];

    NSMutableArray *rows = [NSMutableArray arrayWithObject:RYLabel(T(@"أصواتي", @"My sounds"), 15, UIFontWeightBold, nil)];
    for (NSString *f in RYSoundFiles()) {
        NSString *path = [RYDir(@"sounds") stringByAppendingPathComponent:f];
        UIButton *play = RYBtn(f.stringByDeletingPathExtension, NO, ^{ RYPlayData(nil, [NSURL fileURLWithPath:path]); });
        UIButton *del = RYBtn(@"✕", NO, ^{ [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; [ws rebuild]; });
        [del setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *r = RYHStack(@[play, del], 8); r.alignment = UIStackViewAlignmentFill; [rows addObject:r];
    }
    [rows addObject:RYBtn(T(@"+ إضافة صوت من الملفات", @"+ Add sound from Files"), YES, ^{
        UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
        p.delegate = ws; [ws presentViewController:p animated:YES completion:nil];
    })];
    [self.stack addArrangedSubview:RYCard(rows)];
    [self.stack addArrangedSubview:RYBtn(T(@"إيقاف الكل", @"Stop all"), NO, ^{ RYStopAll(); })];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        NSNumber *sz = nil; [u getResourceValue:&sz forKey:NSURLFileSizeKey error:nil];
        if (sz.longLongValue > 15 * 1024 * 1024) { [self toast:T(@"الملف كبير (أكثر من 15MB)", @"File too large (>15MB)")]; continue; }
        NSString *dst = [RYDir(@"sounds") stringByAppendingPathComponent:u.lastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
        NSError *e = nil; [[NSFileManager defaultManager] copyItemAtURL:u toURL:[NSURL fileURLWithPath:dst] error:&e];
        if (e) [self toast:T(@"تعذر النسخ", @"Copy failed")];
    }
    [self rebuild];
}

#pragma mark Mic
- (void)renderMic {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYLabel(T(@"يرفع صوت مايكك اللي ينرسل للغرفة (مو صوتك المحلي). ابدأ بـ 2x، ولو سمعوك مشوّش أو فيه خشخشة نزّله. فعّله قبل ما تفتح المايك في الغرفة، ولو ما اشتغل أعد فتح المايك.", @"Boosts the mic level sent to the room. Start at 2x and lower it if it distorts or gets noisy. Turn it on before you open the mic in a room; if it does nothing, toggle the mic again."), 13, UIFontWeightRegular, RY_MUTED)];
    UISwitch *iso = [UISwitch new]; iso.on = gNoIso; iso.onTintColor = RYAccent(); __weak UISwitch *wiso = iso;
    [iso addAction:[UIAction actionWithHandler:^(UIAction *a) { RYSetNoIso(wiso.on); [ws toast:T(@"أعد فتح المايك أو ادخل الغرفة من جديد", @"Toggle the mic or rejoin the room to apply")]; }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"إيقاف العوازل (كتم الضوضاء / التحكم التلقائي)", @"Disable isolation (noise suppression / auto gain)"), 15, UIFontWeightBold, nil), iso], 12),
        RYLabel(T(@"يوقف معالجة الصوت اللي تكتم الصوت العالي. بدون سماعة ممكن يرجع صدى. يتطبق عند فتح المايك من جديد.", @"Stops the processing that mutes loud speech. Without headphones echo may return. Applies when the mic restarts."), 12, UIFontWeightRegular, RY_MUTED)])];
    UISwitch *sw = [UISwitch new]; sw.on = gMicOn; sw.onTintColor = RYAccent(); __weak UISwitch *wsw = sw;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) { RYSetMic(wsw.on, gMicGain); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"تفعيل مضخم المايك", @"Enable mic booster"), 15, UIFontWeightBold, nil), sw], 12)])];
    [self.stack addArrangedSubview:RYSlider(T(@"مقدار التضخيم (1x - 5x)", @"Boost amount (1x - 5x)"), 1, 5, gMicGain, ^(float v) { RYSetMic(gMicOn, v); })];
    NSMutableArray *ps = [NSMutableArray new];
    for (NSNumber *g in @[@1.5, @2, @3, @4]) {
        [ps addObject:RYBtn([NSString stringWithFormat:@"%gx", g.floatValue], gMicGain == g.floatValue, ^{ RYSetMic(gMicOn, g.floatValue); [ws rebuild]; })];
    }
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"جاهز", @"Presets"), 15, UIFontWeightBold, nil), RYGrid(ps, 4)])];
}

#pragma mark Settings
- (void)renderSettings {
    __weak typeof(self) ws = self;
    UISegmentedControl *lang = [[UISegmentedControl alloc] initWithItems:@[T(@"تلقائي", @"Auto"), @"العربية", @"English"]];
    NSString *cur = CF(@"lang", @"ar"); lang.selectedSegmentIndex = [cur isEqual:@"auto"] ? 0 : [cur isEqual:@"ar"] ? 1 : 2;
    __weak UISegmentedControl *wl = lang;
    [lang addAction:[UIAction actionWithHandler:^(UIAction *a) { CS(@"lang", @[@"auto", @"ar", @"en"][wl.selectedSegmentIndex]); [ws rebuild]; }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"لغة الواجهة", @"Language"), 15, UIFontWeightBold, nil), lang])];

    NSMutableArray *ac = [NSMutableArray new]; NSArray *accs = RYAccents();
    for (NSInteger i = 0; i < (NSInteger)accs.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.backgroundColor = RYHex(accs[i]); b.layer.cornerRadius = 18;
        if ([CF(@"accent", @0) integerValue] == i) { b.layer.borderWidth = 3; b.layer.borderColor = UIColor.whiteColor.CGColor; }
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { CS(@"accent", @(i)); [ws rebuild]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:36].active = YES; [ac addObject:b];
    }
    UIStackView *accRow = RYHStack(ac, 8); accRow.distribution = UIStackViewDistributionFillEqually; accRow.alignment = UIStackViewAlignmentFill;
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"لون التمييز", @"Accent colour"), 15, UIFontWeightBold, nil), accRow])];

    UISwitch *sw = [UISwitch new]; sw.on = [CF(@"autoOpen", @NO) boolValue]; sw.onTintColor = RYAccent(); __weak UISwitch *wsw = sw;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) { CS(@"autoOpen", @(wsw.on)); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"افتح اللوحة تلقائيًا عند دخول الغرفة", @"Open panel automatically when I enter a room"), 14, UIFontWeightMedium, nil), sw], 12)])];

    NSMutableArray *key = [NSMutableArray arrayWithObject:RYLabel(T(@"مفتاح الفتح", @"Unlock key"), 15, UIFontWeightBold, nil)];
    [key addObject:RYLabel(T(@"يتخزن الهاش (SHA-256) فقط، مو المفتاح نفسه.", @"Only the SHA-256 hash is stored, never the key."), 13, UIFontWeightRegular, RY_MUTED)];
    [key addObject:RYBtn(T(@"تعيين / تغيير المفتاح", @"Set / change key"), NO, ^{
        [ws ask:T(@"مفتاح جديد (3 أحرف أو أكثر)", @"New key (3+ chars)") ph:@"" secure:YES ok:^(NSString *s) {
            if (s.length < 3) { [ws toast:T(@"المفتاح قصير", @"Key too short")]; return; }
            CS(@"keyHash", RYHash(s)); CS(@"unlocked", @YES); [ws rebuild]; [ws toast:T(@"تم حفظ المفتاح", @"Key saved")];
        }];
    })];
    if (CF(@"keyHash", nil)) [key addObject:RYBtn(T(@"قفل مرة ثانية", @"Lock again"), YES, ^{ CS(@"unlocked", @NO); [ws rebuild]; })];
    [self.stack addArrangedSubview:RYCard(key)];

    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"نسخ احتياطي", @"Backup"), 15, UIFontWeightBold, nil),
        RYHStack(@[RYBtn(T(@"تصدير (نسخ)", @"Export (copy)"), NO, ^{ [ws exportCfg]; }), RYBtn(T(@"استيراد (من الحافظة)", @"Import (clipboard)"), NO, ^{ [ws importCfg]; })], 8)])];

    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"متقدم (للضبط)", @"Advanced (tuning)"), 15, UIFontWeightBold, nil),
        RYLabel(T(@"لو الزر ما يظهر بالغرفة أو الشعار ما تغيّر، استخدم هذي.", @"If the button doesn't show in a room or the logo isn't replaced, use these."), 13, UIFontWeightRegular, RY_MUTED),
        RYBtn(T(@"نسخ قائمة الشاشات", @"Copy screen list"), NO, ^{
            NSMutableString *o = [NSMutableString new]; for (UIWindow *w in RYAppWindows()) RYDump(w.rootViewController, 0, o);
            UIPasteboard.generalPasteboard.string = o; [ws toast:T(@"اننسخت قائمة الشاشات", @"Screen list copied")];
        }),
        RYBtn(T(@"نسخ أسماء الصور بالشاشة", @"Copy on-screen image names"), NO, ^{ UIPasteboard.generalPasteboard.string = RYImageReport(); [ws toast:T(@"اننسخت", @"Copied")]; }),
        RYBtn(T(@"نسخ تقرير تشخيصي", @"Copy diagnostic report"), YES, ^{ UIPasteboard.generalPasteboard.string = RYReport(); [ws toast:T(@"اننسخ التقرير", @"Report copied")]; }),
        RYBtn([NSString stringWithFormat:T(@"اسم العلامة: %@", @"Brand name: %@"), RYBrand()], NO, ^{
            [ws ask:T(@"الاسم اللي يظهر بدل rave", @"Name shown instead of rave") ph:@"Layan" secure:NO ok:^(NSString *x) { CS(@"brandName", x.length ? x : nil); [ws rebuild]; }];
        }),
        RYBtn([NSString stringWithFormat:T(@"اسم شاشة الغرفة: %@", @"Room screen class: %@"), CF(@"roomClass", RY_ROOM_DEFAULT)], NO, ^{
            [ws ask:T(@"اسم الكلاس", @"Class name") ph:RY_ROOM_DEFAULT secure:NO ok:^(NSString *s) { CS(@"roomClass", s.length ? s : nil); [ws rebuild]; }];
        }),
        RYBtn([NSString stringWithFormat:T(@"كلمات الشعار: %@", @"Logo match words: %@"), CF(@"brand", RY_BRAND_TOKENS)], NO, ^{
            [ws ask:T(@"كلمات مفصولة بفاصلة (فاضي = إيقاف)", @"Comma-separated (empty = off)") ph:@"logo" secure:NO ok:^(NSString *s) { CS(@"brand", s); [ws rebuild]; }];
        })])];
}
- (void)exportCfg {
    NSMutableDictionary *d = [gCfg mutableCopy]; [d removeObjectsForKeys:@[@"keyHash", @"unlocked"]];
    NSData *j = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
    if (!j) { [self toast:T(@"فشل التصدير", @"Export failed")]; return; }
    UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding];
    [self toast:T(@"اننسخت الإعدادات للحافظة", @"Settings copied to clipboard")];
}
- (void)importCfg {
    NSData *j = [UIPasteboard.generalPasteboard.string dataUsingEncoding:NSUTF8StringEncoding];
    id o = j ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    if (![o isKindOfClass:NSDictionary.class]) { [self toast:T(@"الحافظة ما فيها نسخة صالحة", @"Clipboard has no valid backup")]; return; }
    for (NSString *k in @[@"lang", @"accent", @"autoOpen", @"bgMode", @"bgValue", @"blur", @"dim", @"vol", @"messages", @"brand", @"roomClass", @"bx", @"by", @"micOn", @"micGain", @"noIso"]) if (o[k]) CS(k, o[k]);
    gNoIso = [CF(@"noIso", @YES) boolValue];
    gMicOn = [CF(@"micOn", @NO) boolValue]; gMicGain = [CF(@"micGain", @2.0) floatValue];
    if ([CF(@"bgMode", @"") isEqual:@"image"] && ![[NSFileManager defaultManager] fileExistsAtPath:[RYDir(nil) stringByAppendingPathComponent:@"bg.jpg"]]) CS(@"bgMode", @"none");
    [[RYCore shared] bump]; [self rebuild]; [self toast:T(@"تم الاستيراد", @"Imported")];
}
@end

#pragma mark - Core

#pragma mark Invites engine
static NSMutableSet *gInvDone; static int gInvIdle; static NSTimer *gInvTimer; static NSTimeInterval gInvLast;
static NSArray<UIView *> *RYVisibleCells(UIScrollView *sv);
static id RYInviteCtl(UIView *cell);
static UIScrollView *RYListIn(UIView *root) {
    __block UIScrollView *best = nil; __block CGFloat ba = 0; __block BOOL bestHasInvite = NO;
    RYWalk(root, 0, ^(UIView *x, int d) {
        if (!([x isKindOfClass:UITableView.class] || [x isKindOfClass:UICollectionView.class]) || !RYVisible(x)) return;
        CGRect f = CGRectIntersection([x convertRect:x.bounds toView:nil], x.window.bounds); if (CGRectIsNull(f)) return;
        CGFloat a = f.size.width * f.size.height;
        BOOL has = NO;
        for (UIView *c in RYVisibleCells((UIScrollView *)x)) { if (RYInviteCtl(c)) { has = YES; break; } }
        if ((has && !bestHasInvite) || (has == bestHasInvite && a > ba)) { ba = a; best = (UIScrollView *)x; bestHasInvite = has; }
    });
    return best;
}
// prefer the visible invite-friends screen; the room chat list is bigger and would win otherwise
static UIScrollView *RYBiggestList(void) {
    NSMutableArray *vcs = [NSMutableArray new];
    for (UIWindow *w in RYAppWindows()) RYScanAll(w.rootViewController, CF(@"inviteClass", @"FriendsManagementViewController"), 0, vcs);
    for (UIViewController *vc in vcs) { if (!RYVisible(vc.view)) continue; UIScrollView *l = RYListIn(vc.view); if (l) return l; }
    UIScrollView *best = nil;
    for (UIWindow *w in RYAppWindows()) { UIScrollView *x = RYListIn(w); if (x) { best = x; break; } }
    return best;
}
static NSArray<UIView *> *RYVisibleCells(UIScrollView *sv) {
    if ([sv isKindOfClass:UITableView.class]) return ((UITableView *)sv).visibleCells;
    return ((UICollectionView *)sv).visibleCells;
}
static void RYCellTexts(UIView *v, NSMutableString *o, int d) {
    if (d > 10) return;
    if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) [o appendFormat:@"%@|", ((UILabel *)v).text];
    for (UIView *s in v.subviews) RYCellTexts(s, o, d + 1);
}
// the invite control inside a row: key contains an invite word, and none of the "already done" words
static id RYInviteCtl(UIView *cell) {
    NSMutableArray *c = [NSMutableArray new]; RYCollectCtl(cell, c, 0);
    NSArray *good = @[@"invite", @"دعو", @"دعوه", @"add to room", @"person.badge.plus", @"plus"];
    NSArray *bad = @[@"invited", @"تمت", @"تم ", @"sent", @"pending", @"remove", @"block", @"report", @"unfriend", @"chat", @"message"];
    for (UIControl *b in c) {
        NSString *k = RYCtlKey(b); BOOL skip = NO;
        for (NSString *w in bad) if ([k containsString:w]) { skip = YES; break; }
        if (skip) continue;
        for (NSString *w in good) if ([k containsString:w]) return b;
    }
    NSMutableArray *ax = [NSMutableArray new]; RYA11yCollect(cell, ax, 0);
    for (id e in ax) {
        NSString *k = RYA11yKey(e); BOOL skip = NO;
        for (NSString *w in bad) if ([k containsString:w]) { skip = YES; break; }
        if (skip) continue;
        for (NSString *w in good) if ([k containsString:w]) return e;
    }
    return nil;
}
@implementation RYCore
+ (instancetype)shared { static RYCore *c; static dispatch_once_t t; dispatch_once(&t, ^{ c = [RYCore new]; }); return c; }
- (void)bump { self.stamp++; }

- (void)start {
    if (self.win) return;
    UIWindowScene *sc = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) { sc = (UIWindowScene *)s; break; }
    if (!sc) { [self performSelector:@selector(start) withObject:nil afterDelay:1.0]; return; }
    self.win = [[RYWindow alloc] initWithWindowScene:sc]; self.win.windowLevel = UIWindowLevelAlert + 50; self.win.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; self.win.rootViewController = root; self.win.hidden = NO;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.frame = CGRectMake(0, 0, 52, 52); b.layer.cornerRadius = 26;
    b.backgroundColor = RYAccent(); b.tintColor = UIColor.whiteColor; b.layer.shadowOpacity = 0.4; b.layer.shadowRadius = 6; b.layer.shadowOffset = CGSizeMake(0, 3);
    [b setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    __weak typeof(self) ws = self; [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws openPanel]; }] forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    CGSize sz = root.view.bounds.size;
    b.center = CGPointMake([CF(@"bx", @(sz.width - 40)) doubleValue], [CF(@"by", @(sz.height * 0.35)) doubleValue]);
    b.hidden = YES; [root.view addSubview:b]; self.fab = b;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view; CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y); [g setTranslation:CGPointZero inView:v.superview];
    if (g.state == UIGestureRecognizerStateEnded) {
        CGSize s = v.superview.bounds.size; UIEdgeInsets in = v.superview.safeAreaInsets;
        CGFloat x = MIN(MAX(v.center.x, 30), s.width - 30), y = MIN(MAX(v.center.y, in.top + 30), s.height - in.bottom - 30);
        [UIView animateWithDuration:0.2 animations:^{ v.center = CGPointMake(x, y); }]; CS(@"bx", @(x)); CS(@"by", @(y));
    }
}
- (void)openPanel {
    UIViewController *root = self.win.rootViewController; if (root.presentedViewController) return;
    self.prevKey = nil; for (UIWindow *w in RYAppWindows()) if (w.isKeyWindow) { self.prevKey = w; break; }
    RYPanel *p = [RYPanel new]; p.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sp = p.sheetPresentationController;
    if (sp) { sp.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent]; sp.prefersGrabberVisible = YES; }
    [root presentViewController:p animated:YES completion:^{ [self.win makeKeyWindow]; }];
}
- (void)panelClosed { [self.prevKey makeKeyWindow]; }

- (void)tick {
    UIViewController *room = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT));
    BOOL in = room != nil;
    self.fab.hidden = !in; self.fab.backgroundColor = RYAccent();
    if (in && !self.wasIn && [CF(@"autoOpen", @NO) boolValue] && !RYLocked()) [self openPanel];
    self.wasIn = in;
    [self syncBG:room];
    NSString *pat = CF(@"brand", RY_BRAND_TOKENS);
    if (pat.length) {
        NSMutableArray *toks = [NSMutableArray new];
        for (NSString *t in [pat.lowercaseString componentsSeparatedByString:@","]) { NSString *x = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]; if (x.length) [toks addObject:x]; }
        for (UIWindow *w in RYAppWindows()) RYBrandWalk(w, toks);
    }
}
- (void)syncBG:(UIViewController *)room {
    BOOL want = room && ![CF(@"bgMode", @"none") isEqual:@"none"];
    if (!want) {
        if (self.bgView) { [self.bgView removeFromSuperview]; self.bgView = nil; self.bgHost = nil; RYRestoreAll(); }
        return;
    }
    UIView *host = RYFullHost(room.view);
    if (self.bgView && self.bgView.superview != host) { [self.bgView removeFromSuperview]; self.bgView = nil; RYRestoreAll(); }
    if (!self.bgView) {
        self.bgView = [[RYBGView alloc] initWithFrame:host.bounds]; self.bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:self.bgView atIndex:0]; self.bgView.stamp = -1;
    } else if (host.subviews.firstObject != self.bgView) { [host sendSubviewToBack:self.bgView]; }
    self.bgHost = host;
    // make everything that would hide the wallpaper see-through (re-applied every tick: the app resets colours on layout)
    RYClear(host);
    for (UIView *p = host.superview; p && ![p isKindOfClass:UIWindow.class]; p = p.superview) if (RYHasBG(p)) RYClear(p);
    RYClearBig(host, host, self.bgView, 0);
    if (self.bgView.stamp != self.stamp) { [self.bgView apply]; self.bgView.stamp = self.stamp; }
}
- (NSInteger)invCooldownLeft { if (!gInvLast) return 0; NSInteger l = (NSInteger)(240 - ([NSDate date].timeIntervalSince1970 - gInvLast)); return l > 0 ? l : 0; }
- (void)stopInvites {
    [gInvTimer invalidate]; gInvTimer = nil;
    if (self.invRunning) { self.invRunning = NO; gInvLast = [NSDate date].timeIntervalSince1970; self.invStatus = [NSString stringWithFormat:T(@"وقف. انرسل %ld دعوة.", @"Stopped. %ld invites sent."), (long)self.invSent]; }
}
- (void)startInvites {
    if (self.invRunning || [self invCooldownLeft] > 0) return;
    gInvDone = [NSMutableSet new]; gInvIdle = 0; self.invSent = 0; self.invRunning = YES; self.invStatus = T(@"أبحث عن القائمة…", @"Looking for the list…");
    gInvTimer = [NSTimer scheduledTimerWithTimeInterval:0.9 target:self selector:@selector(invStep) userInfo:nil repeats:YES];
}
- (void)invFinish:(NSString *)why {
    [gInvTimer invalidate]; gInvTimer = nil; self.invRunning = NO; gInvLast = [NSDate date].timeIntervalSince1970;
    self.invStatus = [NSString stringWithFormat:@"%@ %ld", why, (long)self.invSent];
}
- (void)invStep {
    UIScrollView *sv = RYBiggestList();
    if (!sv) { if (++gInvIdle > 6) [self invFinish:T(@"ما لقيت قائمة بالشاشة. انرسل:", @"No list on screen. Sent:")]; return; }
    for (UIView *cell in RYVisibleCells(sv)) {
        NSMutableString *key = [NSMutableString new]; RYCellTexts(cell, key, 0);
        if (!key.length) [key appendFormat:@"%p", cell];
        if ([gInvDone containsObject:key]) continue;
        id b = RYInviteCtl(cell);
        [gInvDone addObject:key];
        if (b) { if ([b isKindOfClass:UIControl.class]) [(UIControl *)b sendActionsForControlEvents:UIControlEventTouchUpInside]; else [b accessibilityActivate]; self.invSent++; self.invStatus = [NSString stringWithFormat:T(@"آخر واحد: %@", @"Last: %@"), RYClip(key, 24)]; gInvIdle = 0; return; }
    }
    // nothing new on this screenful: scroll one page; stop after two failed scrolls at the end
    CGFloat maxY = sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.size.height;
    if (sv.contentOffset.y >= maxY - 2) { if (++gInvIdle >= 2) [self invFinish:T(@"خلصت القائمة. انرسل:", @"Reached the end. Sent:")]; return; }
    [sv setContentOffset:CGPointMake(sv.contentOffset.x, MIN(maxY, sv.contentOffset.y + sv.bounds.size.height * 0.8)) animated:NO];
    gInvIdle = 0;
}
- (void)sendMessage:(NSString *)msg done:(void (^)(NSInteger))done {
    UIViewController *room = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT));
    UIViewController *chat = RYFindVC(CF(@"chatClass", RY_CHAT_DEFAULT));
    UIView *in = chat ? RYBottomInput(chat.view) : nil;
    if (!in && room) in = RYBottomInput(RYFullHost(room.view));
    if (!in) for (UIWindow *w in RYAppWindows()) { in = RYBottomInput(w); if (in) break; }
    if (!in) { done(1); return; }
    NSString *prev = RYGetText(in) ?: @"";
    RYSetText(in, msg);
    UIControl *btn = RYSendBtnNear(in);
    if (btn) [btn sendActionsForControlEvents:UIControlEventTouchUpInside]; else RYPressReturn(in);
    __weak UIView *wi = in;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *x = wi;
        if (!x || ![RYGetText(x) isEqualToString:msg]) { done(0); return; }   // field was cleared by the app = sent
        RYPressReturn(x);                                                       // second try: return key
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *y = wi;
            if (!y || ![RYGetText(y) isEqualToString:msg]) { done(0); } else { RYSetText(y, prev); done(2); }
        });
    });
}
@end

#pragma mark - Entry

__attribute__((constructor)) static void RYInit(void) {
    if (![[NSBundle mainBundle].bundlePath.pathExtension isEqual:@"app"]) return; // skip app extensions
    RYLoad();
    gMicOn = [CF(@"micOn", @NO) boolValue]; gMicGain = [CF(@"micGain", @2.0) floatValue];
    gNoIso = [CF(@"noIso", @YES) boolValue];
    _dyld_register_func_for_add_image(RYAddImage);
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [[RYCore shared] start]; }];
}
