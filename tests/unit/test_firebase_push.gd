extends TestCase
## FirebasePush against stand-ins for the plugin's two singletons: the order
## Firebase needs (core first), the permission prompt and the token.


class FakeCore:
	extends Object
	signal core_initialized(success: bool)
	var inits := 0

	func initialize() -> void:
		inits += 1


class FakeMessaging:
	extends Object
	signal messaging_permission_granted
	signal messaging_permission_denied
	signal messaging_token_received(token: String)
	signal messaging_error(message: String)
	var calls: Array[String] = []

	func initialize() -> void:
		calls.append("initialize")

	func request_permission() -> void:
		calls.append("request_permission")

	func get_token() -> void:
		calls.append("get_token")


var _core: FakeCore
var _messaging: FakeMessaging


func _plug_in() -> void:
	_core = FakeCore.new()
	_messaging = FakeMessaging.new()
	Engine.register_singleton(FirebasePush.CORE, _core)
	Engine.register_singleton(FirebasePush.MESSAGING, _messaging)


func _unplug() -> void:
	Engine.unregister_singleton(FirebasePush.CORE)
	Engine.unregister_singleton(FirebasePush.MESSAGING)
	_core.free()
	_messaging.free()


func test_no_plugin_no_push() -> void:
	assert_false(FirebasePush.is_supported(), "this PC has no Firebase plugin")
	var push := FirebasePush.new()
	assert_false(push.is_available())
	push.request_permission()
	push.start()
	assert_eq(push.token(), "", "nothing happens, nothing breaks")


func test_core_starts_first_then_the_prompt_then_the_token() -> void:
	_plug_in()
	assert_true(FirebasePush.is_supported())
	var push := FirebasePush.new()
	assert_true(push.is_available())
	assert_eq(_core.inits, 1, "Firebase Core is started at once")
	push.request_permission()
	assert_eq(_messaging.calls, [] as Array[String], "the prompt waits for Core")
	_core.core_initialized.emit(true)
	assert_eq(
		_messaging.calls,
		["initialize", "request_permission"] as Array[String],
		"messaging starts, then the waiting prompt shows"
	)
	_messaging.messaging_permission_granted.emit()
	assert_eq(_messaging.calls.back(), "get_token", "a yes asks for the token")
	var got: Array = []
	push.token_received.connect(func(t: String, p: String) -> void: got.append([t, p]))
	_messaging.messaging_token_received.emit("fcm-token-abc")
	assert_eq(got, [["fcm-token-abc", "android"]], "the token reaches the game")
	assert_eq(push.token(), "fcm-token-abc")
	_messaging.messaging_token_received.emit("fcm-token-new")
	assert_eq(push.token(), "fcm-token-new", "a refreshed token replaces the old one")
	push = null
	_unplug()


func test_a_later_start_fetches_the_token_without_a_prompt() -> void:
	_plug_in()
	var push := FirebasePush.new()
	push.start()
	_core.core_initialized.emit(true)
	assert_eq(_messaging.calls, ["initialize", "get_token"] as Array[String], "no prompt")
	push.start()
	assert_eq(_messaging.calls.back(), "get_token", "ready: asked right away")
	push.request_permission()
	assert_eq(_messaging.calls.back(), "request_permission")
	_core.core_initialized.emit(true)
	assert_eq(_messaging.calls.count("initialize"), 1, "messaging starts once")
	push = null
	_unplug()


func test_a_failed_core_or_a_refusal_leaves_the_game_alone() -> void:
	_plug_in()
	var push := FirebasePush.new()
	push.request_permission()
	_core.core_initialized.emit(false)
	assert_eq(_messaging.calls, [] as Array[String], "no Firebase: nothing is asked")
	_core.core_initialized.emit(true)
	_messaging.messaging_permission_denied.emit()
	_messaging.messaging_error.emit("no Google Play services")
	assert_eq(push.token(), "", "a no or an error registers nothing")
	push = null
	_unplug()


func test_main_uses_firebase_only_where_the_plugin_is() -> void:
	var path := "user://test_firebase_push_profile.json"
	DirAccess.remove_absolute(path)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = path
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	assert_false(main.push is FirebasePush, "a PC build has the plain service")
	assert_false(main.push.is_available())
	main.free()
	DirAccess.remove_absolute(path)
