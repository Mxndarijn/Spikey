class_name SupabaseClient
extends RefCounted
## This phone's connection to the Supabase project (supabase/migrations/, setup
## in docs/LEADERBOARD_SETUP.md): the anonymous player's session and calls to
## the database's functions. The leaderboards, the wallet and push alerts all
## go through one client, so a phone is one player everywhere.
## The session is kept in user:// through SafeFile (a crash mid-save keeps the
## last good one). A new anonymous player is made only when there is no
## session at all or the server says this one is gone for good, never because
## of a network hiccup: a new player starts with no diamonds.
## The device key: each player also gets a long random key that never changes
## (supabase/functions/device-key). The refresh token changes every hour, so a
## phone backup (Android Auto Backup restores user:// after a reinstall or on
## a new phone) holds a dead one; with the key from the same backup the phone
## signs in as the same player again.

## A sign-in or token refresh finished (ok: there is a valid session now).
signal session_checked(ok: bool)

const CONFIG_PATH := "res://services/supabase_config.json"
const SESSION_PATH := "user://supabase_session.json"
const DEVICE_PATH := "user://device_key.json"
## The Edge Function that turns the device key into a sign-in.
const DEVICE_FUNCTION := "/functions/v1/device-key"
const TIMEOUT_S := 10.0
## Refresh the access token this long before it runs out.
const REFRESH_MARGIN_S := 60
## Auth error codes that mean the saved session can never work again; anything
## else (a refresh token used twice in a race, the server busy, no internet)
## keeps the session to try again later.
const SESSION_GONE: Array[String] = [
	"refresh_token_not_found", "session_not_found", "session_expired", "user_not_found"
]

## Tests point this somewhere else.
var session_path := SESSION_PATH
var device_path := DEVICE_PATH

var _url := ""
var _key := ""
var _host: Node
var _access := ""
var _refresh := ""
var _expires_at := 0
var _signing_in := false
## The device key and the address it signs in with ("" until the server took
## the key).
var _device_key := ""
var _device_email := ""
var _enrolling := false


## url: "https://<project>.supabase.co"; key: the project's public anon key.
## host: a node in the tree to hang the HTTP requests on.
func _init(host: Node, url: String, key: String) -> void:
	_host = host
	_url = url.trim_suffix("/")
	_key = key


## {"url": ..., "anon_key": ...} from the config file, or {} when it is missing
## or incomplete (the game then plays offline with sample boards).
static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = parse(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {}
	var url := str((data as Dictionary).get("url", ""))
	var key := str((data as Dictionary).get("anon_key", ""))
	# The example file's placeholders ("YOUR-...", "PASTE-...") count as missing.
	if not url.begins_with("https://") or key.is_empty() or _placeholder(url + key):
		return {}
	return {"url": url, "anon_key": key}


static func _placeholder(text: String) -> bool:
	return "YOUR-" in text or "PASTE-" in text


## Loads the saved session.
func restore() -> void:
	var s: Variant = SafeFile.read_json(session_path)
	var d: Dictionary = s if s is Dictionary else {}
	_access = str(d.get("access_token", ""))
	_refresh = str(d.get("refresh_token", ""))
	_expires_at = int(d.get("expires_at", 0))
	var k: Variant = SafeFile.read_json(device_path)
	var dk: Dictionary = k if k is Dictionary else {}
	_device_key = str(dk.get("key", ""))
	_device_email = str(dk.get("email", "")) if is_device_key(_device_key) else ""
	if not is_device_key(_device_key):
		_device_key = ""


## A valid access token: the saved one, a refreshed one, or a new anonymous
## player when there is no session. Calls that arrive while signing in wait
## for it, so a phone never makes two players.
func ensure_session() -> bool:
	var now := int(Time.get_unix_time_from_system())
	if not _access.is_empty() and now < _expires_at - REFRESH_MARGIN_S:
		return true
	if _signing_in:
		return await session_checked
	_signing_in = true
	var ok := await _renew_session(now)
	_signing_in = false
	session_checked.emit(ok)
	return ok


## Refresh token first; when the server refuses it, the device key; only when
## neither can work, a new player. No answer at all (offline, server busy)
## keeps everything to try again later.
func _renew_session(now: int) -> bool:
	var res := {"ok": false, "code": 0, "data": null}
	var can_sign_up := _refresh.is_empty()
	if not _refresh.is_empty():
		res = await post(
			"/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh}, false
		)
		can_sign_up = not res.ok and session_gone(res)
		if not res.ok and not refused(res):
			return false
	if not res.ok and has_device_login():
		res = await post(
			"/auth/v1/token?grant_type=password",
			{"email": _device_email, "password": _device_key},
			false
		)
		if not res.ok and not refused(res):
			return false
		# The key is wrong or its player gone: this phone can only start over.
		can_sign_up = not res.ok and not _rate_limited(res)
	var new_player := false
	if not res.ok:
		if not can_sign_up:
			return false
		res = await post("/auth/v1/signup", {}, false)
		new_player = true
	if not res.ok or not res.data is Dictionary:
		return false
	var d := res.data as Dictionary
	_access = str(d.get("access_token", ""))
	_refresh = str(d.get("refresh_token", ""))
	_expires_at = now + int(d.get("expires_in", 3600))
	SafeFile.write_json(
		session_path,
		{"access_token": _access, "refresh_token": _refresh, "expires_at": _expires_at}
	)
	if new_player:
		# A new player gets a new key; the old one belonged to the old player.
		_device_key = ""
		_device_email = ""
	if not _access.is_empty() and _device_email.is_empty():
		_enroll_device()
	return not _access.is_empty()


## Whether a saved device key can sign in (the server took it).
func has_device_login() -> bool:
	return not _device_key.is_empty() and not _device_email.is_empty()


## Hands this player's device key to the server (once; again after a failure,
## at the next sign-in). The key is saved before it is sent, so a lost answer
## sends the same key again.
func _enroll_device() -> void:
	if _enrolling:
		return
	_enrolling = true
	if _device_key.is_empty():
		_device_key = new_device_key()
		_save_device()
	var res := await post(DEVICE_FUNCTION, {"key": _device_key}, true)
	if res.ok and res.data is Dictionary:
		var email := str((res.data as Dictionary).get("email", ""))
		if not email.is_empty():
			_device_email = email
			_save_device()
	_enrolling = false


func _save_device() -> void:
	SafeFile.write_json(device_path, {"key": _device_key, "email": _device_email})


## "Fj-" and 64 hex characters from 32 random bytes (the function's KEY).
static func new_device_key() -> String:
	return "Fj-" + Crypto.new().generate_random_bytes(32).hex_encode()


static func is_device_key(key: String) -> bool:
	if key.length() != 67 or not key.begins_with("Fj-"):
		return false
	for c in key.substr(3):
		if c not in "0123456789abcdef":
			return false
	return true


## Whether the auth server answered and said no (as opposed to no answer, or
## the server failing): then the next way in is worth a try.
static func refused(res: Dictionary) -> bool:
	return int(res.get("code", 0)) >= 400 and int(res.get("code", 0)) < 500


static func _rate_limited(res: Dictionary) -> bool:
	return int(res.get("code", 0)) == 429


## Whether an auth answer says the session can never be refreshed again.
static func session_gone(res: Dictionary) -> bool:
	if not res.data is Dictionary:
		return false
	var code := str((res.data as Dictionary).get("error_code", ""))
	return code in SESSION_GONE


## Calls one of the database's functions as this phone's player. Same answer
## as post().
func call_db(function: String, body: Dictionary) -> Dictionary:
	if not await ensure_session():
		return {"ok": false, "code": 0, "data": null}
	return await post("/rest/v1/rpc/" + function, body, true)


## One POST. Returns {"ok": bool, "code": HTTP status (0: no answer), "data": parsed JSON}.
func post(path: String, body: Dictionary, signed_in: bool) -> Dictionary:
	if _host == null or not _host.is_inside_tree():
		return {"ok": false, "code": 0, "data": null}
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	_host.add_child(req)
	var headers := PackedStringArray(["apikey: " + _key, "Content-Type: application/json"])
	if signed_in:
		headers.append("Authorization: Bearer " + _access)
	var err := req.request(_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var answer: Array = await req.request_completed
	req.queue_free()
	var code := int(answer[1])
	var text := (answer[3] as PackedByteArray).get_string_from_utf8()
	var ok := int(answer[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	return {"ok": ok, "code": code, "data": parse(text)}


## Parsed JSON, or null for an empty or broken text (never logs an error).
static func parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null
