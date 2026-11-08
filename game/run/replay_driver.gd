class_name ReplayDriver
extends RefCounted
## Plays a recorded run back: hands RunController a tap on exactly the ticks
## the run recorded, the same timing as Replay.simulate(). Taps come only from
## here while it is set; input does nothing. Also checks a leaderboard run
## (SupabaseLeaderboard.parse_run output) before it is played.

const EMPTY_MESSAGE := "Couldn't load this replay. Check your connection"
const OLD_VERSION_MESSAGE := (
	"This run was played in an older version of the game" + " and can't be replayed"
)

var seed_value := 0
var season := Seasons.NONE
var taps := PackedInt32Array()
var _next := 0


func _init(p_seed: int = 0, p_taps: PackedInt32Array = [], p_season: int = Seasons.NONE) -> void:
	seed_value = p_seed
	taps = p_taps
	season = p_season


## A driver for a leaderboard run. `fallback_season` is used when the run
## doesn't say which season it was played in.
static func from_run(run: Dictionary, fallback_season: int = Seasons.NONE) -> ReplayDriver:
	var list := PackedInt32Array()
	for t: Variant in run.get("taps", []):
		list.append(int(t))
	list.sort()
	return ReplayDriver.new(int(run.get("seed", 0)), list, int(run.get("season", fallback_season)))


## Why a run can't be played, or "" when it can.
static func problem(run: Dictionary) -> String:
	if run.is_empty() or not run.has("seed"):
		return EMPTY_MESSAGE
	if int(run.get("gameplay_version", -1)) != SimConfig.GAMEPLAY_VERSION:
		return OLD_VERSION_MESSAGE
	return ""


func restart() -> void:
	_next = 0


## Whether the run tapped on `tick`. Ticks are asked in order, once each.
func tap_at(tick: int) -> bool:
	while _next < taps.size() and taps[_next] < tick:
		_next += 1
	if _next < taps.size() and taps[_next] == tick:
		_next += 1
		return true
	return false


## Every recorded tap has been played.
func done() -> bool:
	return _next >= taps.size()
