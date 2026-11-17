extends TestCase
## The phone's push token reaching the server: register_push goes out signed
## in (the client signs in first), and a registration the server didn't take
## is sent again at the next sign-in, after a transfer, and on app resume.

const SESSION := "user://test_push_registration_session.json"
const DEVICE := "user://test_push_registration_device.json"


## Our server as canned answers per path; remembers each path in order, and
## whether it went out signed in.
class FakeServer:
	extends FlapjawClient
	var posts: Array[String] = []
	var down := false

	func _init() -> void:
		super(null, "https://api.example.com")
		session_path = SESSION
		device_path = DEVICE

	func post(path: String, _body: Dictionary, signed_in: bool) -> Dictionary:
		posts.append(path + (" signed in" if signed_in and not _access.is_empty() else ""))
		if down:
			return {"ok": false, "code": 0, "data": null}
		if path == "/v1/auth/anon":
			return {
				"ok": true,
				"code": 200,
				"data":
				{
					"player_id": "p1",
					"access_token": "acc",
					"refresh_token": "ref",
					"expires_in": 3600,
				},
			}
		return {"ok": true, "code": 200, "data": null}


func _clean() -> void:
	SafeFile.remove(SESSION)
	SafeFile.remove(DEVICE)


func test_the_token_is_registered_after_signing_in() -> void:
	_clean()
	var server := FakeServer.new()
	var push := PushService.new(server)
	push.accept_token("fcm-token-abcdef", PushService.ANDROID)
	assert_eq(
		server.posts,
		["/v1/auth/anon", "/v1/register_push signed in"] as Array[String],
		"a new phone signs in first, then registers as that player"
	)
	assert_true(push.is_registered())
	push.accept_token("fcm-token-abcdef", PushService.ANDROID)
	assert_eq(server.posts.size(), 2, "the same token again: nothing to send")
	push.accept_token("fcm-token-newer1", PushService.ANDROID)
	assert_eq(server.posts.back(), "/v1/register_push signed in", "a new token is sent")
	_clean()


func test_a_lost_registration_is_sent_again() -> void:
	_clean()
	var server := FakeServer.new()
	server.down = true
	var push := PushService.new(server)
	push.accept_token("fcm-token-abcdef", PushService.IOS)
	assert_false(push.is_registered(), "no network at start")
	assert_false(push.last_error.is_empty(), "the debug screen says so")
	server.down = false
	server.posts.clear()
	push.retry_register()
	assert_true(push.is_registered(), "the app came back: registered now")
	assert_eq(server.posts.back(), "/v1/register_push signed in")
	server.posts.clear()
	push.retry_register()
	assert_eq(server.posts, [] as Array[String], "registered: nothing more to send")
	_clean()


func test_a_sign_in_or_a_transfer_registers_again() -> void:
	_clean()
	var server := FakeServer.new()
	server.down = true
	var push := PushService.new(server)
	push.accept_token("fcm-token-abcdef", PushService.ANDROID)
	server.down = false
	server.session_checked.emit(true)
	assert_true(push.is_registered(), "the next sign-in sends it")
	server.account_moved.emit()
	assert_false(push.is_registered(), "a new player here has no token on the server")
	server.posts.clear()
	server.session_checked.emit(true)
	assert_eq(server.posts.back(), "/v1/register_push signed in", "the new player registers")
	assert_true(push.is_registered())
	_clean()


func test_no_server_no_registration() -> void:
	var push := PushService.new()
	push.accept_token("fcm-token-abcdef", PushService.ANDROID)
	push.retry_register()
	assert_false(push.is_registered())
	assert_eq(push.token(), "fcm-token-abcdef")
