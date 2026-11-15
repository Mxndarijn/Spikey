class_name BackendClient
extends RefCounted
## This phone's connection to a game server: the player's session and calls to
## the server's operations by name (`call_db("get_board", {...})`), each
## answering {"ok", "code", "data"}. The leaderboards, the wallet, the save on
## the server and push alerts all go through one client, so a phone is one
## player everywhere.
## Two kinds sit side by side while the game moves servers
## (docs/SERVER_MIGRATION.md): SupabaseClient (the Supabase project) and
## FlapjawClient (our own server, server/). Both take the same operation names,
## arguments and answers, so the services above never know which one runs.
## The config file names the kind; `make()` builds the right one.

## A sign-in or token refresh finished (ok: there is a valid session now).
signal session_checked(ok: bool)
## The server answered that this app is too old to talk to it (HTTP 426): the
## game asks the player to update. Sent once per launch.
signal update_required
## The server answered that this player was moved to another phone (a transfer
## code was used there). The client has already let go of the old session.
signal account_moved

## The config that picks the backend. Missing: the older Supabase-only file.
const BACKEND_CONFIG_PATH := "res://services/backend_config.json"
const KIND_SUPABASE := "supabase"
const KIND_FLAPJAW := "flapjaw"
## The version of the request protocol this app speaks; the server refuses
## anything older than its MIN_API_VERSION with 426 ("please update").
const API_VERSION := 1
const TIMEOUT_S := 10.0
## The iOS engine's Keychain singleton (tools/engine/modules/flapjaw_keychain).
const KEYCHAIN_SINGLETON := "FlapjawKeychain"

## Tests point these somewhere else.
var session_path := ""
var device_path := ""
## The Keychain (read(name) -> String, write(name, value) -> bool), or null
## where there is none (every build but iOS). Looked up by name, never by class.
var keychain: Object = (
	Engine.get_singleton(KEYCHAIN_SINGLETON) if Engine.has_singleton(KEYCHAIN_SINGLETON) else null
)
## The server said this app is too old (426); stays set for this launch.
var update_needed := false

var _url := ""
var _host: Node


## The config: {"kind", "url", "anon_key" (Supabase only), "server_id"
## (Flapjaw only, the one-time reset's marker)}, or {} when there is none or
## it is incomplete (the game then plays offline with sample boards).
## `path` is the backend config; without it the older Supabase file is read.
static func load_backend_config(
	path: String = BACKEND_CONFIG_PATH, supabase_path: String = SupabaseClient.CONFIG_PATH
) -> Dictionary:
	if not FileAccess.file_exists(path):
		var old := SupabaseClient.load_config(supabase_path)
		if old.is_empty():
			return {}
		old["kind"] = KIND_SUPABASE
		return old
	var data: Variant = parse(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {}
	return config_of(data as Dictionary)


## A config dictionary checked: {} when its kind or address is missing or still
## the example's placeholder.
static func config_of(d: Dictionary) -> Dictionary:
	var kind := str(d.get("kind", ""))
	var url := str(d.get("url", "")).trim_suffix("/")
	if not url.begins_with("https://") and not url.begins_with("http://"):
		return {}
	if _is_placeholder(url):
		return {}
	if kind == KIND_SUPABASE:
		var key := str(d.get("anon_key", ""))
		if key.is_empty() or _is_placeholder(key) or not url.begins_with("https://"):
			return {}
		return {"kind": kind, "url": url, "anon_key": key}
	if kind == KIND_FLAPJAW:
		var server_id := str(d.get("server_id", ""))
		if server_id.is_empty() or _is_placeholder(server_id):
			return {}
		return {"kind": kind, "url": url, "server_id": server_id}
	return {}


static func _is_placeholder(text: String) -> bool:
	return "YOUR-" in text or "PASTE-" in text or "<" in text


## The client a config asks for (see load_backend_config), or null for {}.
static func make(host: Node, config: Dictionary) -> BackendClient:
	match str(config.get("kind", "")):
		KIND_SUPABASE:
			return SupabaseClient.new(host, str(config.url), str(config.anon_key))
		KIND_FLAPJAW:
			return FlapjawClient.new(host, str(config.url))
	return null


## Which backend this is (KIND_*).
func kind() -> String:
	return ""


## Loads the saved session and device key.
func restore() -> void:
	pass


## A valid session: the saved one, a refreshed one, or a new player when there
## is none. Calls that arrive while signing in wait for it.
func ensure_session() -> bool:
	return false


## Calls one of the server's operations as this phone's player.
## {"ok": bool, "code": HTTP status (0: no answer), "data": parsed JSON}.
func call_db(_function: String, _body: Dictionary) -> Dictionary:
	return {"ok": false, "code": 0, "data": null}


## Whether a saved device key can sign in (the server took it).
func has_device_login() -> bool:
	return false


## The headers of every request (signed_in: with the player's token).
func _headers(_signed_in: bool) -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json"])


## One POST. Returns {"ok": bool, "code": HTTP status (0: no answer), "data": parsed JSON}.
func post(path: String, body: Dictionary, signed_in: bool) -> Dictionary:
	if _host == null or not _host.is_inside_tree():
		return {"ok": false, "code": 0, "data": null}
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	_host.add_child(req)
	var err := req.request(
		_url + path, _headers(signed_in), HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var answer: Array = await req.request_completed
	req.queue_free()
	var code := int(answer[1])
	var text := (answer[3] as PackedByteArray).get_string_from_utf8()
	var ok := int(answer[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var res := {"ok": ok, "code": code, "data": parse(text)}
	note_answer(res)
	return res


## Watches every answer for "this app is too old" (426).
func note_answer(res: Dictionary) -> void:
	if int(res.get("code", 0)) == 426 and not update_needed:
		update_needed = true
		update_required.emit()


## Parsed JSON, or null for an empty or broken text (never logs an error).
static func parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null


## "Fj-" and 64 hex characters from 32 random bytes.
static func new_device_key() -> String:
	return "Fj-" + Crypto.new().generate_random_bytes(32).hex_encode()


static func is_device_key(key: String) -> bool:
	if key.length() != 67 or not key.begins_with("Fj-"):
		return false
	for c in key.substr(3):
		if c not in "0123456789abcdef":
			return false
	return true


## Whether the server answered and said no (as opposed to no answer, or the
## server failing): then the next way in is worth a try.
static func refused(res: Dictionary) -> bool:
	return int(res.get("code", 0)) >= 400 and int(res.get("code", 0)) < 500


static func _rate_limited(res: Dictionary) -> bool:
	return int(res.get("code", 0)) == 429
