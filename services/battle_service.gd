class_name BattleService
extends RefCounted
## Battle and the wins boards through our own server (the battle_* operations
## and get_wins_board / get_match_record in backend/migrations/0110_battles.sql
## and 0111_wins_boards.sql). Every call answers with a signal; with no server
## (the client is null) or no answer, `failed` says why.
## A run that couldn't be sent is kept by BattleFlow and sent again
## (battle_submit is idempotent: a run sent twice counts once).

## The battle list: [BattleView], your turn first.
signal list_loaded(battles: Array[BattleView])
## One battle changed or arrived (get, create, join, resign, close, nudge, rematch, submit).
signal battle_loaded(view: BattleView)
## A run started: {battle, round, seed, season, blind}. When the server says the
## run before was lost or the round was dealt again, battle_loaded comes instead.
signal run_started(start: Dictionary)
## A wins board: {entries: [...], me, players, resets_in_s, rate_min}.
signal wins_loaded(mode: String, period: String, board: Dictionary)
## A player's record on a wins board.
signal record_loaded(record: Dictionary)
## Something didn't work: the operation and a line to show.
signal failed(op: String, message: String)

const OFFLINE := "No connection. Try again in a moment."
const TOO_MANY := "You have 20 battles going. Finish or close one first."
const BAD_CODE := "That code doesn't work. Check it and try again."

var client: BackendClient
var _profile: Profile


func _init(profile: Profile, p_client: BackendClient) -> void:
	_profile = profile
	client = p_client


func is_online() -> bool:
	return client != null


func request_list() -> void:
	var res := await _call("battle_list", {})
	if not res.ok:
		return
	var out: Array[BattleView] = []
	var data: Variant = res.data
	if data is Dictionary and (data as Dictionary).get("battles") is Array:
		for b: Variant in (data as Dictionary).get("battles"):
			out.append(BattleView.parse(b))
	list_loaded.emit(out)


func request_battle(battle: int) -> void:
	await _view("battle_get", {"p_battle": battle})


## A new battle: "invite" (the answer carries the code) or "random".
func create(opponent: String) -> void:
	var body := _me()
	body["p_opponent"] = opponent
	body["p_gameplay_version"] = SimConfig.GAMEPLAY_VERSION
	await _view("battle_create", body)


func join(code: String) -> void:
	var body := _me()
	body["p_code"] = code
	await _view("battle_join", body)


func resign(battle: int) -> void:
	await _view("battle_resign", {"p_battle": battle})


func close(battle: int) -> void:
	await _view("battle_close", {"p_battle": battle})


func nudge(battle: int) -> void:
	await _view("battle_nudge", {"p_battle": battle})


func rematch(battle: int) -> void:
	await _view("battle_rematch", {"p_battle": battle})


## Starts the run of a round: its seed comes back in run_started.
func start_run(battle: int, round_number: int) -> void:
	var body := {
		"p_battle": battle,
		"p_round": round_number,
		"p_gameplay_version": SimConfig.GAMEPLAY_VERSION
	}
	var res := await _call("battle_start_run", body)
	if not res.ok:
		return
	var data: Variant = res.data
	if not data is Dictionary:
		failed.emit("battle_start_run", OFFLINE)
		return
	var d := data as Dictionary
	if bool(d.get("lost", false)) or bool(d.get("redealt", false)) or not d.has("seed"):
		battle_loaded.emit(BattleView.parse(d))
		return
	run_started.emit(d)


## A finished run of a round (Replay.to_dict()).
func submit(battle: int, round_number: int, score: int, replay: Dictionary) -> void:
	await _view("battle_submit", submit_body(_profile, battle, round_number, score, replay))


## The arguments of battle_submit.
static func submit_body(
	profile: Profile, battle: int, round_number: int, score: int, replay: Dictionary
) -> Dictionary:
	return {
		"p_battle": battle,
		"p_round": round_number,
		"p_name": profile.leaderboard_name,
		"p_flyer": profile.equipped_id(ItemKind.FLYER),
		"p_score": score,
		"p_gameplay_version": int(replay.get("gameplay_version", SimConfig.GAMEPLAY_VERSION)),
		"p_seed": int(replay.get("seed", 0)),
		"p_taps": replay.get("taps", []),
		"p_loadout": LeaderboardService.loadout_of(profile),
		"p_season": int(replay.get("season", Seasons.NONE)),
		"p_coins": int(replay.get("coins", 0)),
		"p_end_tick": int(replay.get("end_tick", 0)),
	}


func request_wins(mode: String, period: String) -> void:
	var res := await _call("get_wins_board", {"p_mode": mode, "p_period": period})
	if res.ok and res.data is Dictionary:
		wins_loaded.emit(mode, period, res.data as Dictionary)


func request_record(mode: String, period: String, who: String) -> void:
	var res := await _call("get_match_record", {"p_mode": mode, "p_period": period, "p_who": who})
	if res.ok and res.data is Dictionary:
		record_loaded.emit(res.data as Dictionary)


func _me() -> Dictionary:
	return {"p_name": _profile.leaderboard_name, "p_flyer": _profile.equipped_id(ItemKind.FLYER)}


func _view(op: String, body: Dictionary) -> void:
	var res := await _call(op, body)
	if res.ok:
		battle_loaded.emit(BattleView.parse(res.data))


## One call; a refusal or no answer emits `failed` and comes back not ok.
func _call(op: String, body: Dictionary) -> Dictionary:
	if client == null:
		failed.emit(op, OFFLINE)
		return {"ok": false, "code": 0, "data": null}
	var res := await client.call_db(op, body)
	if not res.ok:
		failed.emit(op, message_for(op, res))
	return res


## What to tell the player when the server says no.
static func message_for(op: String, res: Dictionary) -> String:
	var code := int(res.get("code", 0))
	if code == 0 or code >= 500:
		return OFFLINE
	var text := ""
	if res.get("data") is Dictionary:
		text = str((res.get("data") as Dictionary).get("message", ""))
	if text.contains("too many battles"):
		return TOO_MANY
	if op == "battle_join":
		return BAD_CODE
	if text.contains("not your turn"):
		return "It's not your turn in this battle."
	return "That didn't work. Try again."
