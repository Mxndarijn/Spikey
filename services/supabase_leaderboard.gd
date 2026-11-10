class_name SupabaseLeaderboard
extends LeaderboardService
## The real leaderboards for friends, on Supabase's free plan (supabase/migrations/,
## setup in docs/LEADERBOARD_SETUP.md), through this phone's SupabaseClient.
## Runs are sent with their seed and taps; a
## checker replays each one (.github/workflows/verify-runs.yml, started by the
## database when a run arrives) and the boards only show runs that passed, plus
## the player's own runs still waiting.
## Runs that can't be sent (offline) wait in user:// and go out with the next
## board request or run.

const QUEUE_PATH := "user://pending_runs.json"
## submit_run's later arguments, newest migration last. A database that doesn't
## know the newest ones yet answers 404; the run is then sent without them.
const NEWER_ARGS := [["p_loadout"], ["p_season", "p_coins", "p_end_tick"]]

## Tests point this somewhere else.
var queue_path := QUEUE_PATH
## The connection, shared with the wallet and push alerts.
var client: SupabaseClient

var _profile: Profile
## Runs not sent yet, oldest first (each the body of a submit_run call).
var _queue: Array[Dictionary] = []
var _sending := false


func _init(profile: Profile, p_client: SupabaseClient) -> void:
	_profile = profile
	client = p_client


## Loads the saved session and the runs still waiting to be sent.
func restore() -> void:
	client.restore()
	_queue.clear()
	var q: Variant = SafeFile.read_json(queue_path)
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
	var body := {
		"p_name": profile.leaderboard_name,
		"p_flyer": profile.equipped_id(ItemKind.FLYER),
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
	# Only a revived run says so: every other run fits the older databases too.
	var revives: Variant = replay.get("revives", [])
	if revives is Array and not (revives as Array).is_empty():
		body["p_revives"] = revives
	return body


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
	var revives: Array[int] = []
	var raw_revives: Variant = d.get("revives", [])
	if raw_revives is Array:
		for t: Variant in raw_revives:
			revives.append(int(t))
	run.revives = revives
	# Runs stored before the season was: the replay falls back to today's.
	var season: Variant = d.get("season")
	if season is int or season is float:
		run.season = int(season)
	return run


func request_run(run_id: int) -> void:
	_load_run(run_id)


func _load_run(run_id: int) -> void:
	var res := await client.call_db("get_run", {"p_run": run_id})
	run_loaded.emit(run_id, parse_run(res.data) if res.ok else {})


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
			# Databases before the name plates migration send none: the plain row.
			e.plate_id = str(row.get("plate", ""))
			e.revived = bool(row.get("revived", false))
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
	if not await client.ensure_session():
		_deliver(LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE))
		return
	await _send_queue()
	var res := await client.call_db("get_board", {"p_board": board_id})
	if not res.ok:
		_deliver(LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE))
		return
	var board := parse_board(board_id, res.data)
	# The player's own row shows the plate in use now, not the one their best
	# run was sent with.
	for e in board.entries:
		if e.is_me:
			e.plate_id = _profile.equipped_id(ItemKind.PLATE)
	_deliver(board)


func _set_player(player_name: String, flyer_id: String) -> void:
	await client.call_db("set_player", {"p_name": player_name, "p_flyer": flyer_id})


## Sends waiting runs oldest first; stops at the first failure and tries again later.
func _send_queue() -> void:
	if _sending or _queue.is_empty():
		return
	_sending = true
	if await client.ensure_session():
		while not _queue.is_empty():
			var res := await client.call_db("submit_run", _queue[0])
			if not res.ok and res.code == 404 and _queue[0].has("p_revives"):
				# The database can't store revives yet. Without them the run would
				# be rejected, so it waits here for the migration.
				break
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


func _save_queue() -> void:
	SafeFile.write_json(queue_path, _queue)
