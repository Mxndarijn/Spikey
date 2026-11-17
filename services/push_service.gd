class_name PushService
extends RefCounted
## Push notifications, as the game sees them: "Board alerts" when another
## player's run pushes you past a prize line on the daily board, and battle
## alerts (your turn, nudges, results). The server decides and sends
## (backend/migrations/20261110110000_push_alerts.sql, backend/src/push.rs);
## the phone only has to hand over its push token and say whether alerts are on.
## A registration the server didn't take (no network at start, a new player
## after a transfer) is sent again at the next sign-in or app resume.
## This base class has no push: nothing is asked and no token ever arrives
## (PC builds, tests, and phones until the native plugin is in). A subclass
## per platform plugin asks the OS and calls accept_token().

## The OS handed over this phone's push token.
signal token_received(token: String, platform: String)

const ANDROID := "android"
const IOS := "ios"
## send_test(): what the server answered, in words.
const TEST_ANSWERS := {
	"queued": "Sent. Leave the app now to see it arrive",
	"no_device": "This phone is not registered (no token on the server)",
	"off": "Board alerts are switched off",
	"too_soon": "Wait half a minute between tests",
	"no_sender": "The server has no sender set up",
	"no_player": "Play one run first (no player on the server yet)",
}

## The last thing that went wrong, for the debug screen.
var last_error := ""

var _api: BackendClient
var _token := ""
var _platform := ""
## The server took this phone's token (for the player signed in now).
var _registered := false
var _registering := false


## api: the server session to register with, or null (no server).
func _init(api: BackendClient = null) -> void:
	_api = api
	if api != null:
		api.session_checked.connect(_on_session_checked)
		api.account_moved.connect(_on_account_moved)


## True when this build can receive push notifications.
func is_available() -> bool:
	return false


## Shows the OS permission prompt; the token follows when the player allows.
func request_permission() -> void:
	pass


## Fetches the token when permission was given earlier (every app start:
## tokens change).
func start() -> void:
	pass


## True when start() can fetch a token before the player was ever asked,
## without showing a prompt (Android: a token needs no permission).
func fetches_silently() -> bool:
	return false


## A platform plugin got a token: remember it and register it on the server.
func accept_token(token: String, platform: String) -> void:
	if token.is_empty():
		return
	if token != _token or platform != _platform:
		_registered = false
	_token = token
	_platform = platform
	token_received.emit(token, platform)
	if not _registered:
		register()


func token() -> String:
	return _token


## Sends this phone's token and clock to the server (also after a setting
## change, so the offset stays right through summer and winter time).
func register() -> void:
	if _api == null or _token.is_empty() or _registering:
		return
	_registering = true
	var token := _token
	var res := await _api.call_db(
		"register_push", register_body(token, _platform, utc_offset_minutes())
	)
	_registering = false
	var ok := bool(res.get("ok", false))
	_registered = ok and token == _token
	if not ok:
		last_error = "register_push failed (%d)" % int(res.get("code", 0))
	elif token != _token:
		# A newer token arrived while this one was on its way.
		register()


## True when the server holds this phone's current token.
func is_registered() -> bool:
	return _registered


## The app came back (or signed in again): send a registration the server
## didn't take yet.
func retry_register() -> void:
	if not _registered:
		register()


func _on_session_checked(ok: bool) -> void:
	if ok:
		retry_register()


## The player moved to another phone: the next player here registers anew.
func _on_account_moved() -> void:
	_registered = false


## Settings > Board alerts.
func set_enabled(on: bool) -> void:
	if _api == null:
		return
	await _api.call_db("set_push_enabled", {"p_enabled": on})


## The debug screen: asks the server to send this phone one test notification
## (send_test_push in backend/migrations/). Returns what happened, in words.
func send_test() -> String:
	if _api == null:
		return "No server in this build"
	var res := await _api.call_db("send_test_push", {})
	if not bool(res.get("ok", false)):
		return "The server did not answer (%d)" % int(res.get("code", 0))
	var answer := str(res.get("data", ""))
	return str(TEST_ANSWERS.get(answer, answer))


## The debug screen: what this service knows right now, as [name, value] rows.
func debug_rows() -> Array:
	var rows := [
		["Push", "in this build" if is_available() else "not in this build"],
		["Server", "set up" if _api != null else "none"],
		["Token", short_token(_token)],
		["On the server", "yes" if _registered else "not yet"],
		["Clock", "UTC %+d min" % utc_offset_minutes()],
	]
	if not last_error.is_empty():
		rows.append(["Last error", last_error])
	return rows


## A token as the debug screen shows it: its ends and its length, never all of it.
static func short_token(value: String) -> String:
	if value.is_empty():
		return "none yet"
	if value.length() <= 12:
		return "%d characters" % value.length()
	return "%s...%s (%d characters)" % [value.left(6), value.right(4), value.length()]


## The arguments of register_push in backend/migrations/.
static func register_body(token: String, platform: String, utc_offset_min: int) -> Dictionary:
	return {
		"p_token": token,
		"p_platform": platform,
		"p_utc_offset_min": clampi(utc_offset_min, -720, 840),
	}


## Minutes this phone's clock is ahead of UTC (60 in Amsterdam in winter): the
## server keeps alerts away between 22:00 and 08:00 on this clock.
static func utc_offset_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))
