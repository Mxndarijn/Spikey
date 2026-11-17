// FlapjawIntents: what the iPhone opened Flapjaw with, handed to the game.
//
//   * a tapped notification's data ({"kind": "battle_alert", "battle": "12"}),
//     at a cold start and when the app comes back to the front
//   * a Universal Link (https://flapjaw.mn-platform.tech/battle/KD7WQ3)
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
}
