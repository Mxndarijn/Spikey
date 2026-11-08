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

const DAILY := "daily"
const TIER := "tier"
const ALL_TIME := "all_time"
const FRIENDS := "friends"
## The boards the screen shows. Tier and Friends wait for more players and for
## Game Center / Play Games sign-in; SampleLeaderboard can still build them.
const BOARDS: Array[String] = [DAILY, ALL_TIME]
const TITLES := {DAILY: "Daily", TIER: "Tier", ALL_TIME: "All-time", FRIENDS: "Friends"}
const NAME_MIN := 3
const NAME_MAX := 14
const NAME_FIRST: Array[String] = ["Swift", "Zippy", "Lucky", "Brave", "Bouncy", "Sunny"]
const NAME_LAST: Array[String] = ["Buzz", "Flap", "Wing", "Hop", "Dash"]

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
	for kind in Catalog.KINDS:
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


## What is wrong with a leaderboard name, or "" when it is fine.
static func name_problem(text: String) -> String:
	if text.length() < NAME_MIN:
		return "Use at least %d characters." % NAME_MIN
	if text.length() > NAME_MAX:
		return "Use at most %d characters." % NAME_MAX
	for c in text:
		var ok := (
			(c >= "a" and c <= "z")
			or (c >= "A" and c <= "Z")
			or (c >= "0" and c <= "9")
			or c == "."
			or c == "_"
		)
		if not ok:
			return "Only letters, numbers, dots and underscores."
	if not NameFilter.is_allowed(text):
		return "That name isn't allowed. Pick another one."
	return ""


static func is_valid_name(text: String) -> bool:
	return name_problem(text).is_empty()


## A random friendly name ("ZippyFlap42"), always valid.
static func suggest_name(rng: RandomNumberGenerator) -> String:
	return (
		"%s%s%d"
		% [
			NAME_FIRST[rng.randi_range(0, NAME_FIRST.size() - 1)],
			NAME_LAST[rng.randi_range(0, NAME_LAST.size() - 1)],
			rng.randi_range(10, 99),
		]
	)
