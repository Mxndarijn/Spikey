class_name SupabaseLeaderboard
extends LeaderboardService
## The real leaderboards for friends, on Supabase's free plan (supabase/migrations/,
## setup in docs/LEADERBOARD_SETUP.md). Each phone signs in anonymously once and
## keeps its session in user://. Runs are sent with their seed and taps; a
## checker replays each one (.github/workflows/verify-runs.yml) and the boards
## only show runs that passed, plus the player's own runs still waiting.
## Runs that can't be sent (offline) wait in user:// and go out with the next
## board request or run.

## A sign-in or token refresh finished (ok: there is a valid session now).
signal session_checked(ok: bool)

const CONFIG_PATH := "res://services/supabase_config.json"
const SESSION_PATH := "user://supabase_session.json"
const QUEUE_PATH := "user://pending_runs.json"
const TIMEOUT_S := 10.0
## Refresh the access token this long before it runs out.
const REFRESH_MARGIN_S := 60
## submit_run's later arguments, newest migration last. A database that doesn't
## know the newest ones yet answers 404; the run is then sent without them.
const NEWER_ARGS := [["p_loadout"], ["p_season", "p_coins", "p_end_tick"]]

## Tests point these somewhere else.
var session_path := SESSION_PATH
var queue_path := QUEUE_PATH

var _url := ""
var _key := ""
var _host: Node
var _profile: Profile
var _access := ""
var _refresh := ""
var _expires_at := 0
## Runs not sent yet, oldest first (each the body of a submit_run call).
var _queue: Array[Dictionary] = []
var _sending := false
var _signing_in := false


## url: "https://<project>.supabase.co"; key: the project's public anon key.
## host: a node in the tree to hang the HTTP requests on.
func _init(profile: Profile, host: Node, url: String, key: String) -> void:
	_profile = profile
	_host = host
	_url = url.trim_suffix("/")
	_key = key


## {"url": ..., "anon_key": ...} from the config file, or {} when it is missing
## or incomplete (the game then falls back to the sample boards).
static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = _read_json_any(path)
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


## Loads the saved session and the runs still waiting to be sent.
func restore() -> void:
	var s := _read_json(session_path)
	_access = str(s.get("access_token", ""))
	_refresh = str(s.get("refresh_token", ""))
	_expires_at = int(s.get("expires_at", 0))
	_queue.clear()
	var q: Variant = _read_json_any(queue_path)
	if q is Array:
		for item: Variant in q:
			if item is Dictionary:
				_queue.append(item as Dictionary)


func request_board(board_id: String) -> void:
	_load_board(board_id)


func submit_run(score: int, replay: Dictionary = {}) -> void:
	_queue.append(run_body(_profile, score, replay, int(Time.get_unix_time_from_system())))
	_save_queue()
	_send_queue()


func set_player(player_name: String, flyer_id: String) -> void:
	_set_player(player_name, flyer_id)


## The arguments of submit_run in supabase/migrations/.
static func run_body(profile: Profile, score: int, replay: Dictionary, now_s: int) -> Dictionary:
	return {
		"p_name": profile.leaderboard_name,
		"p_flyer": profile.equipped_id(Catalog.FLYER),
		"p_score": score,
		"p_gameplay_version": int(replay.get("gameplay_version", SimConfig.GAMEPLAY_VERSION)),
		"p_seed": int(replay.get("seed", 0)),
		"p_taps": replay.get("taps", []),
		"p_played_at": Time.get_datetime_string_from_unix_time(now_s) + "Z",
		"p_loadout": loadout_of(profile),
		"p_season": int(replay.get("season", Seasons.NONE)),
		"p_coins": int(replay.get("coins", 0)),
		"p_end_tick": int(replay.get("end_tick", 0)),
	}


## The body without its newest arguments, or {} when nothing is left to drop.
static func older_body(body: Dictionary) -> Dictionary:
	for i in range(NEWER_ARGS.size() - 1, -1, -1):
		var args: Array = NEWER_ARGS[i]
		if body.has(args[0]):
			var out := body.duplicate()
			for a in args:
				out.erase(a)
			return out
	return {}


## get_run's answer with numbers as ints, or {} when it is not a run.
static func parse_run(data: Variant) -> Dictionary:
	if not data is Dictionary or not (data as Dictionary).has("seed"):
		return {}
	var d := data as Dictionary
	var taps: Array[int] = []
	var raw: Variant = d.get("taps", [])
	if raw is Array:
		for t: Variant in raw:
			taps.append(int(t))
	var look: Variant = d.get("loadout", {})
	var run := {
		"run": int(d.get("run", 0)),
		"name": str(d.get("name", "")),
		"score": int(d.get("score", 0)),
		"gameplay_version": int(d.get("gameplay_version", -1)),
		"seed": int(d.get("seed", 0)),
		"taps": taps,
		"loadout": look if look is Dictionary else {},
	}
	# Runs stored before the season was: the replay falls back to today's.
	var season: Variant = d.get("season")
	if season is int or season is float:
		run.season = int(season)
	return run


func request_run(run_id: int) -> void:
	_load_run(run_id)


func _load_run(run_id: int) -> void:
	var run := {}
	if await _ensure_session():
		var res := await _post("/rest/v1/rpc/get_run", {"p_run": run_id}, true)
		if res.ok:
			run = parse_run(res.data)
	run_loaded.emit(run_id, run)


## Turns get_board's answer into a board; anything unexpected reads as offline.
static func parse_board(board_id: String, data: Variant) -> LeaderboardBoard:
	if not data is Dictionary:
		return LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE)
	var d := data as Dictionary
	var b := LeaderboardBoard.make(board_id)
	var list: Variant = d.get("entries", [])
	if list is Array:
		for item: Variant in list:
			if not item is Dictionary:
				continue
			var row := item as Dictionary
			var e := LeaderboardBoard.Entry.new(
				int(row.get("rank", 0)),
				str(row.get("name", "")),
				str(row.get("flyer", "")),
				int(row.get("score", 0))
			)
			# Replayed by the checker; the player's own new run may still wait.
			e.verified = bool(row.get("verified", false))
			e.is_me = bool(row.get("is_me", false))
			e.run_id = int(row.get("run", 0))
			b.entries.append(e)
	var me: Variant = d.get("me")
	if me is Dictionary:
		var mine := LeaderboardBoard.Entry.new(
			int((me as Dictionary).get("rank", 0)), "", "", int((me as Dictionary).get("score", 0))
		)
		mine.is_me = true
		mine.run_id = int((me as Dictionary).get("run", 0))
		mine.verified = bool((me as Dictionary).get("verified", false))
		b.me = mine
	b.players = int(d.get("players", b.entries.size()))
	b.resets_in_s = int(d.get("resets_in_s", -1))
	return b


func pending_runs() -> int:
	return _queue.size()


func _load_board(board_id: String) -> void:
	if not await _ensure_session():
		_deliver(LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE))
		return
	await _send_queue()
	var res := await _post("/rest/v1/rpc/get_board", {"p_board": board_id}, true)
	if not res.ok:
		_deliver(LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE))
		return
	_deliver(parse_board(board_id, res.data))


func _set_player(player_name: String, flyer_id: String) -> void:
	if await _ensure_session():
		await _post("/rest/v1/rpc/set_player", {"p_name": player_name, "p_flyer": flyer_id}, true)


## Sends waiting runs oldest first; stops at the first failure and tries again later.
func _send_queue() -> void:
	if _sending or _queue.is_empty():
		return
	_sending = true
	if await _ensure_session():
		while not _queue.is_empty():
			var res := await _post("/rest/v1/rpc/submit_run", _queue[0], true)
			if not res.ok and res.code == 404 and not older_body(_queue[0]).is_empty():
				# The database doesn't have the newest migration yet: send without it.
				_queue[0] = older_body(_queue[0])
				_save_queue()
				continue
			if not res.ok:
				# A refused run (bad data) would block the queue forever; drop it.
				if res.code >= 400 and res.code < 500 and res.code != 401:
					_queue.pop_front()
					_save_queue()
					continue
				break
			_queue.pop_front()
			_save_queue()
	_sending = false


## A valid access token: the saved one, a refreshed one, or a new anonymous player.
## Calls that arrive while signing in wait for it, so a phone never makes two players.
func _ensure_session() -> bool:
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


func _renew_session(now: int) -> bool:
	var res: Dictionary
	if not _refresh.is_empty():
		res = await _post(
			"/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh}, false
		)
	if _refresh.is_empty() or (not res.ok and res.code >= 400 and res.code < 500):
		res = await _post("/auth/v1/signup", {}, false)
	if not res.ok or not res.data is Dictionary:
		return false
	var d := res.data as Dictionary
	_access = str(d.get("access_token", ""))
	_refresh = str(d.get("refresh_token", ""))
	_expires_at = now + int(d.get("expires_in", 3600))
	_write_json(
		session_path,
		{"access_token": _access, "refresh_token": _refresh, "expires_at": _expires_at}
	)
	return not _access.is_empty()


## One POST. Returns {"ok": bool, "code": HTTP status (0: no answer), "data": parsed JSON}.
func _post(path: String, body: Dictionary, signed_in: bool) -> Dictionary:
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
	return {"ok": ok, "code": code, "data": _parse(text)}


func _save_queue() -> void:
	_write_json(queue_path, _queue)


## Parsed JSON, or null for an empty or broken text (never logs an error).
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null


static func _read_json(path: String) -> Dictionary:
	var v: Variant = _read_json_any(path)
	return v if v is Dictionary else {}


static func _read_json_any(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return _parse(FileAccess.get_file_as_string(path))


static func _write_json(path: String, value: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(value))
		f.close()
