class_name FlapjawClient
extends BackendClient
## This phone's connection to our own server (backend/, docs/SERVER_MIGRATION.md).
## The operations are the server's SQL functions (backend/migrations/), same
## names, arguments and answers, at POST <url>/v1/<op> with a Bearer token.
## Sign-in: every player has a device key (32 random bytes) that the server
## keeps only as a hash. The phone signs in with its refresh token, then with
## the key, and only when the server says both are no good as a new player
## (POST /v1/auth/anon), never because of a network hiccup. The key is kept in
## user:// and, on iOS, also in the Keychain, so a reinstall is the same player.
## When the server says the player moved to another phone (a transfer code was
## used there), the client forgets this player and the next sign-in starts a
## new one; `account_moved` tells the game to say so.

const SESSION_PATH := "user://flapjaw_session.json"
const DEVICE_PATH := "user://flapjaw_device.json"
## The Keychain entry ({"key", "player"} JSON, like the file).
const KEYCHAIN_ITEM := "flapjaw_device"
## Refresh the access token this long before it runs out.
const REFRESH_MARGIN_S := 60
## The `error` the server answers 401 with after a transfer moved the player.
const MOVED := "account_moved"

var _access := ""
var _refresh := ""
var _expires_at := 0
var _player := ""
var _signing_in := false
var _device_key := ""
## The player the device key belongs to ("" until the server took it).
var _device_player := ""


## url: "https://api.example.com" (no path).
func _init(host: Node, url: String) -> void:
	session_path = SESSION_PATH
	device_path = DEVICE_PATH
	_host = host
	_url = url.trim_suffix("/")


func kind() -> String:
	return KIND_FLAPJAW


## The Duel socket's address (wss:// for an https server) and the token its
## hello signs in with (after ensure_session).
func duel_socket() -> Dictionary:
	var ws := _url.replace("https://", "wss://").replace("http://", "ws://")
	return {"url": ws + "/v1/duel/ws", "token": _access}


## This phone's player id ("" before the first sign-in).
func player_id() -> String:
	return _player


func restore() -> void:
	var s: Variant = SafeFile.read_json(session_path)
	var d: Dictionary = s if s is Dictionary else {}
	_access = str(d.get("access_token", ""))
	_refresh = str(d.get("refresh_token", ""))
	_expires_at = int(d.get("expires_at", 0))
	_player = str(d.get("player", ""))
	var saved := device_entry(SafeFile.read_json(device_path))
	var kept := {}
	if keychain != null:
		kept = device_entry(parse(str(keychain.call("read", KEYCHAIN_ITEM))))
	var dev := saved if not saved.is_empty() else kept
	_device_key = str(dev.get("key", ""))
	_device_player = str(dev.get("player", ""))
	if dev != saved or (keychain != null and dev != kept):
		_save_device()


## A saved {"key", "player"} with a well-formed key, or {}.
static func device_entry(saved: Variant) -> Dictionary:
	var d: Dictionary = saved if saved is Dictionary else {}
	var key := str(d.get("key", ""))
	if not is_device_key(key):
		return {}
	return {"key": key, "player": str(d.get("player", ""))}


func has_device_login() -> bool:
	return not _device_key.is_empty() and not _device_player.is_empty()


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


## Refresh token, then the device key, then a new player; no answer at all
## keeps everything for later.
func _renew_session(now: int) -> bool:
	var res := {"ok": false, "code": 0, "data": null}
	var tried := false
	if not _refresh.is_empty():
		tried = true
		res = await post("/v1/auth/refresh", {"refresh_token": _refresh}, false)
		if not res.ok and not refused(res):
			return false
		if moved(res):
			_forget_player()
	if not res.ok and has_device_login():
		tried = true
		res = await post(
			"/v1/auth/device", {"player_id": _device_player, "device_key": _device_key}, false
		)
		if not res.ok and not refused(res):
			return false
		if moved(res):
			_forget_player()
	if not res.ok:
		if tried and _rate_limited(res):
			return false
		# A new player gets a new key, saved before it is sent, so a lost
		# answer sends the same key again.
		if _device_key.is_empty() or not _device_player.is_empty():
			_device_key = new_device_key()
			_device_player = ""
			_save_device()
		res = await post("/v1/auth/anon", {"device_key": _device_key}, false)
	if not res.ok or not res.data is Dictionary:
		return false
	return adopt_session(res.data as Dictionary, _device_key, now)


## Takes a session answer {"player_id", "access_token", "refresh_token",
## "expires_in"} for the given device key (a sign-in, or a transfer that moved
## a player here). False when the answer isn't one.
func adopt_session(d: Dictionary, key: String, now: int = -1) -> bool:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var access := str(d.get("access_token", ""))
	var player := str(d.get("player_id", ""))
	if access.is_empty() or player.is_empty():
		return false
	_access = access
	_refresh = str(d.get("refresh_token", ""))
	_expires_at = now + int(d.get("expires_in", 3600))
	_player = player
	(
		SafeFile
		. write_json(
			session_path,
			{
				"access_token": _access,
				"refresh_token": _refresh,
				"expires_at": _expires_at,
				"player": _player,
			}
		)
	)
	_device_key = key
	_device_player = player
	_save_device()
	return true


func call_db(function: String, body: Dictionary) -> Dictionary:
	if not await ensure_session():
		return {"ok": false, "code": 0, "data": null}
	var res := await post("/v1/" + function, body, true)
	if int(res.code) != 401:
		return res
	if moved(res):
		_forget_player()
		return res
	# The token ran out early (a clock off, the server restarted with a new
	# key): sign in again once.
	_access = ""
	if not await ensure_session():
		return res
	return await post("/v1/" + function, body, true)


## Moves the player of a transfer code to this phone (docs/ACCOUNT_TRANSFER.md):
## {"ok", "code", "data"} as call_db; on success this phone is that player.
## A new device key goes with it; the old phone's keys stop working.
func redeem_transfer(code: String) -> Dictionary:
	if not await ensure_session():
		return {"ok": false, "code": 0, "data": null}
	var key := new_device_key()
	var res := await post("/v1/transfer/redeem", {"code": code, "device_key": key}, true)
	if res.ok and res.data is Dictionary:
		if not adopt_session(res.data as Dictionary, key):
			res.ok = false
	return res


## Whether an answer says this player was moved to another phone.
static func moved(res: Dictionary) -> bool:
	if int(res.get("code", 0)) != 401 or not res.get("data") is Dictionary:
		return false
	return str((res.data as Dictionary).get("error", "")) == MOVED


## The server moved this player away: drop the session and key, so the next
## sign-in makes a new player, and tell the game once.
func _forget_player() -> void:
	_access = ""
	_refresh = ""
	_expires_at = 0
	_player = ""
	_device_key = ""
	_device_player = ""
	SafeFile.write_json(session_path, {})
	SafeFile.write_json(device_path, {})
	if keychain != null:
		keychain.call("write", KEYCHAIN_ITEM, "{}")
	account_moved.emit()


func _save_device() -> void:
	var entry := {"key": _device_key, "player": _device_player}
	SafeFile.write_json(device_path, entry)
	if keychain != null:
		keychain.call("write", KEYCHAIN_ITEM, JSON.stringify(entry))


func _headers(signed_in: bool) -> PackedStringArray:
	var headers := PackedStringArray(
		[
			"Content-Type: application/json",
			"X-Flapjaw-Api: %d" % API_VERSION,
			"X-Flapjaw-Gameplay: %d" % SimConfig.GAMEPLAY_VERSION,
		]
	)
	if signed_in and not _access.is_empty():
		headers.append("Authorization: Bearer " + _access)
	return headers
