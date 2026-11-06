// 8ubah — local feature set (injected dylib) (injected dylib)
// Pure Objective-C runtime: no Substrate / no Logos, so it works with Feather / ESign / Sideloadly injection.
// UNTESTED on a device: class names are tunable from Settings > Advanced.

// =====================================================================================================================
// RULE FOR ANY AI / EDITOR THAT MODIFIES THIS FILE  (the owner asked for this, do not break it)
//   NO EXPLANATORY TEXT IN THE UI. Never add help / description / hint / tip / note / warning labels under a title, switch, slider,
//   button or inside a card, in ANY tab or menu (panel tabs, settings, mic, link join, invites, quick messages, backgrounds,
//   lock screen, reports). Every control gets only its own SHORT name.
//   Allowed: short names; short live STATUS lines that show a current value ("Ready", "Saved: 3", "Default ✓"); toasts and alerts that
//   follow an action; text-field placeholders; error messages.
//   New feature? Put the explanation in your reply to the owner, never in the app. If you find an explanation label while editing, delete it.
// =====================================================================================================================
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreLocation/CoreLocation.h>
#include <math.h>
#include <ctype.h>
#include <strings.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <sqlite3.h>
#import <AudioToolbox/AudioToolbox.h>
#import <os/lock.h>

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
    NSString *b = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"8ubah"] copy];
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
    NSData *d = [[@"8ubah|" stringByAppendingString:s ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
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
static UIView *RYSliderV(NSString *title, NSString *unit, float mn, float mx, float val, BOOL logScale, int dec, void (^chg)(float)) {
    UILabel *l = RYLabel(@"", 14, UIFontWeightMedium, nil);
    UISlider *s = [UISlider new]; s.minimumTrackTintColor = RYAccent(); s.minimumValue = 0; s.maximumValue = 1;
    float (^toS)(float) = ^float(float v) { if (v < mn) v = mn; if (v > mx) v = mx; return logScale ? (logf(v) - logf(mn)) / (logf(mx) - logf(mn)) : (v - mn) / (mx - mn); };
    float (^fromS)(float) = ^float(float t) { float v = logScale ? expf(logf(mn) + t * (logf(mx) - logf(mn))) : mn + t * (mx - mn); return dec == 0 ? roundf(v) : v; };
    NSString *(^txt)(float) = ^NSString *(float v) { return [NSString stringWithFormat:@"%@: %.*f %@", title, dec, v, unit]; };
    s.value = toS(val); l.text = txt(val);
    __weak UISlider *ws = s; __weak UILabel *wl = l;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { if (!ws) return; float v = fromS(ws.value); wl.text = txt(v); if (chg) chg(v); }] forControlEvents:UIControlEventValueChanged];
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

#pragma mark - Event log (to find out why a room drops: app lifecycle, audio interruptions, route changes, room open/closed)

static void RYLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt); NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    static NSDateFormatter *df; if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"MM-dd HH:mm:ss"; }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:NSDate.date], m];
    NSString *p = [RYDir(@"logs") stringByAppendingPathComponent:@"events.txt"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!h) { [line writeToFile:p atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    if ([h seekToEndOfFile] > 60000) [h truncateFileAtOffset:0];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
}
static NSString *RYLogTail(void) {
    NSString *t = [NSString stringWithContentsOfFile:[RYDir(@"logs") stringByAppendingPathComponent:@"events.txt"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    return t.length > 3500 ? [t substringFromIndex:t.length - 3500] : t;
}
static void RYStartEventLog(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    RYLog(@"=== launch (pid %d) ===", getpid());
    NSDictionary *names = @{UIApplicationDidEnterBackgroundNotification: @"app: background", UIApplicationWillEnterForegroundNotification: @"app: foreground",
        UIApplicationWillResignActiveNotification: @"app: resign active", UIApplicationDidBecomeActiveNotification: @"app: active",
        UIApplicationDidReceiveMemoryWarningNotification: @"app: MEMORY WARNING", UIApplicationWillTerminateNotification: @"app: will terminate",
        AVAudioSessionMediaServicesWereResetNotification: @"audio: media services reset", NSProcessInfoPowerStateDidChangeNotification: @"power state changed"};
    for (NSString *n in names) { NSString *msg = names[n]; [nc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *x) { RYLog(@"%@", msg); }]; }
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(NSNotification *x) {
        RYLog(@"audio: interruption type=%@ reason=%@", x.userInfo[AVAudioSessionInterruptionTypeKey], x.userInfo[AVAudioSessionInterruptionReasonKey]);
    }];
    [nc addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(NSNotification *x) {
        RYLog(@"audio: route change reason=%@", x.userInfo[AVAudioSessionRouteChangeReasonKey]);
    }];
}

#pragma mark - Join room by link (sideloaded builds lose Universal Links, so we hand the URL to the app ourselves)

static NSURL *RYParseRoomURL(NSString *s) {
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) return nil;
    NSDataDetector *dd = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    NSTextCheckingResult *m = [dd firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    NSURL *u = m.URL;
    if (!u) u = [NSURL URLWithString:[@"https://" stringByAppendingString:s]];
    if (!u.host.length) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
    if ([c.scheme isEqualToString:@"http"]) c.scheme = @"https";
    return c.URL ?: u;
}
// calls the same entry points iOS would call for a tapped link.
// "direct"  = we call the app delegate ourselves (only reaches app-delegate handlers)
// "system"  = we ask iOS to open the app's own custom-scheme URL, so iOS picks the real entry point
//             (application:openURL: or scene:openURLContexts:, whichever this app really uses)
typedef NS_ENUM(NSInteger, RYVia) { RYViaDirect = 0, RYViaSystem = 1, RYViaActivity = 2 };
static NSString *RYMeshID(NSURL *u) {
    NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in c.queryItems) { NSString *n = q.name.lowercaseString; if (([n isEqualToString:@"mesh_id"] || [n isEqualToString:@"meshid"] || [n isEqualToString:@"id"]) && q.value.length >= 6) return q.value; }
    NSString *l = u.path.lastPathComponent; return l.length >= 6 ? l : nil;
}
// Rave 9: the plist lists the Handoff type "com.io.rave.mesh" and the app registers rave:// io.rave:// wemesh:// (older builds: sh.weme.wemesh). Read them from the plist so a rename cannot break us again.
static NSArray<NSString *> *RYMeshActivityTypes(void) {
    NSMutableOrderedSet *s = [NSMutableOrderedSet new];
    for (NSString *t in ([NSBundle.mainBundle objectForInfoDictionaryKey:@"NSUserActivityTypes"] ?: @[])) if ([t.lowercaseString containsString:@"mesh"]) [s addObject:t];
    [s addObject:@"com.io.rave.mesh"]; [s addObject:@"com.sh.weme.wemesh.mesh"];
    return s.array;
}
static NSArray<NSString *> *RYAppSchemes(void) { // the app's own custom schemes (not Facebook / Google / VK / Twitter login ones)
    NSMutableOrderedSet *s = [NSMutableOrderedSet new];
    for (NSDictionary *t in ([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleURLTypes"] ?: @[]))
        for (NSString *x in (t[@"CFBundleURLSchemes"] ?: @[])) { NSString *l = x.lowercaseString; if ([l hasPrefix:@"fb"] || [l hasPrefix:@"vk"] || [l hasPrefix:@"twitterkit"] || [l hasPrefix:@"com.googleusercontent"]) continue; [s addObject:x]; }
    for (NSString *x in @[@"rave", @"wemesh", @"io.rave", @"sh.weme.wemesh"]) [s addObject:x];
    return s.array;
}
static NSMutableString *gJoinLog;
static void RYDeliverURL(NSURL *u, RYVia via, void (^res)(BOOL accepted)) {
    UIApplication *app = UIApplication.sharedApplication;
    BOOL web = [u.scheme.lowercaseString hasPrefix:@"http"];
    [gJoinLog appendFormat:@"deliver[%@]: %@ (app state %ld)\n", via == RYViaSystem ? @"system" : via == RYViaActivity ? @"handoff" : @"direct", u, (long)app.applicationState];
    if (via == RYViaActivity) { // Handoff "mesh" activity: the app logs "Continuing Handoff mesh activity: meshId ..." for it
        NSString *mid = RYMeshID(u); id ad0 = app.delegate; BOOL any = NO;
        if (!mid) { res(NO); return; }
        for (NSString *type in RYMeshActivityTypes()) {
            NSUserActivity *act = [[NSUserActivity alloc] initWithActivityType:type];
            [act addUserInfoEntriesFromDictionary:@{@"meshId": mid, @"mesh_id": mid, @"id": mid}];
            for (UIScene *sc in app.connectedScenes) {
                id d = sc.delegate;
                if ([d respondsToSelector:@selector(scene:continueUserActivity:)]) { [d scene:sc continueUserActivity:act]; any = YES; [gJoinLog appendFormat:@" scene handoff (%@)\n", type]; }
            }
            if ([ad0 respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
                BOOL r = [ad0 application:app continueUserActivity:act restorationHandler:^(NSArray<id<UIUserActivityRestoring>> *x) {}];
                [gJoinLog appendFormat:@" app delegate handoff (%@) -> %d\n", type, r]; any = any || r;
            }
            if (any) break;
        }
        if (!any) [gJoinLog appendString:@" handoff: nobody accepted it\n"];
        res(any); return;
    }
    if (via == RYViaSystem) {
        [app openURL:u options:@{} completionHandler:^(BOOL ok) {
            dispatch_async(dispatch_get_main_queue(), ^{ [gJoinLog appendFormat:@" system open -> %d\n", ok]; res(ok); });
        }];
        return;
    }
    BOOL handled = NO;
    id ad = app.delegate;
    if (web) { // NSUserActivity.webpageURL accepts only http/https (anything else throws)
        NSUserActivity *act = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        act.webpageURL = u;
        for (UIScene *sc in app.connectedScenes) {
            id d = sc.delegate;
            if ([d respondsToSelector:@selector(scene:continueUserActivity:)]) { [d scene:sc continueUserActivity:act]; handled = YES; [gJoinLog appendString:@" scene continue called\n"]; }
        }
        if (!handled && [ad respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
            handled = [ad application:app continueUserActivity:act restorationHandler:^(NSArray<id<UIUserActivityRestoring>> *x) {}];
            [gJoinLog appendFormat:@" appdelegate continue -> %d\n", handled];
        }
    }
    // many handlers look at who opened the link, so say it came from Safari
    NSDictionary *opts = @{UIApplicationOpenURLOptionsSourceApplicationKey: @"com.apple.mobilesafari", UIApplicationOpenURLOptionsOpenInPlaceKey: @NO};
    if ([ad respondsToSelector:@selector(application:openURL:options:)]) {
        BOOL r = [ad application:app openURL:u options:opts];
        [gJoinLog appendFormat:@" appdelegate openURL -> %d\n", r]; handled = handled || r;
    }
    res(handled);
}
// the landing page of a short link usually contains the real deep link: collect every URL in it, app schemes first
static NSArray<NSURL *> *RYCandidates(NSString *html) {
    if (!html.length) return @[];
    html = [html stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    html = [html stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    NSMutableOrderedSet *out = [NSMutableOrderedSet new];
    NSArray *noise = @[@"apple.com", @"google", @"gstatic", @"w3.org", @"facebook", @"twitter", @"fonts.", @"schema.org", @"cloudflare", @"jsdelivr", @"cdnjs", @"itunes", @"ytimg", @"youtube"];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z][A-Za-z0-9+.\\-]*://[^\\s\"'<>\\\\)]+" options:0 error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *x = [[html substringWithRange:m.range] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".,;"]];
        BOOL skip = NO; for (NSString *n in noise) if ([x containsString:n]) { skip = YES; break; }
        NSURL *u = skip ? nil : [NSURL URLWithString:x];
        if (u) [out addObject:u];
    }
    NSRegularExpression *mid = [NSRegularExpression regularExpressionWithPattern:@"mesh_?[iI]d[\"'=: ]+([A-Za-z0-9_\\-]{6,})" options:0 error:nil];
    NSTextCheckingResult *mm = [mid firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (mm) {
        NSString *id_ = [html substringWithRange:[mm rangeAtIndex:1]];
        [gJoinLog appendFormat:@"mesh id in page: %@\n", id_];
        // we do not know which shape the app parses, so offer every known one (each is tried and verified in turn)
        for (NSString *sc in @[@"rave", @"wemesh"]) for (NSString *f in @[@"%@://mesh?mesh_id=%@", @"%@://mesh/%@", @"%@://mesh?meshId=%@"]) {
            NSURL *g = [NSURL URLWithString:[NSString stringWithFormat:f, sc, id_]]; if (g) [out addObject:g];
        }
        for (NSString *sc in @[@"io.rave", @"sh.weme.wemesh"]) { NSURL *g = [NSURL URLWithString:[NSString stringWithFormat:@"%@://mesh?mesh_id=%@", sc, id_]]; if (g) [out addObject:g]; }
        // Rave 9 logs "Could not handle Rave universal link. Both meshId and videoUrl are nil": it reads a meshId from the link itself
        for (NSString *h in @[@"rave.watch", @"rave.link"]) { NSURL *g = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/?meshId=%@", h, id_]]; if (g) [out addObject:g]; }
    }
    return [[out array] sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSURL *p, NSURL *q) {
        BOOL cp = ![p.scheme.lowercaseString hasPrefix:@"http"], cq = ![q.scheme.lowercaseString hasPrefix:@"http"];
        return cp == cq ? NSOrderedSame : (cp ? NSOrderedAscending : NSOrderedDescending);
    }];
}
// one attempt = (url, how to deliver it)
static NSArray<NSDictionary *> *RYAttempts(NSArray<NSURL *> *urls) {
    NSMutableArray *a = [NSMutableArray new]; BOOL act = NO;
    for (NSURL *x in urls) {
        if ([x.scheme.lowercaseString hasPrefix:@"http"]) {
            [a addObject:@{@"u": x, @"via": @(RYViaDirect)}];
            if (!act && RYMeshID(x)) { act = YES; [a addObject:@{@"u": x, @"via": @(RYViaActivity)}]; }
            continue;
        }
        [a addObject:@{@"u": x, @"via": @(RYViaSystem)}];
        [a addObject:@{@"u": x, @"via": @(RYViaDirect)}];
        if (!act && RYMeshID(x)) { act = YES; [a addObject:@{@"u": x, @"via": @(RYViaActivity)}]; }
    }
    return a;
}
static NSSet<NSString *> *RYScreenSet(void) {
    NSMutableString *o = [NSMutableString new];
    for (UIWindow *w in RYAppWindows()) RYDump(w.rootViewController, 0, o);
    NSMutableSet *s = [NSMutableSet new];
    for (NSString *ln in [o componentsSeparatedByString:@"\n"]) {
        NSString *t = [ln stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length) [s addObject:t];
    }
    return s;
}
// what the app exposes for links: written to the log only when everything failed, so it can be sent back for analysis
static void RYListMethods(Class c, NSMutableString *o) {
    if (!c) return;
    unsigned n = 0; Method *ms = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++) {
        NSString *s = NSStringFromSelector(method_getName(ms[i])), *l = s.lowercaseString;
        for (NSString *k in @[@"url", @"link", @"activity", @"open", @"branch", @"deep", @"route"]) if ([l containsString:k]) { [o appendFormat:@"  - %@\n", s]; break; }
    }
    free(ms);
}
static void RYJoinDiag(void) {
    UIApplication *app = UIApplication.sharedApplication; id ad = app.delegate;
    NSMutableString *o = [NSMutableString stringWithString:@"\n-- diag --\n"];
    [o appendFormat:@"bundle id: %@\n", NSBundle.mainBundle.bundleIdentifier];
    [o appendFormat:@"app delegate: %@\n", NSStringFromClass([ad class])];
    for (NSDictionary *t in ([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleURLTypes"] ?: @[])) [o appendFormat:@"url schemes: %@\n", [t[@"CFBundleURLSchemes"] componentsJoinedByString:@","]];
    [o appendFormat:@"activity types: %@ | app schemes: %@\n", [RYMeshActivityTypes() componentsJoinedByString:@","], [RYAppSchemes() componentsJoinedByString:@","]];
    [o appendFormat:@"Branch SDK class: %@\n", NSClassFromString(@"Branch") ? @"yes" : @"no"];
    [o appendString:@"app delegate methods:\n"]; RYListMethods([ad class], o);
    for (UIScene *sc in app.connectedScenes) {
        [o appendFormat:@"scene: %@ delegate: %@\n", NSStringFromClass(sc.class), sc.delegate ? NSStringFromClass([(id)sc.delegate class]) : @"nil"];
        if (sc.delegate) RYListMethods([(id)sc.delegate class], o);
    }
    const char *img = class_getImageName([ad class]);
    if (img) {
        unsigned cn = 0; const char **names = objc_copyClassNamesForImage(img, &cn); int shown = 0;
        [o appendString:@"app classes about links:\n"];
        for (unsigned i = 0; i < cn && shown < 60; i++) {
            NSString *s = [NSString stringWithUTF8String:names[i]], *l = s.lowercaseString;
            for (NSString *k in @[@"link", @"branch", @"deeplink", @"route", @"universal", @"invite", @"joinmesh", @"urlhandler"]) if ([l containsString:k]) { [o appendFormat:@"  %@\n", s]; shown++; break; }
        }
        free(names);
    }
    [gJoinLog appendString:o];
}
// remember which delivery really opened a room: next time it goes first (the mesh id is the only thing that changes between links)
static void RYLearnWinner(NSURL *cu, RYVia via) {
    NSString *s0 = cu.absoluteString, *mid = RYMeshID(cu); NSDictionary *w = nil;
    if (mid.length && [s0 containsString:mid]) w = @{@"k": @"id", @"t": [s0 stringByReplacingOccurrencesOfString:mid withString:@"{ID}"], @"via": @(via)};
    else if (cu.host.length) w = @{@"k": @"host", @"t": cu.host, @"via": @(via)};
    if (w) { CS(@"joinWin", w); [gJoinLog appendFormat:@"learned: %@\n", w]; }
}
static NSString *RYMeshFromHTML(NSString *html) {
    if (!html.length) return nil;
    NSRegularExpression *mid = [NSRegularExpression regularExpressionWithPattern:@"mesh_?[iI]d[\"'=: ]+([A-Za-z0-9_\\-]{6,})" options:0 error:nil];
    NSTextCheckingResult *mm = [mid firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    return mm ? [html substringWithRange:[mm rangeAtIndex:1]] : nil;
}
static void RYTryNext(NSArray<NSDictionary *> *at, NSInteger i, UIViewController *before, NSSet<NSString *> *base, void (^done)(BOOL)) {
    if (i >= (NSInteger)at.count || i >= 24) { done(NO); return; }
    NSURL *cu = at[i][@"u"]; RYVia via = (RYVia)[at[i][@"via"] integerValue]; BOOL fast = [at[i][@"fast"] boolValue];
    BOOL wasInRoom = (before != nil);  // the room screen is reused when you switch rooms, so it cannot prove anything then
    RYDeliverURL(cu, via, ^(BOOL accepted) { // accepted != joined: the room screen is the only proof
        __block int limit = accepted ? (wasInRoom ? 12 : (fast ? 32 : 60)) : 2; /* ticks of 0.15s: accepted 9s (learned path 4.8s, already in a room 1.8s), refused 0.3s */    // accepted: 6s (already in a room) or 9s; refused: ~1s
        __block int tries = 0; __block BOOL extended = NO;
        [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *t) {
            UIViewController *now = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT));
            if (now && now != before) { [t invalidate]; [gJoinLog appendFormat:@"entered a room after: %@\n", cu]; if (!wasInRoom) RYLearnWinner(cu, via); done(YES); return; }
            if (++tries < limit) return;
            if (accepted && !wasInRoom && !extended) { // the app reacted (new screen) but the room is not up yet: give it more time instead of firing the next URL
                NSMutableSet *added = [RYScreenSet() mutableCopy]; [added minusSet:base];
                if (added.count) { extended = YES; limit += 60; [gJoinLog appendFormat:@" new screens appeared, waiting longer: %@\n", [added.allObjects componentsJoinedByString:@", "]]; return; }
            }
            [t invalidate];
            if (accepted && wasInRoom) { [gJoinLog appendString:@" accepted while already in a room: cannot verify\n"]; done(YES); return; }
            [gJoinLog appendFormat:@" %@, next\n", accepted ? @"accepted but no room" : @"refused"];
            RYTryNext(at, i + 1, before, base, done);
        }];
    });
}
static void RYJoinLink(NSURL *u, void (^done)(BOOL)) {
    gJoinLog = [NSMutableString stringWithFormat:@"link: %@\n", u];
    UIViewController *before = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT));
    NSSet<NSString *> *base = RYScreenSet();
    NSMutableArray *first = [NSMutableArray arrayWithObject:u];
    if ([u.host.lowercaseString isEqualToString:@"rave.link"]) { // the plist declares rave.watch / get.rave.io, not rave.link: the app may only recognise those
        for (NSString *h in @[@"rave.watch", @"get.rave.io"]) { NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO]; c.host = h; if (c.URL) [first addObject:c.URL]; }
    }
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u]; r.timeoutInterval = 8;
    void (^phase2)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *resp, NSError *e) {
            NSURL *f = resp.URL;
            NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
            NSString *html = d.length ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [gJoinLog appendFormat:@"fetch: status=%ld error=%@ final=%@ bytes=%lu\n", (long)code, e.localizedDescription, f, (unsigned long)d.length];
                NSMutableOrderedSet *urls = [NSMutableOrderedSet new];
                // only URLs that can belong to the app: its own schemes, or Rave's own web domains (never the YouTube link etc.)
                void (^add)(NSURL *) = ^(NSURL *x) {
                    NSString *sc = x.scheme.lowercaseString ?: @"";
                    if ([sc hasPrefix:@"http"]) { NSString *h = x.host.lowercaseString ?: @""; if (![h containsString:@"rave"] && ![h containsString:@"weme"]) return; }
                    else if (![sc containsString:@"weme"] && ![sc containsString:@"rave"]) return;
                    [urls addObject:x];
                };
                if (f && ![f isEqual:u]) add(f);
                NSArray *c = RYCandidates(html);
                [gJoinLog appendFormat:@"candidates: %lu\n", (unsigned long)c.count];
                for (NSURL *x in c) {
                    add(x);
                    NSString *sx = x.absoluteString, *sc0 = x.scheme.lowercaseString; // the app registers several schemes; the id is the same
                    if (sc0.length && ![sc0 hasPrefix:@"http"] && [[RYAppSchemes() valueForKeyPath:@"lowercaseString"] containsObject:sc0]) {
                        NSString *rest = [sx substringFromIndex:MIN(sx.length, sc0.length + 3)];
                        for (NSString *o in @[@"rave", @"wemesh"]) if (![o isEqualToString:sc0]) { NSURL *y = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", o, rest]]; if (y) add(y); }
                    }
                }
                if (!urls.count && html) [gJoinLog appendFormat:@"html:\n%@\n", html.length > 1800 ? [html substringToIndex:1800] : html];
                RYTryNext(RYAttempts([urls array]), 0, before, base, ^(BOOL ok2) { if (!ok2) RYJoinDiag(); done(ok2); });
            });
    };
    // the landing page is fetched right now, in parallel with the first attempts, instead of after they all failed
    __block NSArray *pf = nil; __block void (^waiting)(void) = nil;
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            pf = @[d ?: (id)NSNull.null, resp ?: (id)NSNull.null, e ?: (id)NSNull.null];
            if (waiting) { void (^w)(void) = waiting; waiting = nil; w(); }
        });
    }] resume];
    void (^usePF)(void) = ^{ phase2(pf[0] == NSNull.null ? nil : pf[0], pf[1] == NSNull.null ? nil : pf[1], pf[2] == NSNull.null ? nil : pf[2]); };
    NSDictionary *win = CF(@"joinWin", nil); if (![win isKindOfClass:NSDictionary.class]) win = nil;
    void (^normal)(void) = ^{
        NSMutableArray *at = [NSMutableArray new];
        if ([win[@"k"] isEqual:@"host"]) { // learned: this link's host worked last time
            NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO]; c.host = win[@"t"];
            if (c.URL) [at addObject:@{@"u": c.URL, @"via": win[@"via"] ?: @0, @"fast": @YES}];
        }
        [at addObjectsFromArray:RYAttempts(first)];
        RYTryNext(at, 0, before, base, ^(BOOL ok) {
            if (ok) { done(YES); return; }
            if (pf) usePF(); else waiting = [usePF copy];
        });
    };
    if ([win[@"k"] isEqual:@"id"]) { // learned: this build opens a room from a URL that carries the mesh id
        void (^fastGo)(void) = ^{
            NSString *html = (pf && pf[0] != NSNull.null) ? [[NSString alloc] initWithData:pf[0] encoding:NSUTF8StringEncoding] : nil;
            NSString *mid = RYMeshFromHTML(html);
            NSURL *v = mid ? [NSURL URLWithString:[win[@"t"] stringByReplacingOccurrencesOfString:@"{ID}" withString:mid]] : nil;
            if (!v) { normal(); return; }
            [gJoinLog appendFormat:@"fast path: %@\n", v];
            RYTryNext(@[@{@"u": v, @"via": win[@"via"] ?: @0, @"fast": @YES}], 0, before, base, ^(BOOL ok) { if (ok) done(YES); else normal(); });
        };
        if (pf) fastGo(); else waiting = [fastGo copy];
    } else normal();
}

#pragma mark - Anti-AFK (keep the process alive in the background)

static BOOL gKeepOn = YES;

@interface RYKeep : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *lm;
+ (instancetype)shared;
- (void)start; - (void)stop;
@end
@implementation RYKeep
+ (instancetype)shared { static RYKeep *k; static dispatch_once_t o; dispatch_once(&o, ^{ k = [RYKeep new]; }); return k; }
static BOOL RYHasBgMode(NSString *m) { return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"] containsObject:m]; }
- (void)start {
    if (self.lm) { CLAuthorizationStatus a = self.lm.authorizationStatus; if (a == kCLAuthorizationStatusAuthorizedWhenInUse || a == kCLAuthorizationStatusAuthorizedAlways) [self.lm startUpdatingLocation]; return; }
    CLLocationManager *m = [CLLocationManager new]; m.delegate = self;
    m.desiredAccuracy = kCLLocationAccuracyThreeKilometers; m.distanceFilter = 3000; m.pausesLocationUpdatesAutomatically = NO;
    if (RYHasBgMode(@"location")) { m.allowsBackgroundLocationUpdates = YES; m.showsBackgroundLocationIndicator = YES; } // setting this without the plist key would crash
    self.lm = m;
    if (m.authorizationStatus == kCLAuthorizationStatusNotDetermined) [m requestWhenInUseAuthorization];
    else [m startUpdatingLocation];
}
- (void)stop { [self.lm stopUpdatingLocation]; self.lm = nil; }
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)m {
    CLAuthorizationStatus a = m.authorizationStatus;
    if (a == kCLAuthorizationStatusAuthorizedWhenInUse || a == kCLAuthorizationStatusAuthorizedAlways) [m startUpdatingLocation];
}
- (void)locationManager:(CLLocationManager *)m didUpdateLocations:(NSArray<CLLocation *> *)l {}
- (void)locationManager:(CLLocationManager *)m didFailWithError:(NSError *)e {}
@end
static NSString *RYKeepStatus(void) {
    if (!gKeepOn) return T(@"متوقف", @"Off");
    if (!RYHasBgMode(@"location")) return T(@"ناقص: شغّل patch_ipa.py على الـ IPA (يضيف صلاحية الموقع بالخلفية)", @"Incomplete: run patch_ipa.py on the IPA (adds the background-location mode)");
    CLAuthorizationStatus a = [CLLocationManager new].authorizationStatus;
    if (a == kCLAuthorizationStatusDenied || a == kCLAuthorizationStatusRestricted) return T(@"الموقع مرفوض: فعّله من إعدادات iOS للتطبيق", @"Location denied: allow it in iOS Settings for the app");
    if (a == kCLAuthorizationStatusNotDetermined) return T(@"بانتظار موافقتك على الموقع", @"Waiting for your location permission");
    return T(@"شغّال", @"Running");
}
static void RYSetKeep(BOOL on) { gKeepOn = on; CS(@"keepOn", @(on)); if (on) [[RYKeep shared] start]; else [[RYKeep shared] stop]; }

#pragma mark - Branding

static NSString *RYBrand(void) {
    NSString *s = CF(@"brandName", @"8ubah");
    return ([s isKindOfClass:NSString.class] && s.length) ? s : @"8ubah";
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
#pragma mark - Anti-delete for private messages (SQLite level)
// Rave keeps DMs in a local SQLite table named "message" (GRDB). When a message is unsent / deleted, the app runs
// DELETE FROM "message" WHERE ... . We rebind sqlite3_prepare_v2/v3 (symbol pointers only, no code patching) and turn
// that statement into "UPDATE message SET id = id WHERE ..." (same parameters, changes nothing), so the row stays.
// UNTESTED on a device. Needs Rave to import sqlite3 symbols (not statically linked SQLite).

static volatile BOOL gAntiDel = NO;
static volatile int gAntiDelBlocked = 0, gAntiDelImages = 0;
static int (*orig_prepare_v2)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
static int (*orig_prepare_v3)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);

// returns the part of the statement after the table name if it is a DELETE FROM message, else NULL
static const char *RYMsgDeleteRest(const char *sql) {
    if (!sql) return NULL;
    while (*sql && isspace((unsigned char)*sql)) sql++;
    if (strncasecmp(sql, "DELETE", 6) != 0) return NULL;
    const char *p = sql + 6; while (isspace((unsigned char)*p)) p++;
    if (strncasecmp(p, "FROM", 4) != 0) return NULL;
    p += 4; if (!isspace((unsigned char)*p)) return NULL;
    while (isspace((unsigned char)*p)) p++;
    if (*p == '"' || *p == '`' || *p == '[') p++;
    if (strncasecmp(p, "message", 7) != 0) return NULL;
    p += 7;
    if (isalnum((unsigned char)*p) || *p == '_') return NULL; // messageFTS, message_status ...
    if (*p == '"' || *p == '`' || *p == ']') p++;
    return p;
}
// builds the replacement statement (caller frees); *off = offset of "rest" inside the original
static char *RYMsgDeleteRewrite(const char *sql, int n, size_t *off, size_t *len) {
    const char *rest = gAntiDel ? RYMsgDeleteRest(sql) : NULL;
    if (!rest) return NULL;
    size_t L = n < 0 ? strlen(sql) : (size_t)n, o = (size_t)(rest - sql);
    if (o > L) return NULL;
    const char *pre = "UPDATE message SET id = id"; size_t pl = strlen(pre), rl = L - o;
    char *b = (char *)malloc(pl + rl + 1); if (!b) return NULL;
    memcpy(b, pre, pl); memcpy(b + pl, rest, rl); b[pl + rl] = 0;
    *off = o; *len = L; return b;
}
static void RYNoteBlocked(const char *sql) {
    int c = ++gAntiDelBlocked;
    if (c <= 20) RYLog(@"anti-delete: blocked #%d: %.110s", c, sql);
}
#define RY_BLOCK_PREFIX "UPDATE message SET id = id"

// ---- journal: which statements touch the message table (shown in the diagnostic report, so we can see what Rave really runs when a message is deleted)
static NSMutableDictionary<NSString *, NSNumber *> *gSqlJ;
static NSMutableArray<NSString *> *gSqlJOrder;
static BOOL RYHasDelWord(const char *s) {
    const char *w[] = {"delet", "unsent", "revok", "retract", "recall", "remov", "tombstone", NULL};
    for (int i = 0; w[i]; i++) if (strcasestr(s, w[i])) return YES;
    return NO;
}
// looks at a statement before it is prepared. Returns YES for an UPDATE of the message table that looks like a "soft delete" (deletedAt = ?, isUnsent = ? ...)
static BOOL RYJournalSQL(const char *sql, int n) {
    if (!sql) return NO;
    char buf[321]; size_t L = n < 0 ? strnlen(sql, 320) : (size_t)MIN(n, 320);
    memcpy(buf, sql, L); buf[L] = 0;
    const char *p = buf; while (*p && isspace((unsigned char)*p)) p++;
    const char *kind = NULL;
    if (strncasecmp(p, "INSERT", 6) == 0) kind = "INS"; else if (strncasecmp(p, "UPDATE", 6) == 0) kind = "UPD";
    else if (strncasecmp(p, "DELETE", 6) == 0) kind = "DEL"; else if (strncasecmp(p, "REPLACE", 7) == 0) kind = "REP";
    if (!kind || !strcasestr(p, "message")) return NO;
    static dispatch_once_t once; dispatch_once(&once, ^{ gSqlJ = [NSMutableDictionary new]; gSqlJOrder = [NSMutableArray new]; });
    NSString *shape = [NSString stringWithFormat:@"%s %.110s", kind, p];
    BOOL fresh = NO;
    @synchronized(gSqlJ) {
        NSNumber *c = gSqlJ[shape];
        if (c) gSqlJ[shape] = @(c.intValue + 1);
        else if (gSqlJOrder.count < 40) { gSqlJ[shape] = @1; [gSqlJOrder addObject:shape]; fresh = YES; }
    }
    if (fresh) RYLog(@"sql: %@", shape);
    return strcmp(kind, "UPD") == 0 && RYHasDelWord(p);
}

// statements whose execution must be inspected (the blocked DELETEs and the soft-delete UPDATEs)
static void *volatile gFlag[48]; static int gFlagPos; static volatile int gFlagN; static os_unfair_lock gFlagLk = OS_UNFAIR_LOCK_INIT;
static void RYFlag(sqlite3_stmt *st) {
    os_unfair_lock_lock(&gFlagLk);
    for (int i = 0; i < 48; i++) if (gFlag[i] == (void *)st) { os_unfair_lock_unlock(&gFlagLk); return; }
    gFlag[gFlagPos] = (void *)st; gFlagPos = (gFlagPos + 1) % 48; if (gFlagN < 48) gFlagN++;
    os_unfair_lock_unlock(&gFlagLk);
}
static BOOL RYIsFlagged(sqlite3_stmt *st) { for (int i = 0; i < 48; i++) if (gFlag[i] == (void *)st) return YES; return NO; }

static int RYPrep2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **st, const char **tail) {
    BOOL soft = RYJournalSQL(sql, n);
    size_t off = 0, L = 0; char *b = RYMsgDeleteRewrite(sql, n, &off, &L);
    if (!b) {
        int rc = orig_prepare_v2(db, sql, n, st, tail);
        if (soft && gAntiDel && rc == SQLITE_OK && st && *st) RYFlag(*st);
        return rc;
    }
    const char *t2 = NULL; int rc = orig_prepare_v2(db, b, -1, st, &t2);
    if (tail) { size_t pl = strlen("UPDATE message SET id = id"); *tail = (t2 && t2 >= b + pl) ? sql + off + (size_t)(t2 - (b + pl)) : sql + L; }
    if (rc == SQLITE_OK && st && *st) RYFlag(*st);
    RYNoteBlocked(sql); free(b); return rc;
}
static int RYPrep3(sqlite3 *db, const char *sql, int n, unsigned int fl, sqlite3_stmt **st, const char **tail) {
    BOOL soft = RYJournalSQL(sql, n);
    size_t off = 0, L = 0; char *b = RYMsgDeleteRewrite(sql, n, &off, &L);
    if (!b) {
        int rc = orig_prepare_v3(db, sql, n, fl, st, tail);
        if (soft && gAntiDel && rc == SQLITE_OK && st && *st) RYFlag(*st);
        return rc;
    }
    const char *t2 = NULL; int rc = orig_prepare_v3(db, b, -1, fl, st, &t2);
    if (tail) { size_t pl = strlen("UPDATE message SET id = id"); *tail = (t2 && t2 >= b + pl) ? sql + off + (size_t)(t2 - (b + pl)) : sql + L; }
    if (rc == SQLITE_OK && st && *st) RYFlag(*st);
    RYNoteBlocked(sql); free(b); return rc;
}

// ---- remember what was deleted. Just before a blocked DELETE (or a soft-delete UPDATE) runs, we read the rows it is about to touch
// with the same WHERE (taken from sqlite3_expanded_sql, so it works whatever the WHERE looks like and whatever type the bound values are).
static void RYAddDeletedString(NSString *s);   // ObjC side, defined below
static int (*orig_step)(sqlite3_stmt *);
static int gAntiDelRows = 0, gRowLogged = 0;

static BOOL RYNameIsID(const char *l) {
    size_t n = strlen(l);
    if (strstr(l, "uuid") || strstr(l, "_id")) return YES;
    if (n >= 2 && strcmp(l + n - 2, "id") == 0) return YES;
    if (n >= 3 && strcmp(l + n - 3, "ids") == 0) return YES;
    return NO;
}
// 2 = column that holds message text, 1 = unknown (maybe text), 0 = never
static int RYNameClass(const char *name) {
    if (!name) return 0;
    char l[96]; size_t i = 0; for (; name[i] && i < 95; i++) l[i] = (char)tolower((unsigned char)name[i]); l[i] = 0;
    if (RYNameIsID(l)) return 0;
    const char *hard[] = {"type", "status", "state", "date", "time", "stamp", "lang", "token", "color", "url", "uri", "path", "avatar", "image", "photo", "kind", "version", "flag", NULL};
    for (int k = 0; hard[k]; k++) if (strstr(l, hard[k])) return 0;
    const char *w[] = {"chat", "text", "body", "content", "msg", "message", "caption", "translat", "comment", NULL};
    for (int k = 0; w[k]; k++) if (strstr(l, w[k])) return 2;
    const char *soft[] = {"thread", "user", "sender", "creat", "updat", "reply", "media", "link", "meta", "reaction", "emoji", "read", "sent", "clear", "name", NULL};
    for (int k = 0; soft[k]; k++) if (strstr(l, soft[k])) return 0;
    return 1;
}
static BOOL RYLooksID(const char *t, BOOL strictIDs) {
    size_t n = strlen(t);
    if (n == 36 && t[8] == '-' && t[13] == '-' && t[18] == '-' && t[23] == '-') return YES;
    if (!strictIDs) return NO;
    BOOL allhex = YES, alldig = YES;
    for (size_t i = 0; i < n; i++) { unsigned char c = (unsigned char)t[i]; if (!isxdigit(c)) allhex = NO; if (!isdigit(c)) alldig = NO; }
    return (allhex && n >= 20) || (alldig && n >= 6);
}
static void RYJsonLeaves(id j, NSString *key, int d, NSMutableArray *out) {
    if (!j || d > 6) return;
    if ([j isKindOfClass:NSString.class]) {
        NSString *s = j, *k = key.lowercaseString;
        if (s.length < 2 || s.length > 2000 || !k.length || [k hasSuffix:@"id"] || [k hasSuffix:@"type"]) return;
        for (NSString *w in @[@"text", @"body", @"message", @"msg", @"content", @"caption", @"comment", @"translat"])
            if ([k containsString:w]) { if (!RYLooksID(s.UTF8String, NO)) [out addObject:s]; return; }
    } else if ([j isKindOfClass:NSDictionary.class]) {
        for (id k in (NSDictionary *)j) RYJsonLeaves(((NSDictionary *)j)[k], [k description], d + 1, out);
    } else if ([j isKindOfClass:NSArray.class]) {
        for (id x in (NSArray *)j) RYJsonLeaves(x, key, d + 1, out);
    }
}
// ---- message body is a BLOB in Rave (messageBody:blob71): read it as plist / JSON / protobuf / plain text
static BOOL RYPrintableUTF8(const unsigned char *b, size_t n) {
    if (!n) return NO;
    NSString *s = [[NSString alloc] initWithBytes:b length:n encoding:NSUTF8StringEncoding]; if (!s) return NO;
    for (NSUInteger i = 0; i < s.length; i++) { unichar c = [s characterAtIndex:i]; if ((c < 0x20 && c != '\n' && c != '\t' && c != '\r') || c == 0x7f) return NO; }
    return YES;
}
static BOOL RYReadVarint(const unsigned char *b, size_t n, size_t *pos, uint64_t *out) {
    uint64_t v = 0; int sh = 0;
    while (*pos < n && sh < 64) { unsigned char c = b[(*pos)++]; v |= (uint64_t)(c & 0x7f) << sh; if (!(c & 0x80)) { *out = v; return YES; } sh += 7; }
    return NO;
}
// YES when the whole buffer is valid protobuf; strings found are appended to out (only when it parsed completely)
static BOOL RYProto(const unsigned char *b, size_t n, int depth, NSMutableArray *out) {
    size_t pos = 0; NSMutableArray *local = [NSMutableArray new];
    while (pos < n) {
        uint64_t tag = 0; if (!RYReadVarint(b, n, &pos, &tag)) return NO;
        uint64_t wt = tag & 7, fn = tag >> 3; if (fn == 0 || wt == 3 || wt == 4 || wt > 5) return NO;
        if (wt == 0) { uint64_t x = 0; if (!RYReadVarint(b, n, &pos, &x)) return NO; }
        else if (wt == 1) { if (pos + 8 > n) return NO; pos += 8; }
        else if (wt == 5) { if (pos + 4 > n) return NO; pos += 4; }
        else {
            uint64_t len = 0; if (!RYReadVarint(b, n, &pos, &len) || len > n - pos) return NO;
            const unsigned char *p = b + pos; pos += (size_t)len;
            if (len == 0) continue;
            if (RYPrintableUTF8(p, (size_t)len)) { NSString *t = [[NSString alloc] initWithBytes:p length:(NSUInteger)len encoding:NSUTF8StringEncoding]; if (t) [local addObject:t]; }
            else if (depth < 4) RYProto(p, (size_t)len, depth + 1, local);
        }
    }
    [out addObjectsFromArray:local]; return YES;
}
static void RYAllLeaves(id j, NSString *key, int d, NSMutableArray *out) {
    if (!j || d > 6) return;
    if ([j isKindOfClass:NSString.class]) { if (!key.length || RYNameClass(key.UTF8String)) [out addObject:j]; }
    else if ([j isKindOfClass:NSDictionary.class]) { for (id k in (NSDictionary *)j) RYAllLeaves(((NSDictionary *)j)[k], [k description], d + 1, out); }
    else if ([j isKindOfClass:NSArray.class]) { for (id x in (NSArray *)j) RYAllLeaves(x, key, d + 1, out); }
}
static void RYBlobStrings(const unsigned char *b, int len, NSMutableArray *out) {
    NSMutableArray *got = [NSMutableArray new];
    if (len >= 8 && memcmp(b, "bplist00", 8) == 0) {
        id pl = [NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:b length:(NSUInteger)len] options:0 format:NULL error:NULL]; RYAllLeaves(pl, nil, 0, got);
    } else if (b[0] == '{' || b[0] == '[') {
        id j = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:b length:(NSUInteger)len] options:0 error:nil]; RYAllLeaves(j, nil, 0, got);
    } else if (!RYProto(b, (size_t)len, 0, got)) [got removeAllObjects];
    if (!got.count) {
        if (RYPrintableUTF8(b, (size_t)len)) { NSString *t = [[NSString alloc] initWithBytes:b length:(NSUInteger)len encoding:NSUTF8StringEncoding]; if (t) [got addObject:t]; }
        else { // last resort: printable runs
            int st = -1;
            for (int i = 0; i <= len; i++) {
                BOOL pr = i < len && (b[i] >= 0x20 && b[i] != 0x7f);
                if (pr && st < 0) st = i;
                if (!pr && st >= 0) { if (i - st >= 2 && RYPrintableUTF8(b + st, (size_t)(i - st))) { NSString *t = [[NSString alloc] initWithBytes:b + st length:(NSUInteger)(i - st) encoding:NSUTF8StringEncoding]; if (t) [got addObject:t]; } st = -1; }
            }
        }
    }
    for (NSString *x in got) {
        NSString *t = [x stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length < 1 || t.length > 2000 || RYLooksID(t.UTF8String, YES)) continue;
        [out addObject:t];
    }
}
// pulls the message text out of the current row of q (plain columns, or JSON inside a TEXT / BLOB column)
static void RYCollectRow(sqlite3_stmt *q, NSMutableArray *strong, NSMutableArray *weak, NSMutableString *dbg) {
    int cc = sqlite3_column_count(q);
    for (int c = 0; c < cc; c++) {
        int ty = sqlite3_column_type(q, c); const char *nm = sqlite3_column_name(q, c);
        if (ty == SQLITE_TEXT) {
            const char *t = (const char *)sqlite3_column_text(q, c); if (!t) continue;
            size_t len = strlen(t);
            if (dbg && dbg.length < 900) [dbg appendFormat:@"%s=%.28s | ", nm ?: "?", t];
            if (len < 2 || len > 6000) continue;
            if (t[0] == '{' || t[0] == '[') {
                id j = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:t length:len] options:0 error:nil];
                if (j) RYJsonLeaves(j, nil, 0, strong);
                continue;
            }
            int cl = RYNameClass(nm); if (!cl || len > 4000) continue;
            if (RYLooksID(t, cl == 1)) continue;
            NSString *s = [NSString stringWithUTF8String:t]; if (s) [(cl == 2 ? strong : weak) addObject:s];
        } else if (ty == SQLITE_BLOB) {
            const unsigned char *b = (const unsigned char *)sqlite3_column_blob(q, c); int len = sqlite3_column_bytes(q, c);
            if (dbg && dbg.length < 900) { [dbg appendFormat:@"%s:blob%d hex=", nm ?: "?", len]; for (int i = 0; b && i < len && i < 48; i++) [dbg appendFormat:@"%02x", b[i]]; [dbg appendString:@" | "]; }
            if (b && len > 0 && len < 40000 && RYNameClass(nm) == 2) RYBlobStrings(b, len, strong);
        } else if (dbg && dbg.length < 900) [dbg appendFormat:@"%s:t%d | ", nm ?: "?", ty];
    }
}
static void RYCaptureStmt(sqlite3_stmt *st) {
    static __thread int busy; if (busy) return; busy = 1;
    const char *ps = sqlite3_sql(st); char *ex = ps ? sqlite3_expanded_sql(st) : NULL;
    if (ex) {
        const char *w = NULL; size_t pl = strlen(RY_BLOCK_PREFIX);
        if (strncmp(ps, RY_BLOCK_PREFIX, pl) == 0 && strncmp(ex, RY_BLOCK_PREFIX, pl) == 0) w = ex + pl;
        else if (strncasecmp(ps, "UPDATE", 6) == 0) {
            char head[301]; size_t hl = strnlen(ps, 300); memcpy(head, ps, hl); head[hl] = 0;
            if (RYHasDelWord(head)) { for (const char *p = ex; (p = strcasestr(p, " where ")); p++) w = p; }
        }
        if (w) {
            size_t rl = strlen(w); char *sel = (char *)malloc(rl + 40);
            if (sel) {
                snprintf(sel, rl + 40, "SELECT * FROM message%s", w);
                sqlite3 *db = sqlite3_db_handle(st); sqlite3_stmt *q = NULL; int rc = SQLITE_ERROR;
                if (db && orig_prepare_v2) rc = orig_prepare_v2(db, sel, -1, &q, NULL);
                else if (db && orig_prepare_v3) rc = orig_prepare_v3(db, sel, -1, 0, &q, NULL);
                if (rc == SQLITE_OK && q) {
                    int rows = 0;
                    while (rows < 200 && (orig_step ? orig_step(q) : sqlite3_step(q)) == SQLITE_ROW) {
                        rows++; gAntiDelRows++;
                        NSMutableArray *strong = [NSMutableArray new], *weak = [NSMutableArray new];
                        NSMutableString *dbg = gRowLogged < 6 ? [NSMutableString new] : nil;
                        RYCollectRow(q, strong, weak, dbg);
                        NSArray *use = strong.count ? strong : weak;
                        for (NSString *s in use) RYAddDeletedString(s);
                        if (dbg) { gRowLogged++; RYLog(@"anti-delete: row [%@] -> picked %lu", dbg, (unsigned long)use.count); }
                    }
                } else if (gRowLogged < 6) { gRowLogged++; RYLog(@"anti-delete: select failed rc=%d: %.140s", rc, sel); }
                if (q) sqlite3_finalize(q);
                free(sel);
            }
        }
        sqlite3_free(ex);
    }
    busy = 0;
}
static int RYStep(sqlite3_stmt *st) {
    if (gFlagN && gAntiDel && RYIsFlagged(st)) RYCaptureStmt(st);
    return orig_step(st);
}

#pragma mark - Mic voice changer (changes what the others hear; three possible capture routes, each counted so we can see which one the app really uses)
typedef struct { const char *ar, *en; float semi; int mode; float echo; } RYPreset;
static const RYPreset kPresets[] = {
    {"عادي", "Normal", 0, 0, 0}, {"رجل عميق", "Deep man", -4, 0, 0}, {"وحش", "Monster", -9, 0, 0},
    {"فتاة", "Girl", 4, 0, 0}, {"طفل", "Kid", 7, 0, 0}, {"سنجاب", "Chipmunk", 11, 0, 0},
    {"روبوت", "Robot", 0, 1, 0}, {"ميجافون", "Megaphone", 0, 2, 0}, {"صدى", "Echo", 0, 0, 0.45f}, {"صدى عميق", "Deep echo", -4, 0, 0.4f}
};
#define RY_NPRESETS ((int)(sizeof(kPresets) / sizeof(kPresets[0])))
static volatile int gMicOn = 0, gMicMode = 0, gMicPreset = 0;
static volatile float gMicSemi = 0, gMicEcho = 0, gMicGain = 1;
static volatile long long gMicCallsA = 0, gMicCallsU = 0, gMicCallsT = 0, gMicProc = 0;
static volatile int gMicRebound = 0, gMicWrapped = 0, gMicTapInst = 0;
static volatile int gMicDist = 0, gMicRev = 0, gMonOn = 0;
#define RY_FX_ON (gMicOn || gMicDist || gMicRev)   // the "Silver" effects (amplifier, silver echo) work on their own, without the voice-changer switch
enum { RV_DRY, RV_ELVL, RV_ESEND, RV_LLVL, RV_SIZE, RV_PRE, RV_DECAY, RV_DIFF, RV_SPIN, RV_WANDER, RV_HC, RV_EDAMP, RV_LDAMP, RV_LC, RV_LB, RV_BF, RV_N };
static const float kRvDef[RV_N] = {46, 69, 69, 69, 32, 100, 10, 0, 0, 40, 16000, 16000, 9400, 137, 100, 600}; // the Dragonfly Room Reverb values from the screenshot
static volatile float gRv[RV_N] = {46, 69, 69, 69, 32, 100, 10, 0, 0, 40, 16000, 16000, 9400, 137, 100, 600};
static volatile float gDistGain = 1000.f, gDistOut = 0.7f, gDistGate = 0.0018f; // amplifier: +60 dB, -3 dB out, gate at -55 dB
static char gMicFmt[96] = "-"; static char gMicLast[200] = "-"; static volatile long long gMicSkip = 0; static volatile double gMicHWRate = 48000;

#define RYM_BUF 8192      // pitch history (power of two)
#define RYM_ECHO 32768    // echo line (power of two)
typedef struct {
    float hist[RYM_BUF]; unsigned w; float d0, d1; float eb[RYM_ECHO]; unsigned ew; float ph, hpx, hpy, lp; double sr;
    float dcx, dcy, dlp, env;                                        // "amplifier" (distortion) state
    float cb[8][4096]; unsigned ci[8]; float cf[8]; float ab[4][1024]; unsigned ai[4]; // room reverb: 8 combs + 4 all-passes
    float pre[16384]; unsigned pw; float er[8192]; unsigned erw;      // pre-delay + early reflections
    float rlc, elp, olp, blp, lfo;                                    // reverb filters + modulation
} RYVS;
static RYVS gVS[3]; // 0 = AudioUnitRender, 1 = AUAudioUnit block, 2 = AVAudioEngine tap (separate state: they may run at the same time)


// ---- "Silver" effects. Windows VST plugins cannot run on an iPhone, so the same two effects are built in natively.
// amplifier (Plus Distortion style: input gain -> saturation -> output gain). The gain is at least +60 dB, so a gate keeps the room noise from being blown up.
static inline float RYDist(float x, RYVS *s) {
    float a = fabsf(x); s->env = a > s->env ? a : s->env * 0.9997f;
    float thr = gDistGate, gate = s->env < thr ? s->env / thr : 1.f; gate *= gate;      // below the threshold the input fades out
    float v = x * gDistGain;
    float y = 0.7f * tanhf(v * 2.2f + 0.1f) + 0.3f * fmaxf(-1.f, fminf(1.f, v * 3.f));
    float hp = y - s->dcx + 0.995f * s->dcy; s->dcx = y; s->dcy = hp;                  // DC blocker (the asymmetric clipping adds an offset)
    s->dlp += 0.55f * (hp - s->dlp);                                                    // takes the harshest fizz off
    return s->dlp * gDistOut * gate;
}
// room reverb modelled on Dragonfly Room Reverb (Freeverb3 style): early reflections + a late tail made of 8 combs and 4 all-passes.
// The coefficients are worked out once per audio block from the user's settings.
typedef struct { int L[8], apL[4], etl[8], pd; float fb[8], ld, ed, hc, lc, bf, apg, wdepth, spininc, dry, elv, esend, llv, lb; } RYRevC;
static const int kRvComb[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617}, kRvAp[4] = {556, 441, 341, 225};
static const float kRvEt[8] = {0.007f, 0.011f, 0.017f, 0.023f, 0.031f, 0.041f, 0.053f, 0.067f}, kRvEg[8] = {.7f, .6f, .5f, .45f, .4f, .35f, .3f, .25f};
static inline float RYPole(float hz, double sr) { if (hz > 0.45f * (float)sr) hz = 0.45f * (float)sr; if (hz < 1.f) hz = 1.f; return expf(-6.2831853f * hz / (float)sr); }
static void RYRevPrep(RYRevC *c, double sr) {
    const float k = (float)(sr / 44100.0), sz = fmaxf(0.25f, gRv[RV_SIZE] / 32.f), decay = fmaxf(0.1f, gRv[RV_DECAY]);
    for (int i = 0; i < 8; i++) {
        int L = (int)(kRvComb[i] * k * sz); if (L > 4000) L = 4000; if (L < 32) L = 32; c->L[i] = L;
        float fb = powf(10.f, -3.f * (float)L / ((float)sr * decay)); c->fb[i] = fb > 0.9995f ? 0.9995f : fb;  // feedback that gives the chosen decay time (RT60)
        int e = (int)(kRvEt[i] * sz * (float)sr); c->etl[i] = e > 8190 ? 8190 : e;
    }
    for (int i = 0; i < 4; i++) { int L = (int)(kRvAp[i] * k); if (L > 1000) L = 1000; if (L < 8) L = 8; c->apL[i] = L; }
    int pd = (int)(gRv[RV_PRE] * 0.001 * sr); c->pd = pd > 16383 ? 16383 : (pd < 0 ? 0 : pd);
    c->ld = RYPole(gRv[RV_LDAMP], sr); c->ed = RYPole(gRv[RV_EDAMP], sr); c->hc = RYPole(gRv[RV_HC], sr); c->lc = RYPole(gRv[RV_LC], sr); c->bf = RYPole(gRv[RV_BF], sr);
    c->apg = 0.1f + 0.7f * gRv[RV_DIFF] * 0.01f; c->wdepth = gRv[RV_WANDER] * 0.01f * 24.f * k; c->spininc = 6.2831853f * gRv[RV_SPIN] / (float)sr;
    c->dry = gRv[RV_DRY] * 0.01f; c->elv = gRv[RV_ELVL] * 0.01f * 0.3f; c->esend = gRv[RV_ESEND] * 0.01f; c->llv = gRv[RV_LLVL] * 0.01f * 3.f; c->lb = gRv[RV_LB] * 0.01f;
}
static inline float RYRev(float x, RYVS *s, const RYRevC *c) {
    s->rlc = x * (1.f - c->lc) + s->rlc * c->lc; float xi = x - s->rlc;                  // low cut on what goes into the reverb
    s->pre[s->pw & 16383] = xi; float pin = s->pre[(s->pw - (unsigned)c->pd) & 16383]; s->pw++;
    s->er[s->erw & 8191] = xi; float e = 0;
    for (int j = 0; j < 8; j++) e += s->er[(s->erw - (unsigned)c->etl[j]) & 8191] * kRvEg[j];
    s->erw++; s->elp = e * (1.f - c->ed) + s->elp * c->ed; e = s->elp;                  // early damp
    float in = (pin + e * c->esend) * 0.015f, late = 0;
    s->lfo += c->spininc; if (s->lfo > 6.2831853f) s->lfo -= 6.2831853f;
    for (int i = 0; i < 8; i++) {
        float Lm = (float)c->L[i]; if (c->wdepth > 0.01f && c->spininc > 0.f) Lm += c->wdepth * sinf(s->lfo + 0.8f * (float)i);
        int Li = (int)Lm; float fr = Lm - (float)Li; unsigned wi = s->ci[i];
        float o = s->cb[i][(wi - (unsigned)Li) & 4095] * (1.f - fr) + s->cb[i][(wi - (unsigned)Li - 1u) & 4095] * fr;
        s->cf[i] = o * (1.f - c->ld) + s->cf[i] * c->ld;                                // late damp
        s->cb[i][wi & 4095] = in + s->cf[i] * c->fb[i]; s->ci[i] = wi + 1; late += o;
    }
    for (int a = 0; a < 4; a++) {
        unsigned wi = s->ai[a]; float b = s->ab[a][(wi - (unsigned)c->apL[a]) & 1023], o = -late + b;
        s->ab[a][wi & 1023] = late + b * c->apg; s->ai[a] = wi + 1; late = o;
    }
    s->blp = late * (1.f - c->bf) + s->blp * c->bf; late += s->blp * c->lb;             // low boost
    float wet = e * c->elv + late * c->llv;
    s->olp = wet * (1.f - c->hc) + s->olp * c->hc;                                       // high cut
    return x * c->dry + s->olp;
}
// pitch shift = two read taps on a delay line that slides at (1 - ratio) samples per sample, cross-faded with a Hann window
static void RYVoiceBlock(float *x, int n, double sr, RYVS *s) {
    if (s->sr != sr) { memset(s, 0, sizeof(RYVS)); s->sr = sr; s->d1 = (float)(0.016 * sr); }
    const int W = (int)(0.032 * sr); const int revOn = gMicRev; RYRevC rc; if (revOn) RYRevPrep(&rc, sr);
    const int mst = gMicOn; // pitch / voice / echo / mic level belong to the main switch; amplifier and silver echo have their own
    const float semi = mst ? gMicSemi : 0.f, echo = mst ? gMicEcho : 0.f, gain = mst ? gMicGain : 1.f; const int mode = mst ? gMicMode : 0;
    const float dd = 1.f - powf(2.f, semi / 12.f);
    const BOOL pitch = fabsf(semi) > 0.05f;
    int ed = (int)(0.27 * sr); if (ed >= RYM_ECHO) ed = RYM_ECHO - 1;
    const float rph = (float)(2.0 * M_PI * 70.0 / sr);
    for (int i = 0; i < n; i++) {
        float in = x[i] * gain, y = in;
        if (pitch) {
            s->hist[s->w & (RYM_BUF - 1)] = in;
            float acc = 0; float *dk[2] = { &s->d0, &s->d1 };
            for (int k = 0; k < 2; k++) {
                float d = *dk[k]; int di = (int)d; float fr = d - (float)di;
                float v = s->hist[(s->w - (unsigned)di) & (RYM_BUF - 1)] * (1.f - fr) + s->hist[(s->w - (unsigned)di - 1) & (RYM_BUF - 1)] * fr;
                acc += v * (0.5f - 0.5f * cosf(6.2831853f * (d / (float)W)));
                d += dd; if (d >= (float)W) d -= (float)W; else if (d < 0.f) d += (float)W; *dk[k] = d;
            }
            y = acc; s->w++;
        }
        if (mode == 1) { float m = sinf(s->ph); s->ph += rph; if (s->ph > 6.2831853f) s->ph -= 6.2831853f; y = y * (0.25f + 0.75f * m) * 1.35f; }
        else if (mode == 2) { float hp = 0.95f * (s->hpy + y - s->hpx); s->hpx = y; s->hpy = hp; s->lp += 0.4f * (hp - s->lp); y = tanhf(s->lp * 3.0f); }
        if (gMicDist) y = RYDist(y, s);
        if (revOn) y = RYRev(y, s, &rc);
        if (echo > 0.01f) { float e = s->eb[(s->ew - (unsigned)ed) & (RYM_ECHO - 1)]; s->eb[s->ew & (RYM_ECHO - 1)] = y + e * 0.4f; s->ew++; y += e * echo; }
        if (y > 1.f) y = 1.f; else if (y < -1.f) y = -1.f;
        x[i] = y;
    }
}
// ---- monitor: hear your own processed voice (what the others hear) through the phone's output. A ring buffer is fed by the capture routes below.
static float gMonRing[65536]; static volatile unsigned gMonW = 0, gMonR = 0; static double gMonSR = 48000; static AVAudioEngine *gMonEng;
static void RYMonFeed(const float *x, int n, double sr) {
    if (!gMonOn) return; gMonSR = sr; unsigned w = gMonW;
    for (int i = 0; i < n; i++) gMonRing[(w + (unsigned)i) & 65535] = x[i];
    __sync_synchronize(); gMonW = w + (unsigned)n;
}
static void RYMonStop(void) {
    gMonOn = 0; AVAudioEngine *e = gMonEng; gMonEng = nil;
    if (e) dispatch_async(dispatch_get_main_queue(), ^{ [e stop]; });
}
static void RYMonStart(void) {
    gMonOn = 1; gMonR = gMonW;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gMonEng || !gMonOn) return;
        AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(gMonSR > 0 ? gMonSR : 48000) channels:1];
        __block BOOL primed = NO;
        AVAudioSourceNode *src = [[AVAudioSourceNode alloc] initWithFormat:fmt renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount frames, AudioBufferList *out) {
            float *o = (float *)out->mBuffers[0].mData; unsigned w = gMonW, r = gMonR, avail = w - r;
            if (!primed) { if (avail < 1200) { memset(o, 0, frames * sizeof(float)); return noErr; } primed = YES; }  // small cushion before the first sample
            if (avail > 9600) { r = w - 2400; avail = 2400; }                                                        // fell behind: jump back to ~50 ms
            unsigned take = avail < frames ? avail : frames;
            for (unsigned i = 0; i < take; i++) o[i] = gMonRing[(r + i) & 65535];
            if (take < frames) memset(o + take, 0, (frames - take) * sizeof(float));
            gMonR = r + take; return noErr;
        }];
        AVAudioEngine *e = [AVAudioEngine new];
        [e attachNode:src]; [e connect:src to:e.mainMixerNode format:fmt];
        NSError *err = nil;
        if (![e startAndReturnError:&err]) { RYLog(@"monitor start failed: %@", err); gMonOn = 0; return; }
        gMonEng = e;
        static dispatch_once_t once; dispatch_once(&once, ^{
            [NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                AVAudioEngine *g = gMonEng; if (gMonOn && g && !g.isRunning) [g startAndReturnError:nil];
            }];
        });
    });
}
static inline void RYMicFx(float *t, int c, double sr, RYVS *s) { if (RY_FX_ON) RYVoiceBlock(t, c, sr, s); if (gMonOn) RYMonFeed(t, c, sr); }
// interleaved: channel 0 is processed and copied to the other channels
static void RYProcInter(void *data, BOOL isFloat, UInt32 frames, UInt32 ch, double sr, RYVS *s) {
    if (!data || !ch) return; float tmp[2048]; UInt32 done = 0;
    while (done < frames) {
        UInt32 c = frames - done; if (c > 2048) c = 2048;
        if (isFloat) {
            float *p = (float *)data + (size_t)done * ch;
            for (UInt32 j = 0; j < c; j++) tmp[j] = p[j * ch];
            RYMicFx(tmp, (int)c, sr, s);
            for (UInt32 j = 0; j < c; j++) for (UInt32 k = 0; k < ch; k++) p[j * ch + k] = tmp[j];
        } else {
            int16_t *p = (int16_t *)data + (size_t)done * ch;
            for (UInt32 j = 0; j < c; j++) tmp[j] = (float)p[j * ch] / 32768.f;
            RYMicFx(tmp, (int)c, sr, s);
            for (UInt32 j = 0; j < c; j++) { float v = tmp[j] * 32767.f; int16_t q = (int16_t)(v > 32767.f ? 32767 : v < -32768.f ? -32768 : v); for (UInt32 k = 0; k < ch; k++) p[j * ch + k] = q; }
        }
        done += c;
    }
    gMicProc += frames;
}
static void RYProcPlanar(void **planes, UInt32 np, BOOL isFloat, UInt32 frames, double sr, RYVS *s) {
    if (!np || !planes[0]) return; float tmp[2048]; UInt32 done = 0;
    while (done < frames) {
        UInt32 c = frames - done; if (c > 2048) c = 2048;
        if (isFloat) { float *p = (float *)planes[0] + done; for (UInt32 j = 0; j < c; j++) tmp[j] = p[j]; }
        else { int16_t *p = (int16_t *)planes[0] + done; for (UInt32 j = 0; j < c; j++) tmp[j] = (float)p[j] / 32768.f; }
        RYMicFx(tmp, (int)c, sr, s);
        for (UInt32 q = 0; q < np; q++) {
            if (!planes[q]) continue;
            if (isFloat) { float *p = (float *)planes[q] + done; for (UInt32 j = 0; j < c; j++) p[j] = tmp[j]; }
            else { int16_t *p = (int16_t *)planes[q] + done; for (UInt32 j = 0; j < c; j++) { float v = tmp[j] * 32767.f; p[j] = (int16_t)(v > 32767.f ? 32767 : v < -32768.f ? -32768 : v); } }
        }
        done += c;
    }
    gMicProc += frames;
}
// route A/U: raw buffers described by an AudioStreamBasicDescription
static void RYMicProcessASBD(const AudioStreamBasicDescription *f, UInt32 n, AudioBufferList *io, RYVS *s) {
    if (!f || !io || f->mFormatID != kAudioFormatLinearPCM || !io->mNumberBuffers) { gMicSkip++; return; }
    BOOL isFloat = (f->mFormatFlags & kAudioFormatFlagIsFloat) != 0, planar = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 bits = f->mBitsPerChannel, ch = f->mChannelsPerFrame ? f->mChannelsPerFrame : 1;
    if (!((isFloat && bits == 32) || (!isFloat && bits == 16))) { gMicSkip++; return; }
    double sr = f->mSampleRate > 0 ? f->mSampleRate : (gMicHWRate > 0 ? gMicHWRate : 48000);
    if (!planar) {
        AudioBuffer *b = &io->mBuffers[0]; UInt32 frames = b->mDataByteSize / (ch * (bits / 8)); if (frames > n) frames = n;
        RYProcInter(b->mData, isFloat, frames, ch, sr, s);
    } else {
        void *pl[8]; UInt32 np = io->mNumberBuffers > 8 ? 8 : io->mNumberBuffers; UInt32 frames = n;
        for (UInt32 q = 0; q < np; q++) { pl[q] = io->mBuffers[q].mData; UInt32 fq = io->mBuffers[q].mDataByteSize / (bits / 8); if (fq < frames) frames = fq; }
        RYProcPlanar(pl, np, isFloat, frames, sr, s);
    }
}
// ---- route A: the C function AudioUnitRender (the stock WebRTC capture path calls it on input bus 1)
static OSStatus (*orig_aurender)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
static OSStatus RYAURender(AudioUnit u, AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, UInt32 bus, UInt32 n, AudioBufferList *io) {
    OSStatus r = orig_aurender ? orig_aurender(u, fl, ts, bus, n, io) : -50;
    if (r != noErr || bus != 1 || !io) return r;
    gMicCallsA++;
    if (!RY_FX_ON && !gMonOn) return r;
    static AudioUnit lastU; static AudioStreamBasicDescription f; static BOOL ok;
    if (u != lastU) {
        lastU = u; UInt32 sz = sizeof f; memset(&f, 0, sizeof f);
        ok = AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &f, &sz) == noErr;
        snprintf(gMicFmt, sizeof gMicFmt, "A: %.0fHz %uch %ubit %s%s", f.mSampleRate, (unsigned)f.mChannelsPerFrame, (unsigned)f.mBitsPerChannel, (f.mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : "int", (f.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? " planar" : "");
    }
    if (ok) RYMicProcessASBD(&f, n, io, &gVS[0]);
    return r;
}
// ---- route U: AUAudioUnit.renderBlock (apps that drive an AUAudioUnit themselves, e.g. a custom RTCAudioDevice)
static NSMutableDictionary<NSString *, NSValue *> *gRBOrig;
// The format of the captured bus is NOT valid yet when the app asks for the block (it read 0Hz 0ch), so it is read later, off the render thread,
// and until it is known nothing is touched. If the unit never reports one, it is inferred from the buffer layout as a last resort.
typedef struct { AudioStreamBasicDescription f; volatile int have; volatile int tries; volatile int inferred; } RYUCtx;
static BOOL RYFmtFromAU(AUAudioUnit *au, AudioStreamBasicDescription *out) {
    @try {
        AUAudioUnitBusArray *ob = au.outputBusses;
        if (ob.count > 1) {
            const AudioStreamBasicDescription *p = ob[1].format.streamDescription;
            if (p && p->mFormatID == kAudioFormatLinearPCM && p->mSampleRate > 0 && p->mChannelsPerFrame && p->mBitsPerChannel) { *out = *p; return YES; }
        }
    } @catch (__unused id e) {}
    return NO;
}
// float32 audio is finite and within about +-1; int16 samples read as floats come out as NaN/huge or denormal-tiny values
static BOOL RYLooksFloat(const float *p, UInt32 count) {
    UInt32 bad = 0, tiny = 0; if (count > 256) count = 256;
    for (UInt32 i = 0; i < count; i++) { float v = p[i], a = fabsf(v); if (!(a <= 4.f)) bad++; else if (a != 0.f && a < 1e-6f) tiny++; }
    return bad == 0 && tiny == 0;
}
static BOOL RYFmtInfer(const AudioBufferList *io, UInt32 n, AudioStreamBasicDescription *o) {
    if (!n || !io->mNumberBuffers) return NO;
    const AudioBuffer *b0 = &io->mBuffers[0]; if (!b0->mData || b0->mDataByteSize < n || (b0->mDataByteSize % n)) return NO;
    memset(o, 0, sizeof *o); o->mFormatID = kAudioFormatLinearPCM; o->mSampleRate = gMicHWRate > 0 ? gMicHWRate : 48000;
    UInt32 nb = io->mNumberBuffers, per = b0->mDataByteSize / n, ch, sample;
    if (nb == 1) { ch = b0->mNumberChannels ? b0->mNumberChannels : 1; sample = per / ch; }
    else { ch = nb; sample = per; o->mFormatFlags |= kAudioFormatFlagIsNonInterleaved; }
    if (sample == 4 && nb == 1 && !RYLooksFloat((const float *)b0->mData, MIN(n * ch, b0->mDataByteSize / 4))) { sample = 2; ch *= 2; } // really 16-bit with more channels
    else if (sample == 4 && nb > 1 && !RYLooksFloat((const float *)b0->mData, MIN(n, b0->mDataByteSize / 4))) return NO;
    if (sample == 4) o->mFormatFlags |= kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    else if (sample == 2) o->mFormatFlags |= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    else return NO;
    o->mChannelsPerFrame = ch; o->mBitsPerChannel = sample * 8; o->mFramesPerPacket = 1;
    o->mBytesPerFrame = (nb == 1) ? sample * ch : sample; o->mBytesPerPacket = o->mBytesPerFrame;
    return YES;
}
static void RYFmtText(const char *tag, const AudioStreamBasicDescription *f) {
    snprintf(gMicFmt, sizeof gMicFmt, "%s: %.0fHz %uch %ubit %s%s", tag, f->mSampleRate, (unsigned)f->mChannelsPerFrame, (unsigned)f->mBitsPerChannel, (f->mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : "int", (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? " planar" : "");
}
static AURenderBlock RYRBGetter(id self, SEL _cmd) {
    IMP o = NULL; for (Class k = object_getClass(self); k && !o; k = class_getSuperclass(k)) { NSValue *v = gRBOrig[NSStringFromClass(k)]; if (v) o = (IMP)[v pointerValue]; }
    AURenderBlock orig = o ? ((AURenderBlock (*)(id, SEL))o)(self, _cmd) : nil;
    if (!orig) return orig;
    BOOL cap = NO; @try { AUAudioUnit *au = (AUAudioUnit *)self; cap = (au.isInputEnabled || [NSStringFromClass(object_getClass(au)) containsString:@"IO"]) && au.outputBusses.count > 1; } @catch (__unused id e) {}
    if (!cap) return orig; // only units that really capture input
    gMicWrapped++;
    RYUCtx *cx = (RYUCtx *)calloc(1, sizeof(RYUCtx)); __weak AUAudioUnit *wau = (AUAudioUnit *)self;
    return [^AUAudioUnitStatus(AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, AUAudioFrameCount n, NSInteger bus, AudioBufferList *io, AURenderPullInputBlock pull) {
        AUAudioUnitStatus r = orig(fl, ts, n, bus, io, pull);
        if (r != noErr || bus != 1 || !io) return r;
        long long calls = ++gMicCallsU;
        if (calls <= 3 || calls % 2000 == 0) snprintf(gMicLast, sizeof gMicLast, "frames=%u buffers=%u b0: ch=%u bytes=%u data=%d have=%d inferred=%d", (unsigned)n, (unsigned)io->mNumberBuffers, io->mNumberBuffers ? (unsigned)io->mBuffers[0].mNumberChannels : 0, io->mNumberBuffers ? (unsigned)io->mBuffers[0].mDataByteSize : 0, io->mNumberBuffers ? io->mBuffers[0].mData != NULL : 0, cx->have, cx->inferred);
        if (!RY_FX_ON && !gMonOn) return r;
        AudioStreamBasicDescription f;
        if (cx->have) f = cx->f;
        else {
            int t = cx->tries++;
            if (t % 100 == 0) { // ask the unit for its real format, away from the audio thread; until then the buffer layout is used (no waiting)
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    AUAudioUnit *au = wau; AudioStreamBasicDescription g;
                    if (au && RYFmtFromAU(au, &g)) { cx->f = g; cx->inferred = 0; cx->have = 1; RYFmtText("U", &g); }
                });
            }
            if (!RYFmtInfer(io, n, &f)) { gMicSkip++; return r; }
            if (t == 0) { cx->inferred = 1; RYFmtText("U(inferred)", &f); }
        }
        RYMicProcessASBD(&f, n, io, &gVS[1]);
        return r;
    } copy];
}
static void RYInstallRB(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ gRBOrig = [NSMutableDictionary new]; });
    Class base = NSClassFromString(@"AUAudioUnit"); if (!base) return;
    SEL sel = @selector(renderBlock);
    unsigned cnt = 0; Class *all = objc_copyClassList(&cnt);
    for (unsigned i = 0; i < cnt; i++) {
        Class c = all[i], k = c; BOOL isAU = NO;
        for (; k; k = class_getSuperclass(k)) if (k == base) { isAU = YES; break; }
        if (!isAU) continue;
        NSString *nm = NSStringFromClass(c); if (gRBOrig[nm]) continue;
        Method m = class_getInstanceMethod(c, sel); if (!m) continue;
        Class sup = class_getSuperclass(c); Method sm = sup ? class_getInstanceMethod(sup, sel) : NULL;
        if (c != base && m == sm) continue; // inherited, the class that really defines it gets patched
        IMP cur = method_getImplementation(m); if (cur == (IMP)RYRBGetter) continue;
        gRBOrig[nm] = [NSValue valueWithPointer:(const void *)cur];
        class_replaceMethod(c, sel, (IMP)RYRBGetter, method_getTypeEncoding(m));
    }
    free(all);
}
// ---- route T: AVAudioEngine input-node tap (the buffer is changed before the app's own block sees it)
typedef void (^RYTapBlock)(AVAudioPCMBuffer *, AVAudioTime *);
static void (*orig_tap)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, RYTapBlock);
static void RYTapProcess(AVAudioPCMBuffer *b) {
    AVAudioFormat *f = b.format; UInt32 n = b.frameLength, ch = f.channelCount; if (!n || !ch) return;
    if (b.floatChannelData) {
        float *const *cd = b.floatChannelData;
        if (f.isInterleaved) RYProcInter(cd[0], YES, n, ch, f.sampleRate, &gVS[2]);
        else { void *pl[8]; UInt32 np = ch > 8 ? 8 : ch; for (UInt32 q = 0; q < np; q++) pl[q] = cd[q]; RYProcPlanar(pl, np, YES, n, f.sampleRate, &gVS[2]); }
    } else if (b.int16ChannelData) {
        int16_t *const *cd = b.int16ChannelData;
        if (f.isInterleaved) RYProcInter(cd[0], NO, n, ch, f.sampleRate, &gVS[2]);
        else { void *pl[8]; UInt32 np = ch > 8 ? 8 : ch; for (UInt32 q = 0; q < np; q++) pl[q] = cd[q]; RYProcPlanar(pl, np, NO, n, f.sampleRate, &gVS[2]); }
    }
}
static void RYTapInstall(id self, SEL _cmd, AVAudioNodeBus bus, AVAudioFrameCount size, AVAudioFormat *fmt, RYTapBlock blk) {
    RYTapBlock w = blk;
    if (blk && [self isKindOfClass:[AVAudioInputNode class]]) {
        gMicTapInst++;
        w = [^(AVAudioPCMBuffer *b, AVAudioTime *t) { gMicCallsT++; if (RY_FX_ON || gMonOn) RYTapProcess(b); blk(b, t); } copy];
    }
    orig_tap(self, _cmd, bus, size, fmt, w);
}
static void RYInstallTapHook(void) {
    Method m = class_getInstanceMethod([AVAudioNode class], @selector(installTapOnBus:bufferSize:format:block:));
    if (!m || orig_tap) return;
    orig_tap = (void (*)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, RYTapBlock))method_getImplementation(m);
    method_setImplementation(m, (IMP)RYTapInstall);
}

// ---- remove Rave's audio "isolation" (system voice processing, session mode, WebRTC noise/echo/AGC) so loud or effected voice is not ducked or muted
static volatile int gIsoSess = 0, gIsoVP = 0, gIsoRTC = 0;
static volatile long long gIsoSessN = 0, gIsoVPN = 0, gIsoVPFail = 0, gIsoEngN = 0, gIsoRTCN = 0;
// (1) the AVAudioSession mode: VoiceChat / VideoChat switch the system echo canceller, noise suppressor and AGC on
static BOOL (*orig_setMode)(id, SEL, NSString *, NSError **);
static BOOL RYSetMode(id self, SEL _cmd, NSString *m, NSError **e) { if (gIsoSess && m && ![m isEqual:AVAudioSessionModeDefault]) { gIsoSessN++; m = AVAudioSessionModeDefault; } return orig_setMode(self, _cmd, m, e); }
static BOOL (*orig_setCatMode)(id, SEL, NSString *, NSString *, NSUInteger, NSError **);
static BOOL RYSetCatMode(id self, SEL _cmd, NSString *c, NSString *m, NSUInteger o, NSError **e) { if (gIsoSess && m && ![m isEqual:AVAudioSessionModeDefault]) { gIsoSessN++; m = AVAudioSessionModeDefault; } return orig_setCatMode(self, _cmd, c, m, o, e); }
static BOOL (*orig_setCatModeRS)(id, SEL, NSString *, NSString *, NSUInteger, NSUInteger, NSError **);
static BOOL RYSetCatModeRS(id self, SEL _cmd, NSString *c, NSString *m, NSUInteger rs, NSUInteger o, NSError **e) { if (gIsoSess && m && ![m isEqual:AVAudioSessionModeDefault]) { gIsoSessN++; m = AVAudioSessionModeDefault; } return orig_setCatModeRS(self, _cmd, c, m, rs, o, e); }
static void RYIsoApplySession(void) { if (!gIsoSess) return; dispatch_async(dispatch_get_main_queue(), ^{ [AVAudioSession.sharedInstance setMode:AVAudioSessionModeDefault error:nil]; }); }
// (2) the voice-processing audio unit (VPIO): switch its processing off (properties 2100 = bypass, 2101 = AGC) before it initialises / starts
static OSStatus (*orig_auinit)(AudioUnit); static OSStatus (*orig_austart)(AudioUnit);
static void RYBypassVP(AudioUnit u) {
    if (!gIsoVP || !u) return; UInt32 one = 1, zero = 0;
    OSStatus a = AudioUnitSetProperty(u, 2100, kAudioUnitScope_Global, 0, &one, sizeof one);
    AudioUnitSetProperty(u, 2101, kAudioUnitScope_Global, 0, &zero, sizeof zero);
    if (a == noErr) gIsoVPN++; else gIsoVPFail++;
}
static OSStatus RYAUInit(AudioUnit u) { RYBypassVP(u); return orig_auinit ? orig_auinit(u) : -50; }
static OSStatus RYAUStart(AudioUnit u) { RYBypassVP(u); return orig_austart ? orig_austart(u) : -50; }
static BOOL (*orig_setVPE)(id, SEL, BOOL, NSError **);
static BOOL RYSetVPE(id self, SEL _cmd, BOOL on, NSError **e) { if (gIsoVP && on) { gIsoEngN++; on = NO; } return orig_setVPE(self, _cmd, on, e); }
// (3) WebRTC's own software processing: the constraints the app passes when it creates the microphone source
static id (*orig_rtcinit)(id, SEL, NSDictionary *, NSDictionary *);
static id RYRTCInit(id self, SEL _cmd, NSDictionary *m, NSDictionary *o) {
    if (gIsoRTC) {
        NSArray *keys = @[@"googEchoCancellation", @"googEchoCancellation2", @"googDAEchoCancellation", @"googAutoGainControl", @"googAutoGainControl2", @"googNoiseSuppression", @"googNoiseSuppression2", @"googHighpassFilter", @"googTypingNoiseDetection", @"echoCancellation", @"noiseSuppression", @"autoGainControl"];
        NSMutableDictionary *mm = [m mutableCopy] ?: [NSMutableDictionary new], *oo = [o mutableCopy] ?: [NSMutableDictionary new];
        for (NSString *k in keys) { if (mm[k]) mm[k] = @"false"; oo[k] = @"false"; }
        gIsoRTCN++; m = mm; o = oo;
    }
    return orig_rtcinit(self, _cmd, m, o);
}
static void RYInstallIso(void) {
    static BOOL done; if (done) return; done = YES;
    Class S = [AVAudioSession class]; Method m;
    if ((m = class_getInstanceMethod(S, @selector(setMode:error:)))) { orig_setMode = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetMode); }
    if ((m = class_getInstanceMethod(S, @selector(setCategory:mode:options:error:)))) { orig_setCatMode = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetCatMode); }
    if ((m = class_getInstanceMethod(S, @selector(setCategory:mode:routeSharingPolicy:options:error:)))) { orig_setCatModeRS = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetCatModeRS); }
    if ((m = class_getInstanceMethod([AVAudioIONode class], @selector(setVoiceProcessingEnabled:error:)))) { orig_setVPE = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetVPE); }
    unsigned cnt = 0; Class *all = objc_copyClassList(&cnt);
    for (unsigned i = 0; i < cnt && !orig_rtcinit; i++) {
        if (![NSStringFromClass(all[i]) hasSuffix:@"RTCMediaConstraints"]) continue;
        SEL sel = NSSelectorFromString(@"initWithMandatoryConstraints:optionalConstraints:");
        Method mm = class_getInstanceMethod(all[i], sel); if (!mm) continue;
        orig_rtcinit = (void *)method_getImplementation(mm); method_setImplementation(mm, (IMP)RYRTCInit);
    }
    free(all);
}
// ---- settings
static void RYMicLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ double r = AVAudioSession.sharedInstance.sampleRate; if (r > 0) gMicHWRate = r; });
    gMicOn = [CF(@"micOn", @NO) boolValue]; gMicPreset = [CF(@"micPreset", @0) intValue]; gMicSemi = [CF(@"micSemi", @0) floatValue];
    gMicMode = [CF(@"micMode", @0) intValue]; gMicEcho = [CF(@"micEcho", @0) floatValue]; gMicGain = [CF(@"micGain", @1) floatValue];
    gMicDist = [CF(@"micDist", @NO) boolValue]; gMicRev = [CF(@"micRev", @NO) boolValue];
    { NSArray *rc = CF(@"revCfg", nil); // the saved echo settings only count if they were saved with the current defaults (version 2); otherwise start from the Dragonfly values
      if ([CF(@"revCfgVer", @0) intValue] == 2 && [rc isKindOfClass:NSArray.class] && rc.count == RV_N) for (int i = 0; i < RV_N; i++) gRv[i] = [rc[i] floatValue];
      else { NSMutableArray *d = [NSMutableArray new]; for (int i = 0; i < RV_N; i++) { gRv[i] = kRvDef[i]; [d addObject:@(kRvDef[i])]; } CS(@"revCfg", d); CS(@"revCfgVer", @2); } }
    gDistGain = powf(10.f, [CF(@"distDb", @60) floatValue] / 20.f); gDistOut = powf(10.f, [CF(@"distOutDb", @-3) floatValue] / 20.f); gDistGate = powf(10.f, [CF(@"distGateDb", @-55) floatValue] / 20.f);
    gIsoSess = [CF(@"isoSess", @NO) boolValue]; gIsoVP = [CF(@"isoVP", @NO) boolValue]; gIsoRTC = [CF(@"isoRTC", @NO) boolValue];
}
static void RYMicSetOn(BOOL on) { gMicOn = on; CS(@"micOn", @(on)); }
static void RYMicSetDist(BOOL on) { gMicDist = on; CS(@"micDist", @(on)); }
static void RYMicSetRev(BOOL on) { gMicRev = on; CS(@"micRev", @(on)); }
static void RYRevSave(void) { NSMutableArray *a = [NSMutableArray new]; for (int i = 0; i < RV_N; i++) [a addObject:@(gRv[i])]; CS(@"revCfg", a); CS(@"revCfgVer", @2); }
static BOOL RYRevIsDefault(void) { for (int i = 0; i < RV_N; i++) if (fabsf(gRv[i] - kRvDef[i]) > 0.0005f) return NO; return YES; }
static NSString *RYRevStateText(void) { return RYRevIsDefault() ? T(@"الافتراضي ✓", @"Default ✓") : T(@"معدّل", @"Changed"); }
static void RYIsoSave(void) { CS(@"isoSess", @(gIsoSess != 0)); CS(@"isoVP", @(gIsoVP != 0)); CS(@"isoRTC", @(gIsoRTC != 0)); }
static void RYMicApplyPreset(int i) {
    if (i < 0 || i >= RY_NPRESETS) return; const RYPreset *p = &kPresets[i];
    gMicPreset = i; gMicSemi = p->semi; gMicMode = p->mode; gMicEcho = p->echo;
    CS(@"micPreset", @(i)); CS(@"micSemi", @(p->semi)); CS(@"micMode", @(p->mode)); CS(@"micEcho", @(p->echo));
}
static NSString *RYMicStatus(void) {
    long long calls = gMicCallsA + gMicCallsU + gMicCallsT;
    if (!calls) return T(@"لسا ما التقطت المايك. ادخل صوت الغرفة وافتح المايك، وبعدها تظهر الحالة هنا.", @"No microphone data seen yet. Join voice in a room and unmute; the status shows up here.");
    NSString *route = gMicCallsA ? @"A" : gMicCallsU ? @"U" : @"T";
    if (!RY_FX_ON) return [NSString stringWithFormat:T(@"المايك مرصود ✓ (مسار %@)، المغيّر مطفي.", @"Microphone detected ✓ (route %@), changer is off."), route];
    return [NSString stringWithFormat:T(@"يشتغل ✓ (مسار %@، إطارات معالجة: %lld)", @"Working ✓ (route %@, frames processed: %lld)"), route, (long long)gMicProc];
}
static NSString *RYMicStatus2(void) {
    NSString *iso = (gIsoSess || gIsoVP || gIsoRTC) ? [NSString stringWithFormat:T(@"\nإزالة العوازل: جلسة %lld، VPIO %lld (فشل %lld)، WebRTC %lld", @"\nIsolation removal: session %lld, VPIO %lld (failed %lld), WebRTC %lld"), gIsoSessN, gIsoVPN, gIsoVPFail, gIsoRTCN] : @"";
    return [RYMicStatus() stringByAppendingString:iso];
}
static NSString *RYMicReport(void) {
    return [NSString stringWithFormat:@"mic voice changer\non=%d preset=%d semi=%.1f mode=%d echo=%.2f gain=%.2f dist=%d reverb=%d monitor=%d\nroute A (AudioUnitRender bus 1): calls=%lld, images rebound=%d\nroute U (AUAudioUnit renderBlock): calls=%lld, blocks wrapped=%d\nroute T (AVAudioEngine input tap): calls=%lld, taps installed=%d\nframes processed=%lld (skipped calls=%lld)\nformat=%s\nlast buffer: %s\nhw sample rate=%.0f\nisolation removal: session=%d (forced %lld) vpio=%d (bypassed %lld, failed %lld, engine %lld) webrtc=%d (rewritten %lld)\n",
        gMicOn, gMicPreset, gMicSemi, gMicMode, gMicEcho, gMicGain, gMicDist, gMicRev, gMonOn, gMicCallsA, gMicRebound, gMicCallsU, gMicWrapped, gMicCallsT, gMicTapInst, (long long)gMicProc, (long long)gMicSkip, gMicFmt, gMicLast, gMicHWRate, gIsoSess, gIsoSessN, gIsoVP, gIsoVPN, gIsoVPFail, gIsoEngN, gIsoRTC, gIsoRTCN];
}

// minimal symbol-pointer rebinding (same idea as fishhook)
static void RYRebindImage(const struct mach_header *mh, intptr_t slide) {
    if (!mh || mh->magic != MH_MAGIC_64) return;
    Dl_info di; if (dladdr(mh, &di) && di.dli_fname && (strncmp(di.dli_fname, "/usr/lib", 8) == 0 || strncmp(di.dli_fname, "/System", 7) == 0 || strstr(di.dli_fname, "libsystem"))) return;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const struct symtab_command *st = NULL; const struct dysymtab_command *dy = NULL; const struct segment_command_64 *le = NULL;
    const uint8_t *c = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, c += ((const struct load_command *)c)->cmdsize) {
        const struct load_command *lc = (const struct load_command *)c;
        if (lc->cmd == LC_SYMTAB) st = (const struct symtab_command *)lc;
        else if (lc->cmd == LC_DYSYMTAB) dy = (const struct dysymtab_command *)lc;
        else if (lc->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)lc)->segname, SEG_LINKEDIT) == 0) le = (const struct segment_command_64 *)lc;
    }
    if (!st || !dy || !le || !dy->nindirectsyms) return;
    uintptr_t base = (uintptr_t)slide + le->vmaddr - le->fileoff;
    const struct nlist_64 *syms = (const struct nlist_64 *)(base + st->symoff);
    const char *strs = (const char *)(base + st->stroff);
    const uint32_t *ind = (const uint32_t *)(base + dy->indirectsymoff);
    BOOL did = NO;
    c = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, c += ((const struct load_command *)c)->cmdsize) {
        const struct load_command *lc = (const struct load_command *)c;
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *sg = (const struct segment_command_64 *)lc;
        if (strcmp(sg->segname, "__DATA") != 0 && strcmp(sg->segname, "__DATA_CONST") != 0) continue;
        const struct section_64 *sc = (const struct section_64 *)(sg + 1);
        for (uint32_t j = 0; j < sg->nsects; j++, sc++) {
            uint32_t ty = sc->flags & SECTION_TYPE;
            if (ty != S_LAZY_SYMBOL_POINTERS && ty != S_NON_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)((uintptr_t)slide + sc->addr); size_t cnt = sc->size / sizeof(void *);
            const uint32_t *ix = ind + sc->reserved1; BOOL unlocked = NO;
            for (size_t k = 0; k < cnt; k++) {
                uint32_t si = ix[k];
                if (si == INDIRECT_SYMBOL_ABS || si == INDIRECT_SYMBOL_LOCAL || si == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
                const char *nm = strs + syms[si].n_un.n_strx;
                void *rep = NULL, **save = NULL;
                if (strcmp(nm, "_sqlite3_prepare_v2") == 0) { rep = (void *)RYPrep2; save = (void **)&orig_prepare_v2; }
                else if (strcmp(nm, "_sqlite3_prepare_v3") == 0) { rep = (void *)RYPrep3; save = (void **)&orig_prepare_v3; }
                else if (strcmp(nm, "_sqlite3_step") == 0) { rep = (void *)RYStep; save = (void **)&orig_step; }
                else if (strcmp(nm, "_AudioUnitInitialize") == 0) { rep = (void *)RYAUInit; save = (void **)&orig_auinit; }
                else if (strcmp(nm, "_AudioOutputUnitStart") == 0) { rep = (void *)RYAUStart; save = (void **)&orig_austart; }
                else if (strcmp(nm, "_AudioUnitRender") == 0) { rep = (void *)RYAURender; save = (void **)&orig_aurender; if (slots[k] != rep) gMicRebound++; }
                else continue;
                if (slots[k] == rep) continue;
                if (!unlocked) { vm_protect(mach_task_self(), (vm_address_t)slots, sc->size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY); unlocked = YES; }
                // the real function comes from dlsym (a lazy pointer that was not used yet would still point at the dyld stub helper)
                if (!*save) { void *r = dlsym(RTLD_DEFAULT, nm + 1); *save = r ?: slots[k]; }
                slots[k] = rep; did = YES;
            }
        }
    }
    if (did) gAntiDelImages++; // no logging here: this runs inside dyld callbacks
}

// ---- the saved list (newest last) + matching against what is on screen
static NSMutableArray<NSString *> *gDelList;      // as captured
static NSMutableArray<NSString *> *gDelNormList;  // normalized copy, same order
static NSMutableSet<NSString *> *gDelNorm;
static BOOL gMarkRed = YES, gPainted = NO;
static int gRedShown = 0, gRedSeen = 0, gRedTotal = 0;   // per last scan / per last scan / ever
static volatile int gDelVer = 0;
static NSMutableArray<NSString *> *gScreenSample;
static NSString *RYDelFile(void) { return [RYDir(@"data") stringByAppendingPathComponent:@"deleted.json"]; }
// same text, ignoring invisible characters, attachment placeholders and different whitespace
static NSString *RYNorm(NSString *s) {
    if (!s.length) return @"";
    static NSCharacterSet *junk; static dispatch_once_t o;
    dispatch_once(&o, ^{ junk = [NSCharacterSet characterSetWithCharactersInString:@"\uFFFC\u200B\u200C\u200D\u200E\u200F\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069\uFEFF"]; });
    NSString *t = [[s componentsSeparatedByCharactersInSet:junk] componentsJoinedByString:@""];
    NSMutableArray *k = [NSMutableArray new];
    for (NSString *x in [t componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if (x.length) [k addObject:x];
    return [k componentsJoinedByString:@" "];
}
static void RYSaveDeleted(void) {
    NSArray *a; @synchronized(gDelList) { a = [gDelList copy]; }
    NSData *j = a ? [NSJSONSerialization dataWithJSONObject:a options:0 error:nil] : nil; if (j) [j writeToFile:RYDelFile() atomically:YES];
}
static BOOL RYAddDeletedInternal(NSString *raw) {
    NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], *n = RYNorm(t);
    if (n.length < 1 || !gDelList) return NO;
    BOOL added = NO;
    @synchronized(gDelList) {
        if (![gDelNorm containsObject:n]) {
            if (gDelList.count >= 3000) { [gDelNorm removeObject:gDelNormList.firstObject]; [gDelList removeObjectAtIndex:0]; [gDelNormList removeObjectAtIndex:0]; }
            [gDelList addObject:t]; [gDelNormList addObject:n]; [gDelNorm addObject:n]; added = YES; gDelVer++;
        }
    }
    return added;
}
static void RYLoadDeleted(void) {
    gDelList = [NSMutableArray new]; gDelNormList = [NSMutableArray new]; gDelNorm = [NSMutableSet new]; gScreenSample = [NSMutableArray new];
    NSData *j = [NSData dataWithContentsOfFile:RYDelFile()]; NSArray *a = j ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    if ([a isKindOfClass:NSArray.class]) for (id x in a) if ([x isKindOfClass:NSString.class]) RYAddDeletedInternal(x);
}
static void RYAddDeletedString(NSString *s) {
    if (RYAddDeletedInternal(s)) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ RYSaveDeleted(); });
}
static void RYClearDeleted(void) {
    @synchronized(gDelList) { [gDelList removeAllObjects]; [gDelNormList removeAllObjects]; [gDelNorm removeAllObjects]; gDelVer++; }
    RYSaveDeleted();
}
static BOOL RYIsDeletedText(NSString *raw) {
    if (!gMarkRed || !gDelNorm.count || raw.length < 1 || raw.length > 4000) return NO;
    NSString *n = RYNorm(raw); if (n.length < 1) return NO;
    @synchronized(gDelList) {
        if ([gDelNorm containsObject:n]) return YES;
        if (n.length >= 6) { // the bubble may add a name / time around the text
            NSUInteger from = gDelNormList.count > 400 ? gDelNormList.count - 400 : 0;
            for (NSUInteger i = from; i < gDelNormList.count; i++) { NSString *d = gDelNormList[i]; if (d.length >= 6 && n.length <= d.length + 60 && [n containsString:d]) return YES; }
        }
    }
    return NO;
}

static const void *kRYOrig = &kRYOrig, *kRYMemo = &kRYMemo;
static UIColor *RYRedColor(void) { return [UIColor colorWithRed:1 green:0.23 blue:0.27 alpha:1]; }
static BOOL RYIsRed(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0; if (!c || ![c getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return fabs(r - 1) < 0.02 && fabs(g - 0.23) < 0.02 && fabs(b - 0.27) < 0.02;
}
static NSAttributedString *RYAttr(UIView *v) { return [v isKindOfClass:UILabel.class] ? ((UILabel *)v).attributedText : ((UITextView *)v).attributedText; }
static UIColor *RYEffColor(UIView *v) {
    NSAttributedString *a = RYAttr(v);
    if (a.length) { id c = [a attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]; if ([c isKindOfClass:UIColor.class]) return c; }
    return [v isKindOfClass:UILabel.class] ? ((UILabel *)v).textColor : ((UITextView *)v).textColor;
}
static void RYSetColor(UIView *v, UIColor *c) { if ([v isKindOfClass:UILabel.class]) ((UILabel *)v).textColor = c; else ((UITextView *)v).textColor = c; }
static void RYSetAttr(UIView *v, NSAttributedString *a) { if ([v isKindOfClass:UILabel.class]) ((UILabel *)v).attributedText = a; else ((UITextView *)v).attributedText = a; }
static void RYMarkView(UIView *v) {
    BOOL isL = [v isKindOfClass:UILabel.class], isT = [v isKindOfClass:UITextView.class];
    if (!isL && !isT) return;
    if (isT && (((UITextView *)v).isEditable || v.isFirstResponder)) return; // never the box you type in
    NSString *raw = (isL ? ((UILabel *)v).text : ((UITextView *)v).text) ?: @"";
    BOOL chatView = [NSStringFromClass(v.class) containsString:@"NonSelectable"]; // chat bubbles; short texts are only trusted there
    NSDictionary *orig = objc_getAssociatedObject(v, kRYOrig);
    BOOL del = NO;
    if (gMarkRed && raw.length >= 1 && (chatView || raw.length >= 6)) {
        NSArray *memo = objc_getAssociatedObject(v, kRYMemo);
        if (memo && [memo[0] isEqualToString:raw] && [memo[1] intValue] == gDelVer) del = [memo[2] boolValue];
        else { del = RYIsDeletedText(raw); objc_setAssociatedObject(v, kRYMemo, @[raw, @(gDelVer), @(del)], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    }
    if (v.window && !v.hidden && raw.length >= 1) { // what the scan saw, for the diagnostic report
        gRedSeen++;
        if (gScreenSample.count >= 10) [gScreenSample removeObjectAtIndex:0];
        [gScreenSample addObject:[NSString stringWithFormat:@"%@%@<%@>", del ? @"*" : @"", RYClip(raw, 24), chatView ? @"chat" : @"other"]];
    }
    UIColor *red = RYRedColor();
    if (del) {
        if (!orig) {
            NSAttributedString *a = RYAttr(v);
            orig = @{@"c": RYEffColor(v) ?: UIColor.whiteColor, @"a": a.length ? [a copy] : (id)NSNull.null, @"s": raw,
                     @"bg": v.backgroundColor ?: (id)NSNull.null, @"r": @(v.layer.cornerRadius)};
            objc_setAssociatedObject(v, kRYOrig, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC); gRedTotal++;
        }
        // marker 1: red + struck-through text
        NSAttributedString *cur = RYAttr(v);
        BOOL marked = cur.length && [cur attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:NULL] && RYIsRed(RYEffColor(v));
        if (!marked) {
            if (cur.length) {
                NSMutableAttributedString *m = [cur mutableCopy]; NSRange all = NSMakeRange(0, m.length);
                [m addAttribute:NSForegroundColorAttributeName value:red range:all];
                [m addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:all];
                [m addAttribute:NSStrikethroughColorAttributeName value:red range:all];
                RYSetAttr(v, m);
            } else RYSetColor(v, red);
        }
        // marker 2: a red tint behind the text (visible even if the text drawing ignores colours)
        UIColor *tint = [red colorWithAlphaComponent:0.22];
        if (![v.backgroundColor isEqual:tint]) v.backgroundColor = tint;
        if (v.layer.cornerRadius < 6) v.layer.cornerRadius = 6;
        gRedShown++; gPainted = YES;
    } else if (orig) {
        UIColor *oc = orig[@"c"]; id oa = orig[@"a"], bg = orig[@"bg"];
        if ([orig[@"s"] isEqualToString:raw]) {          // same text: put the look back (switch turned off, list cleared)
            if ([oa isKindOfClass:NSAttributedString.class]) RYSetAttr(v, oa); else RYSetColor(v, oc);
        } else {                                          // the app reused this view for another message: take our marks off
            NSAttributedString *cur = RYAttr(v);
            if (cur.length && [cur attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:NULL]) {
                NSMutableAttributedString *m = [cur mutableCopy]; NSRange all = NSMakeRange(0, m.length);
                [m removeAttribute:NSStrikethroughStyleAttributeName range:all]; [m removeAttribute:NSStrikethroughColorAttributeName range:all];
                [m addAttribute:NSForegroundColorAttributeName value:oc range:all]; RYSetAttr(v, m);
            } else if (RYIsRed(RYEffColor(v))) RYSetColor(v, oc);
        }
        v.backgroundColor = [bg isKindOfClass:UIColor.class] ? bg : nil; v.layer.cornerRadius = [orig[@"r"] doubleValue];
        objc_setAssociatedObject(v, kRYOrig, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void RYStartRedTimer(void) {
    RYLoadDeleted(); gMarkRed = [CF(@"markRed", @YES) boolValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *t) {
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            if (!((gMarkRed && gDelList.count) || gPainted)) return;
            gRedShown = 0; gRedSeen = 0; gPainted = NO; [gScreenSample removeAllObjects];
            for (UIWindow *w in RYAppWindows()) RYWalk(w, 0, ^(UIView *x, int d) { RYMarkView(x); });
        }];
    });
}
static void RYSetMarkRed(BOOL on) { gMarkRed = on; CS(@"markRed", @(on)); gDelVer++; }
static void RYInstallRebind(void) {
    static BOOL once; if (once) return; once = YES;
    _dyld_register_func_for_add_image(RYRebindImage); // calls back for every loaded image now and for later ones
}
static void RYInstallMic(void) {
    RYMicLoad(); RYInstallRebind(); RYInstallTapHook(); RYInstallRB(); RYInstallIso(); RYIsoApplySession();
    for (NSNumber *sec in @[@2, @6, @15]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYInstallRB(); }); // AU classes may load late
}
static void RYInstallAntiDelete(void) {
    static BOOL once; if (once) return; once = YES;
    RYStartRedTimer();
    RYInstallRebind();
}
static void RYSetAntiDelete(BOOL on) { gAntiDel = on; CS(@"antiDelete", @(on)); }

static NSString *RYReport(void) {
    NSMutableString *o = [NSMutableString new];
    NSDictionary *inf = NSBundle.mainBundle.infoDictionary;
    [o appendFormat:@"app %@ (%@) | iOS %@ | %@\n", inf[@"CFBundleShortVersionString"], inf[@"CFBundleVersion"], UIDevice.currentDevice.systemVersion, UIDevice.currentDevice.model];
    [o appendFormat:@"anti-delete: %@ | hooked images %d | blocked %d | rows captured %d | deleted texts stored %lu | red labels last scan %d (texts seen %d, painted ever %d) | mark-red %@\n", gAntiDel ? @"on" : @"off", gAntiDelImages, gAntiDelBlocked, gAntiDelRows, (unsigned long)gDelList.count, gRedShown, gRedSeen, gRedTotal, gMarkRed ? @"on" : @"off"];
    { NSArray *dl; @synchronized(gDelList) { dl = [gDelList copy]; } NSMutableArray *lastDel = [NSMutableArray new];
      for (NSInteger i = (NSInteger)dl.count - 1; i >= 0 && lastDel.count < 5; i--) [lastDel addObject:RYClip(dl[i], 24)];
      [o appendFormat:@"saved (newest): %@\nscreen texts (* = painted): %@\nmessage-table SQL seen:\n", [lastDel componentsJoinedByString:@" | "], [gScreenSample componentsJoinedByString:@" | "]];
      NSArray *ord; NSDictionary *cnt; @synchronized(gSqlJ) { ord = [gSqlJOrder copy]; cnt = [gSqlJ copy]; }
      for (NSString *sh in ord) [o appendFormat:@"  %@ x%@\n", sh, cnt[sh]]; }
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
        NSArray *cells = [x isKindOfClass:UITableView.class] ? (NSArray *)((UITableView *)x).visibleCells : (NSArray *)((UICollectionView *)x).visibleCells;
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
    [o appendFormat:@"\n-- event log (newest last) --\n%@\n", RYLogTail()];
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
- (void)hud:(NSString *)s;
- (void)start; - (void)openPanel; - (void)panelClosed; - (void)bump;
- (void)sendMessage:(NSString *)msg done:(void (^)(NSInteger code))done;
// one-shot invite pass over the visible list (Recents / Friends screen)
@property (nonatomic) BOOL invRunning;
@property (nonatomic) NSInteger invSent;
@property (nonatomic, copy) NSString *invStatus;
- (void)startInvites; - (void)stopInvites; - (NSInteger)invCooldownLeft;
@end

#pragma mark - Panel

#pragma mark - Quick-message loop (sends the saved messages one after another until switched off)

static BOOL gMsgLoop = NO; static NSUInteger gMsgIdx = 0, gMsgFails = 0, gMsgSent = 0; static NSInteger gMsgGen = 0;
static UIBackgroundTaskIdentifier gBGTask = 0; // 0 == UIBackgroundTaskInvalid (the constant itself is not a compile-time value)
static void RYBGRenew(BOOL on) { // keeps the process running a bit longer after leaving the app; renewed every message
    UIApplication *app = UIApplication.sharedApplication;
    UIBackgroundTaskIdentifier old = gBGTask; gBGTask = UIBackgroundTaskInvalid;
    if (on) gBGTask = [app beginBackgroundTaskWithName:@"8ubah.loop" expirationHandler:^{
        UIBackgroundTaskIdentifier t = gBGTask; gBGTask = UIBackgroundTaskInvalid; if (t != UIBackgroundTaskInvalid) [app endBackgroundTask:t];
    }];
    if (old != UIBackgroundTaskInvalid) [app endBackgroundTask:old];
}
static void RYMsgLoopStep(NSInteger gen) {
    if (!gMsgLoop || gen != gMsgGen) return;
    RYBGRenew(YES);
    NSArray *msgs = CF(@"messages", @[]);
    if (!msgs.count) { gMsgLoop = NO; RYBGRenew(NO); return; }
    if (gMsgIdx >= msgs.count) gMsgIdx = 0;
    NSString *m = msgs[gMsgIdx++];
    double delay = MAX(2.0, [CF(@"msgDelay", @4.0) doubleValue]); // never faster than every 2 seconds
    [[RYCore shared] sendMessage:m done:^(NSInteger code) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!gMsgLoop || gen != gMsgGen) return;
            if (code == 0) { gMsgSent++; gMsgFails = 0; }
            else if (++gMsgFails >= 3) { gMsgLoop = NO; RYBGRenew(NO); return; } // chat input not available (left the room?) -> stop
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYMsgLoopStep(gen); });
        });
    }];
}
static void RYMsgLoopSet(BOOL on) {
    gMsgLoop = on; gMsgGen++; gMsgFails = 0; gMsgSent = 0;
    if (!on) RYBGRenew(NO);
    if (on) { gMsgIdx = 0; RYMsgLoopStep(gMsgGen); }
}

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

    UILabel *title = RYLabel(@"8ubah", 22, UIFontWeightHeavy, nil); title.numberOfLines = 1;
    UIView *spacer = [UIView new]; [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *close = RYBtn(T(@"إغلاق", @"Close"), NO, ^{ [ws dismissViewControllerAnimated:YES completion:nil]; });
    UIStackView *head = RYHStack(@[title, spacer, close], 8);
    UIScrollView *tabsScroll = [UIScrollView new]; tabsScroll.showsHorizontalScrollIndicator = NO;
    NSArray *names = @[T(@"الخلفيات", @"Backgrounds"), T(@"الدعوات", @"Invites"), T(@"رسائل سريعة", @"Quick messages"), T(@"الإعدادات", @"Settings"), T(@"دخول برابط", @"Join link"), T(@"مايك", @"Mic")];
    // all tabs always shown, in or out of a room (tabs whose feature needs a room just say so when you tap into them there)
    NSArray<NSNumber *> *order = @[@0, @1, @2, @5, @4, @3];
    if (self.tab < 0 || self.tab > 5) self.tab = 0;
    NSMutableArray *tb = [NSMutableArray new];
    for (NSNumber *nn in order) { NSInteger i = nn.integerValue; [tb addObject:RYBtn(names[i], i == self.tab, ^{ ws.tab = i; [ws rebuild]; })]; }
    tabsScroll.hidden = NO;
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
    switch (self.tab) { case 0: [self renderBG]; break; case 1: [self renderInvites]; break; case 2: [self renderMsgs]; break; case 4: [self renderJoin]; break; case 5: [self renderMic]; break; default: [self renderSettings]; }
}

#pragma mark Saved deleted messages
- (void)showDeleted {
    NSArray *a; @synchronized(gDelList) { a = [gDelList copy]; }
    NSMutableString *m = [NSMutableString new]; NSUInteger shown = 0;
    for (NSInteger i = (NSInteger)a.count - 1; i >= 0 && shown < 40; i--, shown++) [m appendFormat:@"• %@\n", RYClip(a[i], 160)];
    UIAlertController *al = [UIAlertController alertControllerWithTitle:T(@"الرسائل المحذوفة المحفوظة (الأحدث أول)", @"Saved deleted messages (newest first)") message:m.length ? m : T(@"ما في شي محفوظ بعد", @"Nothing saved yet") preferredStyle:UIAlertControllerStyleAlert];
    [al addAction:[UIAlertAction actionWithTitle:T(@"نسخ الكل", @"Copy all") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIPasteboard.generalPasteboard.string = [[[a reverseObjectEnumerator] allObjects] componentsJoinedByString:@"\n"];
    }]];
    [al addAction:[UIAlertAction actionWithTitle:T(@"إغلاق", @"Close") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:al animated:YES completion:nil];
}

#pragma mark Locked
- (void)renderLocked {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"اللوحة مقفلة", @"Panel is locked"), 17, UIFontWeightBold, nil),
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
        RYLabel(T(@"دعوة كل اللي بالقائمة", @"Invite everyone in the list"), 16, UIFontWeightBold, nil)])];
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
    UISwitch *lp = [UISwitch new]; lp.on = gMsgLoop; lp.onTintColor = RYAccent(); __weak UISwitch *wlp = lp;
    UILabel *lst = RYLabel(@"", 12, UIFontWeightRegular, RY_MUTED); self.invLabel = lst;
    [lp addAction:[UIAction actionWithHandler:^(UIAction *a) {
        if (wlp.on && ![CF(@"messages", @[]) count]) { wlp.on = NO; [ws toast:T(@"أضف رسالة أول", @"Add a message first")]; return; }
        RYMsgLoopSet(wlp.on);
    }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"إرسال كل الرسائل بتكرار", @"Loop all messages"), 15, UIFontWeightBold, nil), lp], 12),
        lst])];
    [self.stack addArrangedSubview:RYSlider(T(@"الفاصل بين الرسائل (ثواني)", @"Delay between messages (seconds)"), 2, 15, [CF(@"msgDelay", @4.0) floatValue], ^(float v) { CS(@"msgDelay", @(v)); })];
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        ws.invLabel.text = gMsgLoop ? [NSString stringWithFormat:T(@"شغّال... انرسل %lu", @"Running... sent %lu"), (unsigned long)gMsgSent] : T(@"متوقف", @"Stopped");
        if (!gMsgLoop && wlp.on) wlp.on = NO;
    }];
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

#pragma mark Join link
- (void)joinFrom:(NSString *)str {
    __weak typeof(self) ws = self;
    NSURL *u = RYParseRoomURL(str);
    if (!u) { [self toast:T(@"ما لقيت رابط", @"No link found")]; return; }
    [self toast:T(@"جاري الدخول...", @"Joining...")];
    // the overlay window is key while the panel is open and the app may present from the key window: close the panel first
    [ws dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *k = [RYCore shared].prevKey ?: RYAppWindows().firstObject; [k makeKeyWindow];
            [[RYCore shared] hud:T(@"جاري الدخول…", @"Joining…")];
            RYJoinLink(u, ^(BOOL ok) {
                if (ok) { if ([gJoinLog containsString:@"cannot verify"]) [[RYCore shared] hud:T(@"انرسل الرابط للتطبيق (ما أقدر أتأكد وأنت داخل غرفة)", @"Link sent to the app (cannot verify while inside a room)")]; return; }
                UIPasteboard.generalPasteboard.string = gJoinLog ?: @"";
                [[RYCore shared] hud:T(@"ما دخل الغرفة (انسخت التفاصيل، الصقها لي)", @"Could not enter the room (details copied)")];
            });
        });
    }];
}
- (void)renderJoin {
    __weak typeof(self) ws = self;
    UIButton *paste = RYBtn(T(@"لصق من الحافظة ودخول", @"Paste & join"), YES, ^{ [ws joinFrom:UIPasteboard.generalPasteboard.string]; });
    UIButton *type = RYBtn(T(@"كتابة الرابط", @"Type link"), NO, ^{
        [ws ask:T(@"رابط الروم", @"Room link") ph:@"rave.link/..." secure:NO ok:^(NSString *x) { [ws joinFrom:x]; }];
    });
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:RYLabel(T(@"دخول روم برابط", @"Join a room by link"), 15, UIFontWeightBold, nil), RYHStack(@[paste, type], 8), nil];
    [rows addObject:RYBtn(T(@"اختصار", @"Shortcut"), NO, ^{ [ws addShortcut]; })];
    NSArray *list = CF(@"shortcuts", @[]);
    for (NSUInteger i = 0; i < list.count; i++) {
        NSDictionary *d = list[i]; NSString *nm = d[@"n"] ?: @"", *ln = d[@"u"] ?: @"";
        UIButton *go = RYBtn(nm, NO, ^{ [ws joinFrom:ln]; });
        UIButton *del = RYBtn(T(@"حذف", @"Delete"), NO, ^{
            UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:T(@"حذف الاختصار \"%@\"؟", @"Delete shortcut \"%@\"?"), nm] message:nil preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:T(@"إلغاء", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
            [a addAction:[UIAlertAction actionWithTitle:T(@"حذف", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                NSMutableArray *m = [CF(@"shortcuts", @[]) mutableCopy];
                for (NSUInteger j = 0; j < m.count; j++) if ([m[j][@"n"] isEqual:nm] && [m[j][@"u"] isEqual:ln]) { [m removeObjectAtIndex:j]; break; }
                CS(@"shortcuts", m); [ws rebuild];
            }]];
            [ws presentViewController:a animated:YES completion:nil];
        });
        [rows addObject:RYHStack(@[go, del], 8)];
    }
    [self.stack addArrangedSubview:RYCard(rows)];
}
// a saved name + link: shows up as its own button and is kept in the app's saved settings (survives closing the app)
- (void)addShortcut {
    __weak typeof(self) ws = self;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:T(@"اختصار جديد", @"New shortcut") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) { t.placeholder = T(@"اسم الاختصار", @"Name"); t.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) { t.placeholder = @"rave.link/..."; t.keyboardType = UIKeyboardTypeURL; t.autocorrectionType = UITextAutocorrectionTypeNo; t.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addAction:[UIAlertAction actionWithTitle:T(@"إلغاء", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:T(@"تم", @"OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSCharacterSet *ws_ = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        NSString *nm = [a.textFields[0].text stringByTrimmingCharactersInSet:ws_], *ln = [a.textFields[1].text stringByTrimmingCharactersInSet:ws_];
        if (!nm.length || !RYParseRoomURL(ln)) { [ws toast:T(@"اكتب اسم ورابط صحيح", @"Enter a name and a valid link")]; return; }
        NSMutableArray *m = [CF(@"shortcuts", @[]) mutableCopy]; [m addObject:@{@"n": nm, @"u": ln}];
        CS(@"shortcuts", m); [ws rebuild];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Mic
- (void)renderMic {
    __weak typeof(self) ws = self;
    UISwitch *sw = [UISwitch new]; sw.on = gMicOn != 0; sw.onTintColor = RYAccent(); __weak UISwitch *wsw = sw;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetOn(wsw.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"تشغيل مغيّر الصوت", @"Voice changer"), 15, UIFontWeightBold, nil), sw], 12)])];
    NSMutableArray *bs = [NSMutableArray new];
    for (int i = 0; i < RY_NPRESETS; i++) {
        NSString *nm = [NSString stringWithUTF8String:RYAr() ? kPresets[i].ar : kPresets[i].en];
        [bs addObject:RYBtn(nm, i == gMicPreset, ^{ RYMicApplyPreset(i); RYMicSetOn(YES); [ws rebuild]; })];
    }
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"الأصوات", @"Voices"), 15, UIFontWeightBold, nil), RYGrid(bs, 3)])];
    [self.stack addArrangedSubview:RYSlider(T(@"درجة الصوت (نغمات)", @"Pitch (semitones)"), -12, 12, gMicSemi, ^(float v) { gMicSemi = v; gMicPreset = -1; CS(@"micSemi", @(v)); CS(@"micPreset", @(-1)); })];
    [self.stack addArrangedSubview:RYSlider(T(@"الصدى", @"Echo"), 0, 1, gMicEcho, ^(float v) { gMicEcho = v; CS(@"micEcho", @(v)); })];
    [self.stack addArrangedSubview:RYSlider(T(@"مستوى المايك", @"Mic level"), 0.5, 2, gMicGain, ^(float v) { gMicGain = v; CS(@"micGain", @(v)); })];
    UISwitch *s1 = [UISwitch new]; s1.on = gMicDist != 0; s1.onTintColor = RYAccent(); __weak UISwitch *ws1 = s1;
    [s1 addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetDist(ws1.on); }] forControlEvents:UIControlEventValueChanged];
    UISwitch *s2 = [UISwitch new]; s2.on = gMicRev != 0; s2.onTintColor = RYAccent(); __weak UISwitch *ws2 = s2;
    [s2 addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetRev(ws2.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"فضي", @"Silver"), 15, UIFontWeightBold, nil),
        RYHStack(@[RYLabel(T(@"مضخم", @"Amplifier"), 14, UIFontWeightMedium, nil), s1], 12),
        RYHStack(@[RYLabel(T(@"صدى فضي", @"Silver echo"), 14, UIFontWeightMedium, nil), s2], 12)])];
    UISwitch *s3 = [UISwitch new]; s3.on = gMonOn != 0; s3.onTintColor = RYAccent(); __weak UISwitch *ws3 = s3;
    [s3 addAction:[UIAction actionWithHandler:^(UIAction *a) { if (ws3.on) RYMonStart(); else RYMonStop(); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"اسمع صوتي", @"Hear my voice"), 15, UIFontWeightBold, nil), s3], 12)])];
        // ---- amplifier settings
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"إعدادات المضخم", @"Amplifier settings"), 15, UIFontWeightBold, nil)])];
    [self.stack addArrangedSubview:RYSliderV(T(@"التضخيم", @"Gain"), @"dB", 60, 120, [CF(@"distDb", @60) floatValue], NO, 0, ^(float v) { gDistGain = powf(10.f, v / 20.f); CS(@"distDb", @(v)); })];
    [self.stack addArrangedSubview:RYSliderV(T(@"مستوى الخروج", @"Output"), @"dB", -30, 0, [CF(@"distOutDb", @-3) floatValue], NO, 0, ^(float v) { gDistOut = powf(10.f, v / 20.f); CS(@"distOutDb", @(v)); })];
    [self.stack addArrangedSubview:RYSliderV(T(@"عتبة الكتم", @"Gate"), @"dB", -80, -30, [CF(@"distGateDb", @-55) floatValue], NO, 0, ^(float v) { gDistGate = powf(10.f, v / 20.f); CS(@"distGateDb", @(v)); })];
    // ---- room reverb settings (every control of Dragonfly Room Reverb that matters for a mono voice)
    UILabel *rvState = RYLabel(RYRevStateText(), 12, UIFontWeightMedium, RY_MUTED); __weak UILabel *wst = rvState;
    void (^rvReset)(void) = ^{ for (int i = 0; i < RV_N; i++) gRv[i] = kRvDef[i]; RYRevSave(); [ws rebuild]; [ws toast:T(@"رجعت القيم الافتراضية", @"Defaults restored")]; };
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"إعدادات الصدى (Dragonfly)", @"Echo settings (Dragonfly)"), 15, UIFontWeightBold, nil),
        rvState, RYBtn(T(@"رجّع الافتراضي", @"Reset to default"), YES, rvReset)])];
    struct { int i; const char *ar, *en, *u; float mn, mx; BOOL lg; int d; } rv[] = {
        {RV_DRY, "الصوت الأصلي", "Dry Level", "%", 0, 100, NO, 0}, {RV_ELVL, "الانعكاسات المبكرة", "Early Level", "%", 0, 100, NO, 0},
        {RV_ESEND, "إرسال المبكر للذيل", "Early Send", "%", 0, 100, NO, 0}, {RV_LLVL, "الذيل", "Late Level", "%", 0, 100, NO, 0},
        {RV_SIZE, "حجم الغرفة", "Size", "m", 8, 60, NO, 0}, {RV_PRE, "التأخير الأولي", "Predelay", "ms", 0, 300, NO, 0},
        {RV_DECAY, "مدة الصدى", "Decay", "s", 0.1f, 20, NO, 1}, {RV_DIFF, "الانتشار", "Diffuse", "%", 0, 100, NO, 0},
        {RV_SPIN, "سرعة التذبذب", "Spin", "Hz", 0, 5, NO, 2}, {RV_WANDER, "التجوال", "Wander", "%", 0, 100, NO, 0},
        {RV_HC, "قطع الأعلى", "High Cut", "Hz", 2000, 20000, YES, 0}, {RV_EDAMP, "كتم المبكر", "Early Damp", "Hz", 2000, 20000, YES, 0},
        {RV_LDAMP, "كتم الذيل", "Late Damp", "Hz", 2000, 20000, YES, 0}, {RV_LC, "قطع الأدنى", "Low Cut", "Hz", 20, 1000, YES, 0},
        {RV_LB, "تعزيز الباص", "Low Boost", "%", 0, 200, NO, 0}, {RV_BF, "تردد التعزيز", "Boost Freq", "Hz", 100, 2000, YES, 0}};
    for (size_t q = 0; q < sizeof rv / sizeof rv[0]; q++) {
        int ix = rv[q].i;
        [self.stack addArrangedSubview:RYSliderV(T([NSString stringWithUTF8String:rv[q].ar], [NSString stringWithUTF8String:rv[q].en]), [NSString stringWithUTF8String:rv[q].u], rv[q].mn, rv[q].mx, gRv[ix], rv[q].lg, rv[q].d, ^(float v) { gRv[ix] = v; RYRevSave(); wst.text = RYRevStateText(); })];
    }
    [self.stack addArrangedSubview:RYCard(@[RYBtn(T(@"رجّع الافتراضي (الصدى)", @"Reset echo to default"), NO, rvReset)])];
    // ---- remove Rave's isolation
    UISwitch *i1 = [UISwitch new]; i1.on = gIsoSess != 0; i1.onTintColor = RYAccent(); __weak UISwitch *wi1 = i1;
    [i1 addAction:[UIAction actionWithHandler:^(UIAction *a) { gIsoSess = wi1.on; RYIsoSave(); if (gIsoSess) RYIsoApplySession(); }] forControlEvents:UIControlEventValueChanged];
    UISwitch *i2 = [UISwitch new]; i2.on = gIsoVP != 0; i2.onTintColor = RYAccent(); __weak UISwitch *wi2 = i2;
    [i2 addAction:[UIAction actionWithHandler:^(UIAction *a) { gIsoVP = wi2.on; RYIsoSave(); }] forControlEvents:UIControlEventValueChanged];
    UISwitch *i3 = [UISwitch new]; i3.on = gIsoRTC != 0; i3.onTintColor = RYAccent(); __weak UISwitch *wi3 = i3;
    [i3 addAction:[UIAction actionWithHandler:^(UIAction *a) { gIsoRTC = wi3.on; RYIsoSave(); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"إزالة عوازل ريف", @"Remove Rave isolation"), 15, UIFontWeightBold, nil),
        RYHStack(@[RYLabel(T(@"كل العوازل", @"All"), 14, UIFontWeightMedium, nil), RYBtn(T(@"شغّل الكل", @"All on"), YES, ^{ gIsoSess = gIsoVP = gIsoRTC = 1; RYIsoSave(); RYIsoApplySession(); [ws rebuild]; }), RYBtn(T(@"طفّ الكل", @"All off"), NO, ^{ gIsoSess = gIsoVP = gIsoRTC = 0; RYIsoSave(); [ws rebuild]; })], 8),
        RYHStack(@[RYLabel(T(@"وضع الجلسة (بدون صدى/ضجيج النظام)", @"Session mode (no system voice processing)"), 13, UIFontWeightRegular, nil), i1], 12),
        RYHStack(@[RYLabel(T(@"معالج الصوت VPIO (صدى، ضجيج، AGC)", @"VPIO audio unit (echo, noise, AGC)"), 13, UIFontWeightRegular, nil), i2], 12),
        RYHStack(@[RYLabel(T(@"معالجة WebRTC (ضجيج، صدى، AGC)", @"WebRTC processing (noise, echo, AGC)"), 13, UIFontWeightRegular, nil), i3], 12)])];
    self.invLabel = RYLabel(RYMicStatus2(), 13, UIFontWeightMedium, RY_MUTED);
    [self.stack addArrangedSubview:RYCard(@[self.invLabel, RYBtn(T(@"نسخ تشخيص المايك", @"Copy mic diagnostics"), NO, ^{ UIPasteboard.generalPasteboard.string = RYMicReport(); [ws toast:T(@"اننسخ", @"Copied")]; })])];
    [self.invUI invalidate];
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { ws.invLabel.text = RYMicStatus2(); }];
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

    UISwitch *ad = [UISwitch new]; ad.on = gAntiDel; ad.onTintColor = RYAccent(); __weak UISwitch *wad = ad;
    [ad addAction:[UIAction actionWithHandler:^(UIAction *a) { RYSetAntiDelete(wad.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"منع حذف الرسائل الخاصة (عندك بس)", @"Keep deleted private messages (local only)"), 14, UIFontWeightMedium, nil), ad], 12),
        RYLabel([NSString stringWithFormat:T(@"محجوز: %d | صور محقونة: %d", @"Blocked: %d | hooked images: %d"), gAntiDelBlocked, gAntiDelImages], 12, UIFontWeightRegular, RY_MUTED)])];

    UISwitch *rd = [UISwitch new]; rd.on = gMarkRed; rd.onTintColor = RYAccent(); __weak UISwitch *wrd = rd;
    [rd addAction:[UIAction actionWithHandler:^(UIAction *a) { RYSetMarkRed(wrd.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"الرسائل المحذوفة تظهر بالأحمر", @"Show deleted messages in red"), 14, UIFontWeightMedium, nil), rd], 12),
        RYLabel([NSString stringWithFormat:T(@"المحفوظ: %lu رسالة", @"Remembered: %lu messages"), (unsigned long)gDelList.count], 12, UIFontWeightRegular, RY_MUTED),
        RYBtn(T(@"عرض المحذوفة المحفوظة", @"Show saved messages"), YES, ^{ [ws showDeleted]; }),
        RYBtn(T(@"مسح قائمة المحذوفة", @"Clear deleted list"), NO, ^{ RYClearDeleted(); [ws rebuild]; [ws toast:T(@"انمسحت", @"Cleared")]; })])];

    NSMutableArray *key = [NSMutableArray arrayWithObject:RYLabel(T(@"مفتاح الفتح", @"Unlock key"), 15, UIFontWeightBold, nil)];
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
        RYBtn(T(@"نسخ قائمة الشاشات", @"Copy screen list"), NO, ^{
            NSMutableString *o = [NSMutableString new]; for (UIWindow *w in RYAppWindows()) RYDump(w.rootViewController, 0, o);
            UIPasteboard.generalPasteboard.string = o; [ws toast:T(@"اننسخت قائمة الشاشات", @"Screen list copied")];
        }),
        RYBtn(T(@"نسخ أسماء الصور بالشاشة", @"Copy on-screen image names"), NO, ^{ UIPasteboard.generalPasteboard.string = RYImageReport(); [ws toast:T(@"اننسخت", @"Copied")]; }),
        RYBtn(T(@"نسخ تقرير تشخيصي", @"Copy diagnostic report"), YES, ^{ UIPasteboard.generalPasteboard.string = RYReport(); [ws toast:T(@"اننسخ التقرير", @"Report copied")]; }),
        RYBtn([NSString stringWithFormat:T(@"اسم العلامة: %@", @"Brand name: %@"), RYBrand()], NO, ^{
            [ws ask:T(@"الاسم اللي يظهر بدل rave", @"Name shown instead of rave") ph:@"8ubah" secure:NO ok:^(NSString *x) { CS(@"brandName", x.length ? x : nil); CS(@"brandOn", @(x.length > 0)); [ws rebuild]; }];
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
    for (NSString *k in @[@"lang", @"accent", @"autoOpen", @"bgMode", @"bgValue", @"blur", @"dim", @"messages", @"brand", @"roomClass", @"bx", @"by", @"shortcuts"]) if (o[k]) CS(k, o[k]);
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
static NSMutableString *gInvLog; static NSInteger gInvOK;
// activate one invite control. events first (works for UIKit buttons and UIAction buttons), accessibility activation as a delayed fallback
static void RYActivateCtl(id b) {
    if (!gInvLog) gInvLog = [NSMutableString new];
    if ([b isKindOfClass:UIControl.class]) {
        UIControl *c = (UIControl *)b; NSString *k0 = RYCtlKey(c); __weak UIControl *wc = c;
        [gInvLog appendFormat:@"ctl %@ key=%@ events=%lu\n", NSStringFromClass(c.class), k0, (unsigned long)c.allControlEvents];
        [c sendActionsForControlEvents:UIControlEventTouchDown];
        [c sendActionsForControlEvents:UIControlEventTouchUpInside];
        [c sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIControl *x = wc;
            if (!x || !x.window || !x.enabled || ![RYCtlKey(x) isEqualToString:k0]) { gInvOK++; [gInvLog appendFormat:@"  changed after tap: ok (%@)\n", k0]; return; }
            BOOL r = [x accessibilityActivate];
            [gInvLog appendFormat:@"  unchanged -> a11y activate=%d (%@)\n", r, k0];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIControl *y = wc;
                if (!y || !y.window || !y.enabled || ![RYCtlKey(y) isEqualToString:k0]) { gInvOK++; [gInvLog appendFormat:@"  changed after a11y: ok (%@)\n", k0]; }
                else [gInvLog appendFormat:@"  STILL unchanged (%@)\n", k0];
            });
        });
    } else {
        BOOL r = [b accessibilityActivate];
        [gInvLog appendFormat:@"elem %@ a11y=%d key=%@\n", NSStringFromClass([b class]), r, RYA11yKey(b)];
        if (r) gInvOK++;
    }
}
#pragma mark - Invite flow: tick the circle on every row, then press "Send N invites"

static NSInteger gInvPendBefore, gInvPendMethod, gInvPendTicks, gInvFail, gInvMethod = -1, gInvSelected, gInvSendWait;
static BOOL gInvPend, gInvSending, gInvFinalSend, gInvDumped;
static __weak UIView *gInvPendCell;
static NSTimeInterval gInvPendT, gInvEndT, gInvChkT, gInvSendUntil; static NSInteger gInvChkBefore; static BOOL gInvChkOn;
static NSTimeInterval RYNow(void) { return [NSDate date].timeIntervalSince1970; }

static NSString *RYAsciiDigits(NSString *s) {
    NSMutableString *o = [NSMutableString new];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x0660 && c <= 0x0669) c = (unichar)('0' + (c - 0x0660));
        else if (c >= 0x06F0 && c <= 0x06F9) c = (unichar)('0' + (c - 0x06F0));
        [o appendFormat:@"%C", c];
    }
    return o;
}
// UIKit has no public "perform this tap recognizer", so call the recognizer's own targets
static BOOL RYFireTap(UIView *v) {
    BOOL fired = NO;
    for (UIGestureRecognizer *g in v.gestureRecognizers) {
        if (![g isKindOfClass:UITapGestureRecognizer.class] || !g.enabled) continue;
        @try {
            for (id t in (NSArray *)[g valueForKey:@"targets"]) {
                id target = [t valueForKey:@"target"];
                Ivar iv = class_getInstanceVariable([t class], "_action");
                if (!target || !iv) continue;
                SEL a = *(SEL *)((char *)(__bridge void *)t + ivar_getOffset(iv));
                if (a && [target respondsToSelector:a]) { ((void (*)(id, SEL, id))objc_msgSend)(target, a, g); fired = YES; }
            }
        } @catch (__unused id e) {}
    }
    return fired;
}
static BOOL RYTapAncestors(UIView *x) {
    int d = 0;
    for (UIView *p = x; p && ![p isKindOfClass:UIWindow.class] && d < 6; p = p.superview, d++) {
        if ([p isKindOfClass:UIControl.class] && ((UIControl *)p).enabled) {
            UIControl *c = (UIControl *)p;
            [c sendActionsForControlEvents:UIControlEventTouchDown];
            [c sendActionsForControlEvents:UIControlEventTouchUpInside];
            [c sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            return YES;
        }
        if (RYFireTap(p)) return YES;
    }
    return [x accessibilityActivate];
}
// the "Send N invites" button that shows up after rows are ticked; count = N (0 when there is no such button)
static UIView *RYFindSendBtn(NSInteger *count) {
    NSArray *words = @[@"ارسل", @"أرسل", @"إرسال", @"ارسال", @"send", @"invite", @"دعو", @"دعوات"];
    __block UIView *found = nil; __block NSInteger cnt = 0;
    for (UIWindow *w in RYAppWindows()) RYWalk(w, 0, ^(UIView *x, int d) {
        if (found || x.hidden || x.alpha < 0.05 || !x.window) return;
        NSString *t = nil;
        if ([x isKindOfClass:UILabel.class]) t = ((UILabel *)x).text;
        else if ([x isKindOfClass:UIButton.class]) { UIButton *b = (UIButton *)x; t = [b titleForState:UIControlStateNormal] ?: b.configuration.title; }
        if (!t.length) return;
        NSString *l = RYAsciiDigits(t).lowercaseString;
        BOOL hit = NO; for (NSString *k in words) if ([l containsString:k]) { hit = YES; break; }
        if (!hit) return;
        NSInteger n = -1;
        for (NSUInteger i = 0; i < l.length; i++) {
            unichar c = [l characterAtIndex:i];
            if (c >= '0' && c <= '9') { n = 0; while (i < l.length && [l characterAtIndex:i] >= '0' && [l characterAtIndex:i] <= '9') { n = n * 10 + ([l characterAtIndex:i] - '0'); i++; } break; }
        }
        if (n < 0) return;
        for (UIView *p = x; p; p = p.superview) if ([p isKindOfClass:UITableView.class] || [p isKindOfClass:UICollectionView.class]) return; // names in the list are not the button
        if (!RYVisible(x)) return;
        found = x; cnt = n;
    });
    if (count) *count = found ? cnt : 0;
    return found;
}
static NSInteger RYSendCountNow(void) { NSInteger c = 0; RYFindSendBtn(&c); return c; }
// the empty circle is at the far right of the row; the person+ icon further left must never be touched
static UIView *RYCircleIn(UIView *cell) {
    CGRect cf = [cell convertRect:cell.bounds toView:nil];
    __block UIView *best = nil; __block CGFloat bx = -1e9;
    RYWalk(cell, 0, ^(UIView *x, int d) {
        if (x == cell || x.hidden || x.alpha < 0.05) return;
        CGRect f = [x convertRect:x.bounds toView:nil];
        if (f.size.width > 70 || f.size.height > 70 || f.size.width < 10) return;
        if (CGRectGetMidX(f) < CGRectGetMaxX(cf) - 48) return;
        if (!([x isKindOfClass:UIControl.class] || x.gestureRecognizers.count)) return;
        if (CGRectGetMidX(f) > bx) { bx = CGRectGetMidX(f); best = x; }
    });
    return best;
}
// four ways to tick a row, tried in order until the "Send N" counter goes up
static BOOL RYSelectRow(UIScrollView *sv, UIView *cell, NSInteger m) {
    if (m == 0) {
        UIView *c = RYCircleIn(cell); if (![c isKindOfClass:UIControl.class]) return NO;
        UIControl *ct = (UIControl *)c;
        [ct sendActionsForControlEvents:UIControlEventTouchDown]; [ct sendActionsForControlEvents:UIControlEventTouchUpInside]; [ct sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        return YES;
    }
    if (m == 1) {
        UIView *c = RYCircleIn(cell); int d = 0;
        for (UIView *p = c; p && p != cell && d < 3; p = p.superview, d++) if (RYFireTap(p)) return YES;
        return NO;
    }
    if ([sv isKindOfClass:UICollectionView.class]) {
        UICollectionView *cv = (UICollectionView *)sv; NSIndexPath *ip = [cv indexPathForCell:(UICollectionViewCell *)cell]; id dl = cv.delegate;
        if (!ip || ![dl respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) return NO;
        if (m == 3) [cv selectItemAtIndexPath:ip animated:NO scrollPosition:UICollectionViewScrollPositionNone];
        [dl collectionView:cv didSelectItemAtIndexPath:ip]; return YES;
    }
    if ([sv isKindOfClass:UITableView.class]) {
        UITableView *tv = (UITableView *)sv; NSIndexPath *ip = [tv indexPathForCell:(UITableViewCell *)cell]; id dl = tv.delegate;
        if (!ip || ![dl respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        if (m == 3) [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
        [dl tableView:tv didSelectRowAtIndexPath:ip]; return YES;
    }
    return NO;
}
static void RYRowDump(UIView *cell) {
    [gInvLog appendFormat:@"ROW %@ list-delegate=%@\n", NSStringFromClass(cell.class), NSStringFromClass([[(UIScrollView *)cell.superview valueForKey:@"delegate"] class] ?: NSObject.class)];
    CGRect cf = [cell convertRect:cell.bounds toView:nil];
    RYWalk(cell, 0, ^(UIView *x, int d) {
        CGRect f = [x convertRect:x.bounds toView:nil];
        [gInvLog appendFormat:@"%@%@ x=%.0f w=%.0fx%.0f ctl=%d ui=%d gr=%lu a11y=%@\n", [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0], NSStringFromClass(x.class),
            f.origin.x - cf.origin.x, f.size.width, f.size.height, [x isKindOfClass:UIControl.class], x.userInteractionEnabled, (unsigned long)x.gestureRecognizers.count, RYClip(x.accessibilityLabel ?: @"", 20)];
    });
}
@implementation RYCore
+ (instancetype)shared { static RYCore *c; static dispatch_once_t t; dispatch_once(&t, ^{ c = [RYCore new]; }); return c; }
- (void)bump { self.stamp++; }

- (void)hud:(NSString *)s {
    UIView *host = self.win.rootViewController.view; if (!host) return;
    UILabel *l = RYLabel(s, 14, UIFontWeightMedium, nil); l.textAlignment = NSTextAlignmentCenter; l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    l.layer.cornerRadius = 12; l.clipsToBounds = YES; l.userInteractionEnabled = NO;
    CGSize z = [l sizeThatFits:CGSizeMake(host.bounds.size.width - 60, CGFLOAT_MAX)];
    l.frame = CGRectMake(0, 0, z.width + 28, z.height + 18); l.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height - 110);
    [host addSubview:l];
    [UIView animateWithDuration:0.4 delay:4 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
}
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
    self.fab.hidden = NO; self.fab.backgroundColor = RYAccent();
    if (in && !self.wasIn && [CF(@"autoOpen", @NO) boolValue] && !RYLocked()) [self openPanel];
    if (in != self.wasIn) RYLog(in ? @"room: opened" : @"room: CLOSED (app state %ld)", (long)UIApplication.sharedApplication.applicationState);
    self.wasIn = in;
    [self syncBG:room];
    static int brandTick = 0; brandTick++;
    NSString *pat = ([CF(@"brandOn", @NO) boolValue] && brandTick % 5 == 1) ? CF(@"brand", RY_BRAND_TOKENS) : @""; // logo walk only every ~4s: keeps the main thread free
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
    if (self.invRunning) { self.invRunning = NO; if (gInvOK > 0) gInvLast = RYNow(); self.invStatus = [NSString stringWithFormat:T(@"وقف. حُدّد %ld.", @"Stopped. %ld selected."), (long)self.invSent]; }
}
- (void)startInvites {
    if (self.invRunning || [self invCooldownLeft] > 0) return;
    gInvDone = [NSMutableSet new]; gInvIdle = 0; gInvLog = [NSMutableString new]; gInvOK = 0; self.invSent = 0; self.invRunning = YES; self.invStatus = T(@"أبحث عن القائمة…", @"Looking for the list…");
    gInvPend = NO; gInvSending = NO; gInvFinalSend = NO; gInvDumped = NO; gInvFail = 0; gInvSelected = 0; gInvMethod = -1; gInvPendCell = nil;
    gInvEndT = 0; gInvChkOn = NO; gInvSendUntil = 0;
    gInvTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(invStep) userInfo:nil repeats:YES];
}
- (void)invFinish:(NSString *)why {
    [gInvTimer invalidate]; gInvTimer = nil; self.invRunning = NO; if (gInvOK > 0) gInvLast = RYNow();
    self.invStatus = [NSString stringWithFormat:@"%@ %ld", why, (long)self.invSent];
    if (gInvOK == 0 && gInvLog.length) { UIPasteboard.generalPasteboard.string = gInvLog; self.invStatus = [self.invStatus stringByAppendingString:T(@" — ما تحدد أحد، انسخت التفاصيل", @" - nothing got selected, details copied")]; }
}
// press "Send N invites"; final = the list is finished
- (void)invPressSend:(BOOL)final {
    NSInteger c = 0; UIView *b = RYFindSendBtn(&c);
    BOOL ok = b ? RYTapAncestors(b) : NO;
    [gInvLog appendFormat:@"send button %@ (%ld selected) pressed=%d\n", b ? NSStringFromClass(b.class) : @"NOT FOUND", (long)c, ok];
    if (!ok) {
        UIPasteboard.generalPasteboard.string = gInvLog;
        [self invFinish:T(@"ما قدرت أضغط زر الإرسال (انسخت التفاصيل). المحدد:", @"Could not press the send button (details copied). Selected:")];
        return;
    }
    self.invStatus = [NSString stringWithFormat:T(@"ضغط إرسال (%ld)", @"Pressed send (%ld)"), (long)c];
    gInvSending = YES; gInvSendUntil = RYNow() + (final ? 1.2 : 1.5); gInvFinalSend = final; gInvPend = NO; gInvChkOn = NO; gInvSelected = 0; gInvFail = 0;
}
// 10 ticks a second. Phase 1 (learning): tick one row at a time and watch the "Send N" counter to find which tap method works.
// Phase 2 (fast): tick every visible row at once with that method, scroll, repeat (up to 4 screens per tick), check the counter afterwards.
- (void)invStep {
    NSTimeInterval now = RYNow();
    if (gInvSending) {
        if (now < gInvSendUntil) return;
        gInvSending = NO;
        if (gInvFinalSend) { [self invFinish:T(@"خلصت وانرسلت الدعوات. المحدد:", @"Done, invites sent. Selected:")]; return; }
    }
    UIScrollView *sv = RYBiggestList();
    if (!sv) { if (++gInvIdle > 30) [self invFinish:T(@"ما لقيت قائمة بالشاشة. المحدد:", @"No list on screen. Selected:")]; return; }
    if (gInvPend) { // learning: did the last tap move the counter?
        NSInteger c = RYSendCountNow(); UIView *pc = gInvPendCell;
        if (c > gInvPendBefore) {
            gInvPend = NO; gInvSelected = c; self.invSent++; gInvOK++; gInvFail = 0; gInvMethod = gInvPendMethod;
            [gInvLog appendFormat:@"  ticked (method %ld), counter=%ld -> fast mode\n", (long)gInvPendMethod, (long)c];
        } else if (now - gInvPendT < 0.7) { return; }
        else {
            NSInteger m = gInvPendMethod + 1; BOOL again = NO;
            while (pc && m <= 3) { if (RYSelectRow(sv, pc, m)) { gInvPendMethod = m; gInvPendT = now; again = YES; break; } m++; }
            if (again) { [gInvLog appendFormat:@"  no change, trying method %ld\n", (long)m]; return; }
            gInvPend = NO; gInvFail++; [gInvLog appendString:@"  row could not be ticked\n"];
            if (!gInvDumped && pc) { gInvDumped = YES; RYRowDump(pc); }
        }
    }
    if (gInvChkOn && now - gInvChkT > 0.8) { // fast mode: did the batch move the counter?
        gInvChkOn = NO; NSInteger c = RYSendCountNow();
        if (c > gInvChkBefore) { gInvSelected = c; gInvFail = 0; }
        else { gInvFail += 2; [gInvLog appendFormat:@"batch check: counter %ld did not rise (was %ld)\n", (long)c, (long)gInvChkBefore]; }
    }
    if (gInvFail >= 3) { // refused repeatedly: a selection limit (send what we have) or the tap does not reach the circle
        if (gInvSelected > 0) { [self invPressSend:NO]; return; }
        [self invFinish:T(@"ما قدرت أحدد الدايرة. المحدد:", @"Could not tick the circle. Selected:")]; return;
    }
    BOOL anyNew = NO;
    for (int pass = 0; pass < 4; pass++) {
        NSInteger tapped = 0;
        for (UIView *cell in RYVisibleCells(sv)) {
            NSMutableString *key = [NSMutableString new]; RYCellTexts(cell, key, 0);
            if (!key.length) [key appendFormat:@"%p", cell];
            if ([gInvDone containsObject:key]) continue;
            [gInvDone addObject:key]; anyNew = YES;
            if (gInvMethod < 0) { // learning: one row, then wait for the counter
                gInvPendBefore = RYSendCountNow(); gInvPendCell = cell; gInvPendT = now;
                BOOL started = NO;
                for (NSInteger m = 0; m <= 3; m++) if (RYSelectRow(sv, cell, m)) { gInvPendMethod = m; started = YES; break; }
                [gInvLog appendFormat:@"row %@ method=%ld started=%d\n", RYClip(key, 30), (long)gInvPendMethod, started];
                if (!started) { gInvFail++; if (!gInvDumped) { gInvDumped = YES; RYRowDump(cell); } continue; }
                gInvPend = YES; gInvIdle = 0; gInvEndT = 0;
                self.invStatus = [NSString stringWithFormat:T(@"أحدد: %@", @"Selecting: %@"), RYClip(key, 24)];
                return;
            }
            if (!gInvChkOn && tapped == 0) gInvChkBefore = RYSendCountNow();
            if (RYSelectRow(sv, cell, gInvMethod)) tapped++;
        }
        if (tapped > 0) {
            self.invSent += tapped; gInvOK += tapped; gInvIdle = 0;
            if (!gInvChkOn) { gInvChkOn = YES; gInvChkT = now; }
            self.invStatus = [NSString stringWithFormat:T(@"حُدّد %ld…", @"Selected %ld…"), (long)self.invSent];
        }
        if (gInvMethod < 0) break;
        CGFloat maxY = sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.size.height;
        if (sv.contentOffset.y >= maxY - 2) break;
        [sv setContentOffset:CGPointMake(sv.contentOffset.x, MIN(maxY, sv.contentOffset.y + sv.bounds.size.height * 0.8)) animated:NO];
        [sv layoutIfNeeded];
    }
    CGFloat maxY = sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.size.height;
    if (anyNew) { gInvEndT = 0; return; }
    if (gInvMethod < 0 || gInvPend) return;
    if (sv.contentOffset.y >= maxY - 2) { // at the bottom with nothing new: wait a moment (the app may load more rows), then send
        if (!gInvEndT) gInvEndT = now;
        if (now - gInvEndT > 1.2 && !gInvChkOn) {
            if (RYSendCountNow() > 0) [self invPressSend:YES]; else [self invFinish:T(@"خلصت القائمة. المحدد:", @"Reached the end. Selected:")];
        }
    } else gInvEndT = 0;
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
    // crash-loop guard: if the previous launch died within 10 seconds, this launch skips the risky parts (Anti-AFK, audio hooks)
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL safe = [ud boolForKey:@"8ubah.launching"];
    [ud setBool:YES forKey:@"8ubah.launching"]; [ud synchronize];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ud setBool:NO forKey:@"8ubah.launching"]; [ud synchronize]; });
    RYStartEventLog();
    gAntiDel = [CF(@"antiDelete", @YES) boolValue];
    RYLog(@"mode: %@", safe ? @"SAFE (previous launch crashed)" : @"normal");
    if (!safe) RYInstallAntiDelete();
    if (!safe) RYInstallMic();
    gKeepOn = YES; // Anti-AFK is always on: no switch, not stored, not importable
    if (!safe) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [[RYKeep shared] start]; });
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [[RYKeep shared] start]; }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [[RYCore shared] start]; }];
}
