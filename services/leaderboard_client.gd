class_name LeaderboardService
extends RefCounted
## The leaderboards, as the game sees them. The screens only talk to this
## interface. SupabaseLeaderboard is the real one (friends version, free plan);
## SampleLeaderboard serves made-up boards when no Supabase project is set up.
## A verification server can come later (docs/ARCHITECTURE.md, "Verified
## leaderboards"). This base class has no server: every board is offline.

## A board asked for with request_board(), once it arrives.
signal board_loaded(board: LeaderboardBoard)
## A run asked for with request_run(): {"seed", "taps", "gameplay_version",
## "loadout", "name", "score"}, or {} when it could not be loaded.
signal run_loaded(run_id: int, run: Dictionary)
## Today's Daily Run asked for with request_daily(), once it arrives.
signal daily_loaded(info: DailyRunInfo)
## A try asked for with start_daily_try(): its seed and season, or a failed one.
signal daily_try_started(daily_try: DailyTry)

## Today: the best endless run per player today, each run on its own seed.
## (Its id stays "daily": the server's board and prize tables use it.)
const DAILY := "daily"
const TIER := "tier"
const ALL_TIME := "all_time"
const FRIENDS := "friends"
## The Daily Run: the best try per player on today's one map (DailyRunRules).
const DAILY_RUN := "daily_run"
## The boards the screen shows. Tier and Friends wait for more players and for
## Game Center / Play Games sign-in; SampleLeaderboard can still build them.
const BOARDS: Array[String] = [DAILY, DAILY_RUN, ALL_TIME]
const TITLES := {
	DAILY: "Today", DAILY_RUN: "Daily Run", TIER: "Tier", ALL_TIME: "All-time", FRIENDS: "Friends"
}

## board id -> the player's rank from the last load (0: none yet).
var _ranks := {}
## Boards waiting for the next frame.
var _pending: Array[LeaderboardBoard] = []


## Asks for a board. board_loaded fires with it later (next frame, or when the
## server answers), never inside this call, so callers can show loading first.
func request_board(board_id: String) -> void:
	_deliver(LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE))


## The player's rank on a board from the last load, 0 when unknown or unranked.
func cached_rank(board_id: String) -> int:
	return int(_ranks.get(board_id, 0))


## A finished real run (never practice), with its Replay.to_dict() so the
## seed and taps are kept for checking later.
func submit_run(_score: int, _replay: Dictionary = {}) -> void:
	pass


## Asks for today's Daily Run; daily_loaded fires later (offline here).
func request_daily() -> void:
	_deliver_daily.call_deferred(DailyRunInfo.offline())


## Starts the player's next try on today's map; daily_try_started fires later
## with its seed and season (offline here: no try).
func start_daily_try() -> void:
	_deliver_try.call_deferred(DailyTry.failed(DailyTry.Problem.OFFLINE))


## A finished Daily Run try, with its Replay.to_dict(). Sent once per try.
func submit_daily_run(_daily_try: DailyTry, _score: int, _replay: Dictionary = {}) -> void:
	pass


func _deliver_daily(info: DailyRunInfo) -> void:
	daily_loaded.emit(info)


func _deliver_try(daily_try: DailyTry) -> void:
	daily_try_started.emit(daily_try)


## Diamonds the board pays for a place when its day is over (0: none).
static func prize(board_id: String, rank: int) -> int:
	match board_id:
		DAILY:
			return Economy.daily_prize(rank)
		DAILY_RUN:
			return Economy.daily_run_prize(rank)
	return 0


## The board pays its top 10 when its day is over.
static func pays(board_id: String) -> bool:
	return board_id == DAILY or board_id == DAILY_RUN


## The player's leaderboard name and flyer changed.
func set_player(_player_name: String, _flyer_id: String) -> void:
	pass


## Asks for one run's replay (LeaderboardBoard.Entry.run_id); run_loaded fires later.
func request_run(run_id: int) -> void:
	_deliver_run.call_deferred(run_id, {})


func _deliver_run(run_id: int, run: Dictionary) -> void:
	run_loaded.emit(run_id, run)


## The player's look for a replay: every cosmetic kind they have equipped
## ({"flyer": "dash", "world": "ice", ...}). Cosmetic only, never gameplay.
static func loadout_of(profile: Profile) -> Dictionary:
	var out := {}
	for kind in ItemKind.ALL:
		var id := profile.equipped_id(kind)
		if not id.is_empty():
			out[kind] = id
	return out


## Friends come from Game Center (iOS) or Play Games (Android).
func is_signed_in() -> bool:
	return false


func sign_in() -> void:
	pass


## Remembers the player's rank and hands the board over on the next frame.
## The frame signal is connected to this object, so Godot drops it if the
## service is gone by then.
func _deliver(board: LeaderboardBoard) -> void:
	_ranks[board.id] = board.me.rank if board.me != null else 0
	_pending.append(board)
	var tree := Engine.get_main_loop() as SceneTree
	if not tree.process_frame.is_connected(_flush):
		tree.process_frame.connect(_flush, CONNECT_ONE_SHOT)


func _flush() -> void:
	var boards := _pending.duplicate()
	_pending.clear()
	for b: LeaderboardBoard in boards:
		board_loaded.emit(b)
