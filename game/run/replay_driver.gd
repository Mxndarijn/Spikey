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
## Ticks at which the recorded run was revived (Replay.revive_ticks).
var revives := PackedInt32Array()
var _next := 0
var _next_revive := 0


func _init(
	p_seed: int = 0,
	p_taps: PackedInt32Array = [],
	p_season: int = Seasons.NONE,
	p_revives: PackedInt32Array = []
) -> void:
	seed_value = p_seed
	taps = p_taps
	season = p_season
	revives = p_revives


## A driver for a leaderboard run. `fallback_season` is used when the run
## doesn't say which season it was played in.
static func from_run(run: Dictionary, fallback_season: int = Seasons.NONE) -> ReplayDriver:
	var list := PackedInt32Array()
	for t: Variant in run.get("taps", []):
		list.append(int(t))
	list.sort()
	var revive_list := PackedInt32Array()
	for t: Variant in run.get("revives", []):
		revive_list.append(int(t))
	revive_list.sort()
	return ReplayDriver.new(
		int(run.get("seed", 0)), list, int(run.get("season", fallback_season)), revive_list
	)


## Why a run can't be played, or "" when it can.
static func problem(run: Dictionary) -> String:
	if run.is_empty() or not run.has("seed"):
		return EMPTY_MESSAGE
	if int(run.get("gameplay_version", -1)) != SimConfig.GAMEPLAY_VERSION:
		return OLD_VERSION_MESSAGE
	return ""


func restart() -> void:
	_next = 0
	_next_revive = 0


## Moves the cursors to a sim that stands at `tick` having used `revives_used`
## revives (a seek): the next tap asked for is the first at or after `tick`.
func seek(tick: int, revives_used: int) -> void:
	_next = ReplayIndex.lower_bound(taps, tick)
	_next_revive = clampi(revives_used, 0, revives.size())


## Whether the run tapped on `tick`. Ticks are asked in order, once each.
func tap_at(tick: int) -> bool:
	while _next < taps.size() and taps[_next] < tick:
		_next += 1
	if _next < taps.size() and taps[_next] == tick:
		_next += 1
		return true
	return false


## Whether the run was revived when it died at `tick` (the tick the sim stands
## at once dead). Each recorded revive is used once.
func revive_at(tick: int) -> bool:
	if _next_revive < revives.size() and revives[_next_revive] == tick:
		_next_revive += 1
		return true
	return false


## Every recorded tap has been played.
func done() -> bool:
	return _next >= taps.size()
