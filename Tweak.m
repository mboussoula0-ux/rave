// Layan — local feature set (injected dylib) (injected dylib)
// Pure Objective-C runtime: no Substrate / no Logos, so it works with Feather / ESign / Sideloadly injection.
// UNTESTED on a device: class names are tunable from Settings > Advanced.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
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
    NSString *b = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Layan"] copy];
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
    NSData *d = [[@"layan|" stringByAppendingString:s ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
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
// calls the same entry points iOS would call for a tapped Universal Link
static NSMutableString *gJoinLog;
static BOOL RYDeliverURL(NSURL *u) {
    UIApplication *app = UIApplication.sharedApplication;
    BOOL web = [u.scheme.lowercaseString hasPrefix:@"http"];
    BOOL handled = NO;
    [gJoinLog appendFormat:@"deliver: %@\n", u];
    id ad = app.delegate;
    if (web) { // NSUserActivity.webpageURL accepts only http/https (anything else throws)
        NSUserActivity *act = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        act.webpageURL = u;
        for (UIScene *sc in app.connectedScenes) {
            id d = sc.delegate;
            BOOL r = [d respondsToSelector:@selector(scene:continueUserActivity:)];
            [gJoinLog appendFormat:@" scene %@ continue: %@\n", NSStringFromClass([d class]), r ? @"yes" : @"no"];
            if (r) { [d scene:sc continueUserActivity:act]; handled = YES; }
        }
        BOOL ra = [ad respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)];
        [gJoinLog appendFormat:@" appdelegate continue: %@\n", ra ? @"yes" : @"no"];
        if (!handled && ra) {
            handled = [ad application:app continueUserActivity:act restorationHandler:^(NSArray<id<UIUserActivityRestoring>> *x) {}];
            [gJoinLog appendFormat:@"  -> returned %d\n", handled];
        }
    }
    BOOL ro = [ad respondsToSelector:@selector(application:openURL:options:)];
    [gJoinLog appendFormat:@" appdelegate openURL: %@\n", ro ? @"yes" : @"no"];
    if (!handled && ro) {
        handled = [ad application:app openURL:u options:@{}];
        [gJoinLog appendFormat:@"  -> returned %d\n", handled];
    }
    if (!handled && !web) { // custom scheme registered by the app itself: let iOS route it back to us
        [app openURL:u options:@{} completionHandler:nil];
        [gJoinLog appendString:@" UIApplication openURL fired\n"]; handled = YES;
    }
    return handled;
}
// the landing page of a short link usually contains the real deep link: collect every URL in it, app schemes first
static NSArray<NSURL *> *RYCandidates(NSString *html) {
    if (!html.length) return @[];
    html = [html stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    html = [html stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    NSMutableOrderedSet *out = [NSMutableOrderedSet new];
    NSArray *noise = @[@"apple.com", @"google", @"gstatic", @"w3.org", @"facebook", @"twitter", @"fonts.", @"schema.org", @"cloudflare", @"jsdelivr", @"cdnjs", @"itunes"];
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
        NSURL *g = [NSURL URLWithString:[@"wemesh://mesh/" stringByAppendingString:id_]]; if (g) [out addObject:g];
    }
    return [[out array] sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSURL *p, NSURL *q) {
        BOOL cp = ![p.scheme.lowercaseString hasPrefix:@"http"], cq = ![q.scheme.lowercaseString hasPrefix:@"http"];
        return cp == cq ? NSOrderedSame : (cp ? NSOrderedAscending : NSOrderedDescending);
    }];
}
static void RYJoinLink(NSURL *u, void (^done)(BOOL)) {
    gJoinLog = [NSMutableString stringWithFormat:@"link: %@\n", u];
    if (RYDeliverURL(u)) { done(YES); return; }
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u]; r.timeoutInterval = 8;
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        NSURL *f = resp.URL;
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        NSString *html = d.length ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [gJoinLog appendFormat:@"fetch: status=%ld error=%@ final=%@ bytes=%lu\n", (long)code, e.localizedDescription, f, (unsigned long)d.length];
            BOOL ok = (f && ![f isEqual:u]) ? RYDeliverURL(f) : NO;
            if (!ok && html) {
                NSArray *c = RYCandidates(html); [gJoinLog appendFormat:@"candidates: %lu\n", (unsigned long)c.count];
                int n = 0; for (NSURL *cu in c) { if (n++ >= 8) break; if (RYDeliverURL(cu)) { ok = YES; break; } }
            }
            if (!ok && html) [gJoinLog appendFormat:@"html:\n%@\n", html.length > 1800 ? [html substringToIndex:1800] : html];
            done(ok);
        });
    }] resume];
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
    if (on) gBGTask = [app beginBackgroundTaskWithName:@"layan.loop" expirationHandler:^{
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

    UILabel *title = RYLabel(RYBrand(), 22, UIFontWeightHeavy, nil); title.numberOfLines = 1;
    UIView *spacer = [UIView new]; [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *close = RYBtn(T(@"إغلاق", @"Close"), NO, ^{ [ws dismissViewControllerAnimated:YES completion:nil]; });
    UIStackView *head = RYHStack(@[title, spacer, close], 8);
    UIScrollView *tabsScroll = [UIScrollView new]; tabsScroll.showsHorizontalScrollIndicator = NO;
    NSArray *names = @[T(@"الخلفيات", @"Backgrounds"), T(@"الدعوات", @"Invites"), T(@"رسائل سريعة", @"Quick messages"), T(@"دخول برابط", @"Join link"), T(@"الإعدادات", @"Settings")];
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
    switch (self.tab) { case 0: [self renderBG]; break; case 1: [self renderInvites]; break; case 2: [self renderMsgs]; break; case 3: [self renderJoin]; break; default: [self renderSettings]; }
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
        RYLabel(T(@"افتح شاشة الريسنت (أو الأصدقاء) في Layan، وخلّها ظاهرة، وبعدين اضغط ابدأ. يمر على كل شخص مرة وحدة بس، وبعدها يوقف. ما يعيد الإرسال لنفس الناس.", @"Open the Recents (or Friends) screen in Rave and keep it visible, then press Start. It goes through each person once and stops. It never re-sends to the same people."), 13, UIFontWeightRegular, RY_MUTED)])];
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
    UISwitch *lp = [UISwitch new]; lp.on = gMsgLoop; lp.onTintColor = RYAccent(); __weak UISwitch *wlp = lp;
    UILabel *lst = RYLabel(@"", 12, UIFontWeightRegular, RY_MUTED); self.invLabel = lst;
    [lp addAction:[UIAction actionWithHandler:^(UIAction *a) {
        if (wlp.on && ![CF(@"messages", @[]) count]) { wlp.on = NO; [ws toast:T(@"أضف رسالة أول", @"Add a message first")]; return; }
        RYMsgLoopSet(wlp.on);
    }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"إرسال كل الرسائل بتكرار", @"Loop all messages"), 15, UIFontWeightBold, nil), lp], 12),
        RYLabel(T(@"يرسل رسائلك وحدة بعد وحدة لين تطفي الزر. يكمّل حتى لو طلعت من التطبيق طالما أنت داخل الروم، ويوقف لحاله لو طلعت من الروم. الغرف ممكن تكتمك لو كثّرت.", @"Sends your messages one after another until switched off. Keeps going when you leave the app as long as you stay in the room; stops if you leave the room. Rooms may mute you for flooding."), 12, UIFontWeightRegular, RY_MUTED), lst])];
    [self.stack addArrangedSubview:RYSlider(T(@"الفاصل بين الرسائل (ثواني)", @"Delay between messages (seconds)"), 2, 15, [CF(@"msgDelay", @4.0) floatValue], ^(float v) { CS(@"msgDelay", @(v)); })];
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        ws.invLabel.text = gMsgLoop ? [NSString stringWithFormat:T(@"شغّال... انرسل %lu", @"Running... sent %lu"), (unsigned long)gMsgSent] : T(@"متوقف", @"Stopped");
        if (!gMsgLoop && wlp.on) wlp.on = NO;
    }];
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

#pragma mark Join link
- (void)joinFrom:(NSString *)str {
    __weak typeof(self) ws = self;
    NSURL *u = RYParseRoomURL(str);
    if (!u) { [self toast:T(@"ما لقيت رابط", @"No link found")]; return; }
    [self toast:T(@"جاري الدخول...", @"Joining...")];
    UIViewController *before = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT));
    RYJoinLink(u, ^(BOOL ok) {
        if (!ok) { UIPasteboard.generalPasteboard.string = gJoinLog ?: @""; [ws toast:T(@"التطبيق ما تعرّف على الرابط (انسخت التفاصيل، الصقها لي)", @"The app didn\u2019t recognise the link (details copied)")]; return; }
        // "accepted" only means the app took the call: the panel stays until a room screen really appears
        __block int tries = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            UIViewController *now = RYFindVC(CF(@"roomClass", RY_ROOM_DEFAULT));
            if (now && now != before) { [t invalidate]; [ws dismissViewControllerAnimated:YES completion:nil]; return; }
            if (++tries >= 16) {
                [t invalidate]; [gJoinLog appendString:@"result: no room screen appeared within 8s\n"];
                UIPasteboard.generalPasteboard.string = gJoinLog ?: @"";
                [ws toast:T(@"التطبيق قبل الرابط بس ما دخل الغرفة (انسخت التفاصيل، الصقها لي)", @"The app accepted the link but no room opened (details copied)")];
            }
        }];
    });
}
- (void)renderJoin {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYLabel(T(@"في النسخة المعدّلة الروابط ما تفتح التطبيق لما تضغط عليها (بسبب التوقيع). انسخ رابط الروم وادخل من هنا.", @"In the modded build tapped links don't open the app (signing drops Universal Links). Copy the room link and join from here."), 13, UIFontWeightRegular, RY_MUTED)];
    UIButton *paste = RYBtn(T(@"لصق من الحافظة ودخول", @"Paste & join"), YES, ^{ [ws joinFrom:UIPasteboard.generalPasteboard.string]; });
    UIButton *type = RYBtn(T(@"كتابة الرابط", @"Type link"), NO, ^{
        [ws ask:T(@"رابط الروم", @"Room link") ph:@"rave.link/..." secure:NO ok:^(NSString *x) { [ws joinFrom:x]; }];
    });
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"دخول روم برابط", @"Join a room by link"), 15, UIFontWeightBold, nil), RYHStack(@[paste, type], 8)])];
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
    for (NSString *k in @[@"lang", @"accent", @"autoOpen", @"bgMode", @"bgValue", @"blur", @"dim", @"messages", @"brand", @"roomClass", @"bx", @"by"]) if (o[k]) CS(k, o[k]);
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
    if (in != self.wasIn) RYLog(in ? @"room: opened" : @"room: CLOSED (app state %ld)", (long)UIApplication.sharedApplication.applicationState);
    self.wasIn = in;
    [self syncBG:room];
    static int brandTick = 0; brandTick++;
    NSString *pat = (brandTick % 5 == 1) ? CF(@"brand", RY_BRAND_TOKENS) : @""; // logo walk only every ~4s: keeps the main thread free
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
    gInvDone = [NSMutableSet new]; gInvIdle = 0; gInvLog = [NSMutableString new]; gInvOK = 0; self.invSent = 0; self.invRunning = YES; self.invStatus = T(@"أبحث عن القائمة…", @"Looking for the list…");
    gInvTimer = [NSTimer scheduledTimerWithTimeInterval:0.9 target:self selector:@selector(invStep) userInfo:nil repeats:YES];
}
- (void)invFinish:(NSString *)why {
    [gInvTimer invalidate]; gInvTimer = nil; self.invRunning = NO; gInvLast = [NSDate date].timeIntervalSince1970;
    self.invStatus = [NSString stringWithFormat:@"%@ %ld (%@ %ld)", why, (long)self.invSent, T(@"مؤكد", @"confirmed"), (long)gInvOK];
    if (gInvOK == 0 && self.invSent > 0 && gInvLog.length) { UIPasteboard.generalPasteboard.string = gInvLog; self.invStatus = [self.invStatus stringByAppendingString:T(@" — ما تأكد أي إرسال، انسخت التفاصيل", @" - none confirmed, details copied")]; }
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
        if (b) { RYActivateCtl(b); self.invSent++; self.invStatus = [NSString stringWithFormat:T(@"آخر واحد: %@", @"Last: %@"), RYClip(key, 24)]; gInvIdle = 0; return; }
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
    // crash-loop guard: if the previous launch died within 10 seconds, this launch skips the risky parts (Anti-AFK, audio hooks)
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL safe = [ud boolForKey:@"layan.launching"];
    [ud setBool:YES forKey:@"layan.launching"]; [ud synchronize];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ud setBool:NO forKey:@"layan.launching"]; [ud synchronize]; });
    RYStartEventLog();
    RYLog(@"mode: %@", safe ? @"SAFE (previous launch crashed)" : @"normal");
    gKeepOn = YES; // Anti-AFK is always on: no switch, not stored, not importable
    if (!safe) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [[RYKeep shared] start]; });
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [[RYKeep shared] start]; }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [[RYCore shared] start]; }];
}
