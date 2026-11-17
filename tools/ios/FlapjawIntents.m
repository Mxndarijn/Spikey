// FlapjawIntents: what the iPhone opened Flapjaw with, handed to the game.
//
//   * a tapped notification's data ({"kind": "battle_alert", "battle": "12"}),
//     at a cold start and when the app comes back to the front
//   * a Universal Link (https://flapjaw.mn-platform.tech/battle/KD7WQ3)
//
// and the other way: the phone's share sheet for an invite (see FJShare).
//
// Godot gives GDScript neither on iOS, so this small file does it, with no
// Godot headers: it registers itself as one of the app delegate's services
// (GDTApplicationDelegate forwards the launch and scene callbacks to every
// service that answers them), and wraps the Firebase plugin's notification
// delegate (GodotxAPNDelegate), which sees a tap but drops its data. What it
// finds goes into Documents/flapjaw_intent.json, Godot's user:// folder on iOS;
// services/app_intents.gd reads that file and deletes it.
//
// Added to the exported Xcode project by .github/ios/fastlane/Fastfile, with
// ARC on (-fobjc-arc).

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const FJFile = @"flapjaw_intent.json";
// The push data keys the game reads (backend/src/push.rs).
static NSArray<NSString *> *FJKeys(void) {
	return @[ @"kind", @"battle" ];
}

static NSString *FJPath(void) {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	return paths.count > 0 ? [paths.firstObject stringByAppendingPathComponent:FJFile] : nil;
}

// Adds `value` under `key` to the file (keeping what is there).
static void FJSave(NSString *key, id value) {
	NSString *path = FJPath();
	if (!path || !value) {
		return;
	}
	NSMutableDictionary *all = [NSMutableDictionary dictionary];
	NSData *old = [NSData dataWithContentsOfFile:path];
	if (old) {
		id parsed = [NSJSONSerialization JSONObjectWithData:old options:0 error:nil];
		if ([parsed isKindOfClass:[NSDictionary class]]) {
			[all addEntriesFromDictionary:parsed];
		}
	}
	all[key] = value;
	NSData *data = [NSJSONSerialization dataWithJSONObject:all options:0 error:nil];
	[data writeToFile:path atomically:YES];
}

static void FJSavePush(NSDictionary *userInfo) {
	NSMutableDictionary *push = [NSMutableDictionary dictionary];
	for (NSString *key in FJKeys()) {
		id v = userInfo[key];
		if (v) {
			push[key] = [NSString stringWithFormat:@"%@", v];
		}
	}
	if (push.count > 0) {
		FJSave(@"push", push);
	}
}

static void FJSaveActivity(NSUserActivity *activity) {
	if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && activity.webpageURL) {
		FJSave(@"link", activity.webpageURL.absoluteString);
	}
}

@interface FlapjawIntents : NSObject
@end

@implementation FlapjawIntents

// A cold start from a tapped notification (no scenes, or before them).
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	NSDictionary *remote = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
	if ([remote isKindOfClass:[NSDictionary class]]) {
		FJSavePush(remote);
	}
	return NO;
}

// A link while the app runs, when the app has no scenes.
- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)activity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))restorationHandler {
	FJSaveActivity(activity);
	return NO;
}

// A cold start with scenes: from a tapped notification, or from a link.
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
	if (options.notificationResponse) {
		FJSavePush(options.notificationResponse.notification.request.content.userInfo);
	}
	for (NSUserActivity *activity in options.userActivities) {
		FJSaveActivity(activity);
	}
}

// A link while the app runs (or wakes).
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)activity API_AVAILABLE(ios(13.0)) {
	FJSaveActivity(activity);
}

@end

// A tap while the app runs or sleeps: the Firebase plugin's delegate gets it;
// keep its data, then let the plugin carry on as before.
static void FJWrapTapHandler(void) {
	Class cls = NSClassFromString(@"GodotxAPNDelegate");
	SEL sel = @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:);
	Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
	if (!method) {
		return;
	}
	typedef void (*Handler)(id, SEL, UNUserNotificationCenter *, UNNotificationResponse *, void (^)(void));
	Handler original = (Handler)method_getImplementation(method);
	IMP wrapped = imp_implementationWithBlock(^(id delegate, UNUserNotificationCenter *center, UNNotificationResponse *response, void (^done)(void)) {
		FJSavePush(response.notification.request.content.userInfo);
		original(delegate, sel, center, response, done);
	});
	method_setImplementation(method, wrapped);
}

// The share sheet: GDScript (services/share_sheet.gd) opens
// flapjaw-share:?text=... with OS.shell_open, which ends in UIApplication's
// openURL; that address shows UIActivityViewController instead.
static NSString *const FJShareScheme = @"flapjaw-share";

static BOOL FJIsShare(NSURL *url) {
	return [url.scheme.lowercaseString isEqualToString:FJShareScheme];
}

static UIViewController *FJTopController(void) {
	UIWindow *window = nil;
	if (@available(iOS 13.0, *)) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:[UIWindowScene class]]) {
				continue;
			}
			for (UIWindow *w in ((UIWindowScene *)scene).windows) {
				if (w.isKeyWindow) {
					window = w;
				}
			}
		}
	}
	if (!window) {
		window = UIApplication.sharedApplication.windows.firstObject;
	}
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController) {
		top = top.presentedViewController;
	}
	return top;
}

static void FJShare(NSURL *url) {
	NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSString *text = nil;
	for (NSURLQueryItem *item in parts.queryItems) {
		if ([item.name isEqualToString:@"text"]) {
			text = item.value;
		}
	}
	if (text.length == 0) {
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *top = FJTopController();
		if (!top) {
			return;
		}
		UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[ text ] applicationActivities:nil];
		// On an iPad the sheet is a popover and needs a place to point at.
		UIPopoverPresentationController *pop = sheet.popoverPresentationController;
		if (pop) {
			pop.sourceView = top.view;
			pop.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMaxY(top.view.bounds), 1, 1);
			pop.permittedArrowDirections = 0;
		}
		[top presentViewController:sheet animated:YES completion:nil];
	});
}

static void FJWrapOpenURL(void) {
	Class cls = [UIApplication class];
	SEL openSel = @selector(openURL:options:completionHandler:);
	Method open = class_getInstanceMethod(cls, openSel);
	if (open) {
		typedef void (*Open)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL));
		Open original = (Open)method_getImplementation(open);
		method_setImplementation(open, imp_implementationWithBlock(^(id app, NSURL *url, NSDictionary *options, void (^done)(BOOL)) {
			if (FJIsShare(url)) {
				FJShare(url);
				if (done) {
					done(YES);
				}
				return;
			}
			original(app, openSel, url, options, done);
		}));
	}
	SEL canSel = @selector(canOpenURL:);
	Method can = class_getInstanceMethod(cls, canSel);
	if (can) {
		typedef BOOL (*Can)(id, SEL, NSURL *);
		Can original = (Can)method_getImplementation(can);
		method_setImplementation(can, imp_implementationWithBlock(^BOOL(id app, NSURL *url) {
			return FJIsShare(url) || original(app, canSel, url);
		}));
	}
}

// After every class's +load (GDTApplicationDelegate makes its service list in its own).
__attribute__((constructor)) static void FJStart(void) {
	static FlapjawIntents *service = nil;
	service = [FlapjawIntents new];
	Class app = NSClassFromString(@"GDTApplicationDelegate");
	SEL add = NSSelectorFromString(@"addService:");
	if (app && [app respondsToSelector:add]) {
		((void (*)(id, SEL, id))objc_msgSend)(app, add, service);
	}
	FJWrapTapHandler();
	FJWrapOpenURL();
}
