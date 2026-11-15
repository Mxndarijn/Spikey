class_name PhoneMove
extends RefCounted
## Move to a new phone (docs/ACCOUNT_TRANSFER.md), on our own server only.
## The old phone gets a one-time code (after its waiting runs and save were
## sent, so nothing is left behind); the new phone looks at what the code would
## move and then takes it: it becomes that player, gets the server's save back
## (ProfileSync), the wallet and the player's runs for Your runs. Its own
## progress is replaced, never merged. The page is PhoneMovePage in Settings.

## The code's player is on this phone now (Home shows the moved progress).
signal moved

## What the server's refusals mean for the player.
const PROBLEMS := {
	"unknown_code": "That code doesn't work. Check it and try again.",
	"code_used": "That code was already used.",
	"code_expired": "That code has expired. Get a new one on your old phone.",
	"rate_limited": "Too many tries. Wait an hour, then try again.",
	"bad_request": "That code doesn't work. Check it and try again.",
	"offline": "No connection. Try again when you're online.",
}

var _client: FlapjawClient
var _profile: Profile
var _services: AppServices
var _runs: RunStore
## Writes the save; the first start (free flyer and world) for a save without one.
var _save: Callable
var _first_start: Callable


func _init(
	client: FlapjawClient,
	profile: Profile,
	services: AppServices,
	runs: RunStore,
	save: Callable,
	first_start: Callable
) -> void:
	_client = client
	_profile = profile
	_services = services
	_runs = runs
	_save = save
	_first_start = first_start


## {"ok", "code" (12 characters), "expires_at" (unix s), "problem"}.
func make_code() -> Dictionary:
	var board := _services.leaderboard as OnlineLeaderboard
	if board != null:
		await board.send_waiting()
	await _services.profile_sync.push()
	var res := await _client.call_db("transfer/create", {})
	if not res.ok:
		return {"ok": false, "problem": problem(res)}
	var d: Dictionary = res.data
	return {"ok": true, "code": str(d.get("code", "")), "expires_at": int(d.get("expires_at", 0))}


func cancel_code() -> void:
	await _client.call_db("transfer/cancel", {})


## What a code would move: {"ok", "problem", "name", "best", "gold", "diamonds",
## "items", "this_phone": {the same for this phone}}.
func preview(code: String) -> Dictionary:
	var res := await _client.call_db("transfer/preview", {"code": code})
	if not res.ok or not res.data is Dictionary:
		return {"ok": false, "problem": problem(res)}
	var d: Dictionary = (res.data as Dictionary).duplicate()
	d["ok"] = true
	return d


## Takes the code's player onto this phone. {"ok", "problem"}.
func redeem(code: String) -> Dictionary:
	var res := await _client.redeem_transfer(code)
	if not res.ok:
		return {"ok": false, "problem": problem(res)}
	# This phone's own progress goes; the server's copy of the save comes.
	BackendReset.clear(_profile, _profile.backend_server)
	await _services.profile_sync.push()
	if not _profile.onboarded:
		_first_start.call()
	_save.call()
	_services.wallet.sync()
	await import_runs()
	moved.emit()
	return {"ok": true, "problem": ""}


## The player's runs from the server become Your runs on this phone.
func import_runs() -> void:
	var res := await _client.call_db("get_my_runs", {})
	if not res.ok or not res.data is Dictionary:
		return
	var rows: Variant = (res.data as Dictionary).get("runs", [])
	if not rows is Array:
		return
	var records: Array[RunRecord] = []
	for row: Variant in rows:
		if row is Dictionary:
			records.append(record_of(row as Dictionary))
	# Oldest first, so the newest gets the highest id.
	records.reverse()
	_runs.replace(records)


## One server run as a Your runs entry. Rooms are counted from the score (a
## room change every 10 points); the revive score isn't stored on the server.
static func record_of(row: Dictionary) -> RunRecord:
	var r := Replay.new()
	r.gameplay_version = int(row.get("gameplay_version", -1))
	r.seed_value = int(row.get("seed", 0))
	var season: Variant = row.get("season")
	r.season = int(season) if season is float or season is int else Seasons.NONE
	r.taps = _ticks(row.get("taps"))
	r.revive_ticks = _ticks(row.get("revives"))
	r.score = int(row.get("score", 0))
	var coins: Variant = row.get("coins")
	r.coins = int(coins) if coins is float or coins is int else 0
	var end: Variant = row.get("end_tick")
	r.end_tick = int(end) if end is float or end is int else 0
	var look: Variant = row.get("loadout", {})
	var loadout: Dictionary = look if look is Dictionary else {}
	var revived := -1 if r.revive_ticks.is_empty() else 0
	return RunRecord.make(
		r, loadout, int(row.get("played_at", 0)), 1 + floori(r.score / 10.0), revived
	)


static func _ticks(raw: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if raw is Array:
		for t: Variant in raw:
			out.append(int(t))
	return out


## The player's words for a refusal.
static func problem(res: Dictionary) -> String:
	if int(res.get("code", 0)) == 0:
		return PROBLEMS.offline
	var data: Variant = res.get("data")
	var error := str((data as Dictionary).get("error", "")) if data is Dictionary else ""
	if int(res.get("code", 0)) == 400 and error == "bad_request" and data is Dictionary:
		if "already is that player" in str((data as Dictionary).get("message", "")):
			return "This phone already has that progress."
	return str(PROBLEMS.get(error, "Something went wrong. Try again later."))


## "K7QF-3MZD-PX9W" for "K7QF3MZDPX9W".
static func grouped(code: String) -> String:
	if code.length() != 12:
		return code
	return "%s-%s-%s" % [code.substr(0, 4), code.substr(4, 4), code.substr(8, 4)]
