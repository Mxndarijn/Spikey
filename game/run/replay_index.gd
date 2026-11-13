class_name ReplayIndex
extends RefCounted
## What the replay scrubber needs to move around a recorded run: keyframes
## (SimCopy copies of the sim every `key_every` ticks) and the run's chapters
## (rooms), bounces, coins and revives. It plays the run on a sim of its own, a
## bounded number of steps per build() call, so the run being watched never
## changes and a frame never stalls. seek(tick) gives a new GameSim standing at
## that tick: a copy of the keyframe at or before it, stepped on with the
## recorded taps exactly as Replay.simulate plays them. No gameplay here.

const KEY_EVERY := SimConfig.TICKS_PER_SECOND
## At most this many keyframes (about 14 MB); a longer run spaces them out.
const MAX_KEYS := 600

var seed_value := 0
var season := Seasons.NONE
var taps := PackedInt32Array()
var revives := PackedInt32Array()
var key_every := KEY_EVERY
## The run's end tick the run file claims (0 = unknown); the timeline's length
## until the index has played it all.
var expected_end := 0
## The tick the run ended at, once the index has played it all; -1 before.
var end_tick := -1
## Chapters: the tick each room started at, its RoomCatalog index and the exit
## kind taken into it (SimState.ExitKind: CALM or WILD behind a fork).
var room_starts := PackedInt32Array()
var room_kinds := PackedInt32Array()
var room_routes := PackedInt32Array()
## Ticks of every wall bounce, coin pickup and revive.
var bounces := PackedInt32Array()
var coins := PackedInt32Array()
var revived_at := PackedInt32Array()

var _keys: Array[GameSim] = []
var _sim: GameSim
var _next_tap := 0
var _next_revive := 0


func _init(
	p_seed: int,
	p_taps: PackedInt32Array,
	p_season: int = Seasons.NONE,
	p_revives: PackedInt32Array = PackedInt32Array(),
	p_expected_end: int = 0
) -> void:
	seed_value = p_seed
	taps = p_taps
	season = p_season
	revives = p_revives
	expected_end = maxi(0, p_expected_end)
	key_every = maxi(KEY_EVERY, ceili(float(expected_end) / MAX_KEYS))
	_sim = GameSim.new(seed_value, season)
	_add_chapter(0)
	_keys.append(SimCopy.copy(_sim))


## An index for the run a driver plays.
static func of_driver(driver: ReplayDriver, p_expected_end: int = 0) -> ReplayIndex:
	return ReplayIndex.new(
		driver.seed_value, driver.taps, driver.season, driver.revives, p_expected_end
	)


## The last tick the index has played to (seek() reaches no further).
func built_to() -> int:
	return _sim.state.tick


func is_done() -> bool:
	return end_tick >= 0


## The timeline's length in ticks: the end once known, else the claimed end.
func length() -> int:
	if end_tick >= 0:
		return maxi(1, end_tick)
	return maxi(1, maxi(expected_end, built_to()))


## Plays up to `steps` more ticks of the run. True once the whole run is in.
func build(steps: int) -> bool:
	while steps > 0 and end_tick < 0:
		if _sim.state.tick >= SimConfig.MAX_TICKS:
			end_tick = _sim.state.tick
			break
		if _sim.is_over():
			if not _revive_due(_sim, _next_revive) or not _sim.revive():
				end_tick = _sim.state.tick
				break
			_next_revive += 1
			revived_at.append(_sim.state.tick)
		var tap := _next_tap < taps.size() and taps[_next_tap] == _sim.state.tick
		if tap:
			_next_tap += 1
		_sim.step(tap)
		steps -= 1
		for e in _sim.events:
			match e:
				GameSim.Event.BOUNCE:
					bounces.append(_sim.state.tick)
				GameSim.Event.COIN:
					coins.append(_sim.state.tick)
				GameSim.Event.ROOM_CHANGE:
					_add_chapter(_sim.state.tick)
		if _sim.state.tick % key_every == 0:
			_keys.append(SimCopy.copy(_sim))
	return end_tick >= 0


## A new sim at `tick` (clamped to what the index has played): as the run
## stood there, after a revive that happened at that tick.
func seek(tick: int) -> GameSim:
	var target := clampi(tick, 0, built_to())
	var sim := SimCopy.copy(_keys[mini(target / key_every, _keys.size() - 1)])
	var next_tap := lower_bound(taps, sim.state.tick)
	while sim.state.tick < target:
		if sim.is_over():
			if not _revive_due(sim, sim.state.revives) or not sim.revive():
				break
		var tap := next_tap < taps.size() and taps[next_tap] == sim.state.tick
		if tap:
			next_tap += 1
		sim.step(tap)
	if sim.is_over() and _revive_due(sim, sim.state.revives):
		sim.revive()
	sim.events.clear()
	return sim


## Which chapter (index into room_starts) `tick` is in.
func chapter_at(tick: int) -> int:
	return maxi(0, upper_bound(room_starts, tick) - 1)


## The bounce before `tick` (by more than `slack` ticks, so a second tap goes
## one further back), or 0.
func bounce_before(tick: int, slack: int = 6) -> int:
	var i := lower_bound(bounces, tick - slack) - 1
	return bounces[i] if i >= 0 else 0


## The bounce after `tick`, or -1 when none is known yet.
func bounce_after(tick: int) -> int:
	var i := upper_bound(bounces, tick)
	return bounces[i] if i < bounces.size() else -1


func _revive_due(sim: GameSim, used: int) -> bool:
	return used < revives.size() and revives[used] == sim.state.tick


func _add_chapter(tick: int) -> void:
	room_starts.append(tick)
	room_kinds.append(_sim.state.room_kind)
	room_routes.append(_sim.state.route)


## The first index whose value is >= `v`.
static func lower_bound(a: PackedInt32Array, v: int) -> int:
	var lo := 0
	var hi := a.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if a[mid] < v:
			lo = mid + 1
		else:
			hi = mid
	return lo


## The first index whose value is > `v`.
static func upper_bound(a: PackedInt32Array, v: int) -> int:
	var lo := 0
	var hi := a.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if a[mid] <= v:
			lo = mid + 1
		else:
			hi = mid
	return lo
