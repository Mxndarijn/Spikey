class_name FirebasePush
extends PushService
## Push through Firebase Cloud Messaging: asks the phone for permission and
## hands its token to the server. Uses the Godotx Firebase plugin
## (addons/godotx_firebase, core + messaging), which only exists in phone
## builds: check is_supported() before making one.
## Firebase Core starts first; a permission prompt or token asked for before
## it is ready waits until it is.
## Android: the notification channels are made at start (AndroidChannels), and
## a token needs no permission, so every start fetches one. iOS: every start
## goes through request_permission, which after the first answer shows no
## prompt but registers the app with Apple's push service again; without that
## Firebase has no APNs token and hands out no FCM token.

const CORE := "GodotxFirebaseCore"
const MESSAGING := "GodotxFirebaseMessaging"

## "Android" or "iOS" (OS.get_name(); tests set it).
var os_name := OS.get_name()

var _core: Object
var _messaging: Object
var _started := false
## Asked for before Firebase was ready.
var _want_permission := false
var _want_token := false


## True in a build that carries the plugin (Android with the Gradle build).
static func is_supported() -> bool:
	return Engine.has_singleton(CORE) and Engine.has_singleton(MESSAGING)


func _init(api: BackendClient = null) -> void:
	super(api)
	if not is_supported():
		return
	_core = Engine.get_singleton(CORE)
	_messaging = Engine.get_singleton(MESSAGING)
	AndroidChannels.create()
	_core.connect(&"core_initialized", _on_core_initialized)
	_messaging.connect(&"messaging_permission_granted", _on_permission_granted)
	_messaging.connect(&"messaging_token_received", _on_token)
	_messaging.connect(&"messaging_error", _on_error)
	_core.call(&"initialize")


func is_available() -> bool:
	return _messaging != null


## The OS prompt (Android 13 and up, iOS); the token follows a yes.
func request_permission() -> void:
	if _messaging == null:
		return
	if not _started:
		_want_permission = true
		return
	_messaging.call(&"request_permission")


## This start's token, without a prompt (on iOS only once the player answered
## the prompt before: BoardAlerts calls this then).
func start() -> void:
	if _messaging == null:
		return
	if not _started:
		_want_token = true
		return
	if os_name == "iOS":
		_messaging.call(&"request_permission")
	else:
		_messaging.call(&"get_token")


## Android hands out a token without asking.
func fetches_silently() -> bool:
	return _messaging != null and os_name != "iOS"


## "android" or "ios", as the server stores it.
func platform() -> String:
	return IOS if os_name == "iOS" else ANDROID


func _on_core_initialized(success: bool) -> void:
	if not success or _started:
		return
	_started = true
	_messaging.call(&"initialize")
	if _want_permission:
		_want_permission = false
		request_permission()
	elif _want_token:
		start()
	_want_token = false


func _on_permission_granted() -> void:
	_messaging.call(&"get_token")


func _on_token(token: String) -> void:
	# On iOS a get_token right after the prompt can fail before Apple's token is
	# in; the token then still arrives here.
	last_error = ""
	accept_token(token, platform())


func _on_error(message: String) -> void:
	# Not push_error: a phone without Google Play services is no bug.
	last_error = message
	print("Board alerts: ", message)
