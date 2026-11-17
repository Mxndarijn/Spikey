class_name AndroidChannels
extends RefCounted
## The Android notification channels the server sends to (backend/src/push.rs,
## CHANNEL and BATTLE_CHANNEL): one per kind, so a player can mute battles in
## the phone's settings and keep board alerts. Android 8 and up shows a
## notification only on a channel the app made; one for a channel the app
## never made lands in Firebase's "Miscellaneous" fallback instead.
## Made through Godot's JavaClassWrapper on the AndroidRuntime singleton (no
## plugin of our own). Making a channel that exists only updates its name.

const BOARD := "board_alerts"
const BATTLES := "battles"
## NotificationManager.IMPORTANCE_DEFAULT (sound) and IMPORTANCE_HIGH (sound
## and a banner on top of the screen).
const IMPORTANCE_DEFAULT := 3
const IMPORTANCE_HIGH := 4
## Android 8 (API 26) brought channels.
const FIRST_ANDROID := 8
const RUNTIME := "AndroidRuntime"


## [id, name, description, importance] per channel, as the player sees them in
## Settings > Apps > Flapjaw > Notifications.
static func channels() -> Array:
	return [
		[
			BOARD,
			"Board alerts",
			"Someone pushed you out of a prize spot on today's board",
			IMPORTANCE_DEFAULT,
		],
		[BATTLES, "Battles", "Your turn, nudges and results in your battles", IMPORTANCE_HIGH],
	]


## True on Android 8 and up ("8.1.0" -> 8), where channels exist.
static func has_channels(os_name: String, version: String) -> bool:
	return os_name == "Android" and version.get_slice(".", 0).to_int() >= FIRST_ANDROID


## Makes every channel on this phone. Returns how many were made (0 off
## Android, before Android 8, or when the Java side isn't there).
static func create() -> int:
	if not has_channels(OS.get_name(), OS.get_version()):
		return 0
	if not Engine.has_singleton(RUNTIME):
		return 0
	var runtime: Object = Engine.get_singleton(RUNTIME)
	var context: Object = runtime.call(&"getApplicationContext")
	if context == null:
		return 0
	var manager: Object = context.call(&"getSystemService", "notification")
	var channel_class: Object = JavaClassWrapper.wrap("android.app.NotificationChannel")
	if manager == null or channel_class == null:
		return 0
	var made := 0
	for c: Array in channels():
		var channel: Object = channel_class.call(&"NotificationChannel", c[0], c[1], c[3])
		if channel == null:
			continue
		channel.call(&"setDescription", c[2])
		manager.call(&"createNotificationChannel", channel)
		made += 1
	return made
