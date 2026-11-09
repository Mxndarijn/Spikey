class_name RunChecker
extends RefCounted
## Decides one stored leaderboard run (a row from worker_pending_runs in
## supabase/migrations/): replays it with the sim and compares the claimed
## score, coins and end tick. server/verify_batch.gd runs it on every new run.

const OK := "ok"
const REJECTED := "rejected"
const OUTDATED := "outdated"
const DAY_S := 86400


## {"id", "status", "reason"}, or {} when the run is newer than this checker
## (it stays pending until the checker runs the newer sim).
static func check(run: Dictionary) -> Dictionary:
	var id := _int(run.get("id"), 0)
	var version := _int(run.get("gameplay_version"), -1)
	if version > SimConfig.GAMEPLAY_VERSION:
		return {}
	if version < SimConfig.GAMEPLAY_VERSION:
		return _result(
			id,
			OUTDATED,
			"gameplay_version %d, checker has %d" % [version, SimConfig.GAMEPLAY_VERSION]
		)
	var taps: Variant = _taps(run.get("taps"))
	if taps == null:
		return _result(id, REJECTED, "invalid taps")
	var day := str(run.get("day", ""))
	var allowed := seasons_around(day)
	if allowed.is_empty():
		return _result(id, REJECTED, "unknown day '%s'" % day)
	# Runs sent before the season was stored: try the seasons of that date.
	var candidates: Array[int] = allowed
	if run.get("season") != null:
		var season := _int(run.get("season"), -1)
		if not season in allowed:
			return _result(id, REJECTED, "season %d not in play on %s" % [season, day])
		candidates = [season]
	var reason := ""
	for candidate in candidates:
		var result := _replay(run, taps as PackedInt32Array, candidate).verify()
		if result.ok:
			return _result(id, OK, "")
		reason = str(result.reason)
	return _result(id, REJECTED, reason)


## The seasons in play the day before, on and after `day` ("YYYY-MM-DD", the
## board's Amsterdam date). Phones use their own local date, which can be a
## day off. Empty for a day that can't be read.
static func seasons_around(day: String) -> Array[int]:
	var out: Array[int] = []
	var parts := day.split("-")
	if parts.size() != 3:
		return out
	for p in parts:
		if not p.is_valid_int():
			return out
	var noon := Time.get_unix_time_from_datetime_dict(
		{"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 12}
	)
	for offset in [-1, 0, 1]:
		var d := Time.get_date_dict_from_unix_time(noon + offset * DAY_S)
		var season := SeasonCalendar.for_date(int(d.month), int(d.day))
		if not season in out:
			out.append(season)
	return out


## The run as a Replay. Coins and end tick that weren't stored (runs sent
## before they were) are taken from the replay itself, so only the score counts.
static func _replay(run: Dictionary, taps: PackedInt32Array, season: int) -> Replay:
	var r := Replay.new()
	r.gameplay_version = _int(run.get("gameplay_version"), -1)
	r.seed_value = _int(run.get("seed"), 0)
	r.season = season
	r.taps = taps
	r.score = _int(run.get("score"), -1)
	r.coins = _int(run.get("coins"), -1)
	r.end_tick = _int(run.get("end_tick"), -1)
	if run.get("coins") == null or run.get("end_tick") == null:
		var sim := Replay.simulate(r.seed_value, taps, season)
		if run.get("coins") == null:
			r.coins = sim.state.coins
		if run.get("end_tick") == null:
			r.end_tick = sim.state.tick
	return r


## Taps as ints, or null when the list holds anything but numbers.
static func _taps(raw: Variant) -> Variant:
	if not raw is Array:
		return null
	var out := PackedInt32Array()
	for t: Variant in raw:
		if not (t is int or t is float):
			return null
		out.append(int(t))
	return out


## JSON numbers arrive as floats; anything else (null, text) reads as `fallback`.
static func _int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


static func _result(id: int, status: String, reason: String) -> Dictionary:
	return {"id": id, "status": status, "reason": reason}
