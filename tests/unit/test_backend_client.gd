extends TestCase
## The backend interface (BackendClient): which backend the config picks, and
## our own server's client (FlapjawClient) without a network: how it signs in
## (refresh token, then device key, a new player only when both are refused),
## "please update", and letting go of a player who moved to another phone.

const CONFIG := "user://test_backend_config.json"
const OLD_CONFIG := "user://test_backend_old_supabase.json"
const SESSION := "user://test_flapjaw_session.json"
const DEVICE := "user://test_flapjaw_device.json"


## A FlapjawClient whose server is a script: each path answers from `answers`
## (a list per path, used in order; the last one repeats).
class ScriptedClient:
	extends FlapjawClient
	var answers := {}
	var sent: Array = []

	func _init() -> void:
		super(null, "https://api.example.com/")

	func post(path: String, body: Dictionary, signed_in: bool) -> Dictionary:
		sent.append([path, body, signed_in])
		var list: Array = answers.get(path, [])
		if list.is_empty():
			return {"ok": false, "code": 0, "data": null}
		var res: Dictionary = list[0] if list.size() == 1 else list.pop_front()
		note_answer(res)
		return res.duplicate(true)

	func paths() -> Array:
		return sent.map(func(s: Array) -> String: return s[0])


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean() -> void:
	for path in [CONFIG, OLD_CONFIG, SESSION, DEVICE]:
		SafeFile.remove(path)


func _client() -> ScriptedClient:
	var c := ScriptedClient.new()
	c.session_path = SESSION
	c.device_path = DEVICE
	c.keychain = null
	return c


static func _session(player: String, access: String = "acc") -> Dictionary:
	return {
		"ok": true,
		"code": 200,
		"data":
		{
			"player_id": player,
			"access_token": access,
			"refresh_token": "ref-" + player,
			"expires_in": 3600,
		},
	}


static func _no(code: int, error: String = "") -> Dictionary:
	return {"ok": false, "code": code, "data": {"error": error} if error != "" else null}


func test_the_config_picks_the_backend() -> void:
	_clean()
	assert_eq(BackendClient.load_backend_config(CONFIG, OLD_CONFIG), {}, "no file: sample boards")
	_write(OLD_CONFIG, '{"url": "https://abc.supabase.co", "anon_key": "k"}')
	assert_eq(
		BackendClient.load_backend_config(CONFIG, OLD_CONFIG),
		{"url": "https://abc.supabase.co", "anon_key": "k", "kind": "supabase"},
		"the older Supabase file still works"
	)
	_write(CONFIG, '{"kind": "flapjaw", "url": "https://api.flapjaw.example/", "server_id": "s1"}')
	assert_eq(
		BackendClient.load_backend_config(CONFIG, OLD_CONFIG),
		{"kind": "flapjaw", "url": "https://api.flapjaw.example", "server_id": "s1"},
		"the new file wins"
	)
	_write(CONFIG, '{"kind": "flapjaw", "url": "https://<API_HOST>", "server_id": "s1"}')
	assert_eq(BackendClient.load_backend_config(CONFIG, OLD_CONFIG), {}, "a placeholder host")
	_write(CONFIG, '{"kind": "flapjaw", "url": "https://api.flapjaw.example"}')
	assert_eq(BackendClient.load_backend_config(CONFIG, OLD_CONFIG), {}, "a server id is needed")
	_write(CONFIG, '{"kind": "other", "url": "https://api.flapjaw.example", "server_id": "s"}')
	assert_eq(BackendClient.load_backend_config(CONFIG, OLD_CONFIG), {}, "an unknown kind")
	_write(CONFIG, '{"kind": "flapjaw", "url": "http://127.0.0.1:8080", "server_id": "local"}')
	assert_eq(
		BackendClient.load_backend_config(CONFIG, "").url,
		"http://127.0.0.1:8080",
		"plain http for a server on this PC"
	)
	_clean()


func test_make_builds_the_kind_asked_for() -> void:
	assert_true(BackendClient.make(null, {}) == null)
	var s := BackendClient.make(null, {"kind": "supabase", "url": "https://a.co", "anon_key": "k"})
	assert_true(s is SupabaseClient)
	assert_eq(s.kind(), BackendClient.KIND_SUPABASE)
	var f := BackendClient.make(null, {"kind": "flapjaw", "url": "https://a.co", "server_id": "x"})
	assert_true(f is FlapjawClient)
	assert_eq(f.kind(), BackendClient.KIND_FLAPJAW)


func test_the_example_config_is_not_a_real_one() -> void:
	var text := FileAccess.get_file_as_string("res://services/backend_config.example.json")
	var d: Variant = JSON.parse_string(text)
	assert_true(d is Dictionary)
	assert_eq(str(d.kind), BackendClient.KIND_FLAPJAW)
	assert_eq(BackendClient.config_of(d), {}, "the example's placeholders count as missing")


func test_a_new_phone_signs_up_once_with_its_key() -> void:
	_clean()
	var c := _client()
	c.answers = {"/v1/auth/anon": [_session("p1")]}
	c.restore()
	assert_true(await c.ensure_session())
	assert_eq(c.paths(), ["/v1/auth/anon"], "nothing to refresh: straight to a new player")
	var key := str(c.sent[0][1].device_key)
	assert_true(BackendClient.is_device_key(key))
	assert_eq(c.player_id(), "p1")
	assert_eq(SafeFile.read_json(DEVICE), {"key": key, "player": "p1"}, "the key is kept")
	assert_eq(SafeFile.read_json(SESSION).refresh_token, "ref-p1")
	assert_true(await c.ensure_session(), "a valid token needs no request")
	assert_eq(c.sent.size(), 1)
	_clean()


func test_a_lost_sign_up_answer_sends_the_same_key_again() -> void:
	_clean()
	var c := _client()
	c.answers = {"/v1/auth/anon": [{"ok": false, "code": 0, "data": null}, _session("p1")]}
	c.restore()
	assert_false(await c.ensure_session(), "no answer")
	assert_true(await c.ensure_session())
	assert_eq(c.sent[0][1].device_key, c.sent[1][1].device_key)
	_clean()


func test_refresh_then_device_key_then_a_new_player() -> void:
	_clean()
	var key := BackendClient.new_device_key()
	SafeFile.write_json(SESSION, {"access_token": "a", "refresh_token": "r", "expires_at": 1})
	SafeFile.write_json(DEVICE, {"key": key, "player": "p1"})
	var c := _client()
	c.answers = {
		"/v1/auth/refresh": [_no(401, "session_gone")],
		"/v1/auth/device": [_session("p1", "acc2")],
	}
	c.restore()
	assert_true(await c.ensure_session())
	assert_eq(c.paths(), ["/v1/auth/refresh", "/v1/auth/device"])
	assert_eq(c.sent[1][1], {"player_id": "p1", "device_key": key})
	assert_eq(c.player_id(), "p1", "the same player after a restored backup")
	# Both refused: only now a new player, with a new key.
	SafeFile.write_json(SESSION, {"access_token": "a", "refresh_token": "r", "expires_at": 1})
	c = _client()
	c.answers = {
		"/v1/auth/refresh": [_no(401, "session_gone")],
		"/v1/auth/device": [_no(401, "unknown_key")],
		"/v1/auth/anon": [_session("p2")],
	}
	c.restore()
	assert_true(await c.ensure_session())
	assert_eq(c.paths(), ["/v1/auth/refresh", "/v1/auth/device", "/v1/auth/anon"])
	assert_ne(str(c.sent[2][1].device_key), key, "a new player gets a new key")
	assert_eq(c.player_id(), "p2")
	_clean()


func test_no_answer_never_makes_a_new_player() -> void:
	_clean()
	SafeFile.write_json(SESSION, {"access_token": "a", "refresh_token": "r", "expires_at": 1})
	SafeFile.write_json(DEVICE, {"key": BackendClient.new_device_key(), "player": "p1"})
	var c := _client()
	c.answers = {"/v1/auth/refresh": [{"ok": false, "code": 0, "data": null}]}
	c.restore()
	assert_false(await c.ensure_session())
	assert_eq(c.paths(), ["/v1/auth/refresh"], "offline: nothing else is tried")
	c = _client()
	c.answers = {"/v1/auth/refresh": [_no(503)]}
	c.restore()
	assert_false(await c.ensure_session(), "server busy")
	assert_eq(SafeFile.read_json(SESSION).refresh_token, "r", "the session is kept")
	_clean()


func test_a_moved_player_is_let_go() -> void:
	_clean()
	SafeFile.write_json(SESSION, {"access_token": "a", "refresh_token": "r", "expires_at": 1})
	SafeFile.write_json(DEVICE, {"key": BackendClient.new_device_key(), "player": "p1"})
	var c := _client()
	var moved := [0]
	c.account_moved.connect(func() -> void: moved[0] += 1)
	c.answers = {
		"/v1/auth/refresh": [_no(401, FlapjawClient.MOVED)],
		"/v1/auth/anon": [_session("p9")],
	}
	c.restore()
	assert_true(await c.ensure_session())
	assert_eq(moved[0], 1, "the game is told")
	assert_eq(c.paths(), ["/v1/auth/refresh", "/v1/auth/anon"], "the old key is not tried")
	assert_eq(c.player_id(), "p9", "a new player here")
	_clean()


func test_a_call_after_the_move_lets_go_too() -> void:
	_clean()
	var c := _client()
	var moved := [0]
	c.account_moved.connect(func() -> void: moved[0] += 1)
	c.answers = {
		"/v1/auth/anon": [_session("p1")],
		"/v1/get_wallet": [_no(401, FlapjawClient.MOVED)],
	}
	c.restore()
	var res := await c.call_db("get_wallet", {})
	assert_false(res.ok)
	assert_eq(moved[0], 1)
	assert_eq(c.player_id(), "")
	assert_eq(SafeFile.read_json(DEVICE), {}, "the key is gone")
	_clean()


func test_a_refused_token_signs_in_again_once() -> void:
	_clean()
	var c := _client()
	c.answers = {
		"/v1/auth/anon": [_session("p1")],
		"/v1/auth/refresh": [_session("p1", "acc2")],
		"/v1/get_board": [_no(401, "token_expired"), {"ok": true, "code": 200, "data": {}}],
	}
	c.restore()
	var res := await c.call_db("get_board", {"p_board": "daily"})
	assert_true(res.ok)
	assert_eq(c.paths(), ["/v1/auth/anon", "/v1/get_board", "/v1/auth/refresh", "/v1/get_board"])
	_clean()


func test_too_old_an_app_asks_once_to_update() -> void:
	_clean()
	var c := _client()
	var asked := [0]
	c.update_required.connect(func() -> void: asked[0] += 1)
	c.answers = {
		"/v1/auth/anon": [_session("p1")],
		"/v1/get_board": [{"ok": false, "code": 426, "data": {"error": "update_required"}}],
	}
	c.restore()
	await c.call_db("get_board", {})
	await c.call_db("get_board", {})
	assert_true(c.update_needed)
	assert_eq(asked[0], 1, "once per launch")
	_clean()


func test_a_transfer_makes_this_phone_that_player() -> void:
	_clean()
	var c := _client()
	c.answers = {
		"/v1/auth/anon": [_session("new")],
		"/v1/transfer/redeem": [_session("old-player", "acc-moved")],
	}
	c.restore()
	var res := await c.redeem_transfer("K7QF3MZDPX9W")
	assert_true(res.ok)
	var sent: Dictionary = c.sent[1][1]
	assert_eq(sent.code, "K7QF3MZDPX9W")
	assert_true(BackendClient.is_device_key(str(sent.device_key)), "a new key goes along")
	assert_eq(c.player_id(), "old-player")
	assert_eq(SafeFile.read_json(DEVICE).key, sent.device_key)
	assert_true(c.sent[1][2], "signed in as this phone's player")
	_clean()


func test_requests_say_which_app_is_asking() -> void:
	var c := _client()
	var h := c._headers(false)
	assert_true("X-Flapjaw-Api: %d" % BackendClient.API_VERSION in h)
	assert_true("X-Flapjaw-Gameplay: %d" % SimConfig.GAMEPLAY_VERSION in h)
	assert_false(Array(h).any(func(x: String) -> bool: return x.begins_with("Authorization")))


func test_the_keychain_keeps_the_key_through_a_reinstall() -> void:
	_clean()
	var store := {}
	var kc := FakeKeychain.new(store)
	var key := BackendClient.new_device_key()
	kc.write(FlapjawClient.KEYCHAIN_ITEM, JSON.stringify({"key": key, "player": "p1"}))
	var c := _client()
	c.keychain = kc
	c.restore()
	assert_true(c.has_device_login(), "the file was gone; the Keychain had the key")
	assert_eq(SafeFile.read_json(DEVICE), {"key": key, "player": "p1"}, "and the file is back")
	_clean()


class FakeKeychain:
	extends RefCounted
	var _store: Dictionary

	func _init(s: Dictionary) -> void:
		_store = s

	func read(name: String) -> String:
		return str(_store.get(name, ""))

	func write(name: String, value: String) -> bool:
		_store[name] = value
		return true
