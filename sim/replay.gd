class_name Replay
extends RefCounted
## A recorded run: everything needed to re-simulate it exactly.
## This is what the client submits and what the server verifies.

var gameplay_version := SimConfig.GAMEPLAY_VERSION
var seed_value := 0
## Seasonal rooms in play (Seasons.*). The server checks it against the date.
var season := Seasons.NONE
## Ticks at which a tap was applied, strictly ascending.
var taps := PackedInt32Array()
## Ticks at which the dead bird was revived (GameSim.revive): the tick the sim
## stood at when it died. At most SimConfig.MAX_REVIVES, ascending.
var revive_ticks := PackedInt32Array()
## The final result, after any revive.
var score := 0
## Coins collected; they go to the player's balance, so they're verified too.
var coins := 0
var end_tick := 0
var checksum := 0


static func from_sim(
	sim: GameSim, p_taps: PackedInt32Array, p_revives: PackedInt32Array = PackedInt32Array()
) -> Replay:
	var r := Replay.new()
	r.seed_value = sim.seed_value
	r.season = sim.season
	r.taps = p_taps
	r.revive_ticks = p_revives
	r.score = sim.state.score
	r.coins = sim.state.coins
	r.end_tick = sim.state.tick
	r.checksum = sim.checksum()
	return r


## Runs the sim with the given taps until death (or MAX_TICKS). A death at
## the next revive tick is revived and the run goes on; a revive tick the bird
## was not dead at is never used (see sim.state.revives).
static func simulate(
	p_seed: int,
	p_taps: PackedInt32Array,
	p_season: int = Seasons.NONE,
	p_revives: PackedInt32Array = PackedInt32Array()
) -> GameSim:
	var sim := GameSim.new(p_seed, p_season)
	var next := 0
	var next_revive := 0
	while sim.state.tick < SimConfig.MAX_TICKS:
		if sim.is_over():
			var due := next_revive < p_revives.size() and p_revives[next_revive] == sim.state.tick
			if not due or not sim.revive():
				break
			next_revive += 1
		var tap := next < p_taps.size() and p_taps[next] == sim.state.tick
		if tap:
			next += 1
		sim.step(tap)
	return sim


## Re-simulates this replay and checks the claimed result.
## Returns {ok: bool, reason: String, score: int, coins: int, end_tick: int, checksum: int}.
func verify() -> Dictionary:
	var result := {"ok": false, "reason": "", "score": 0, "coins": 0, "end_tick": 0, "checksum": 0}
	if gameplay_version != SimConfig.GAMEPLAY_VERSION:
		result.reason = "unsupported gameplay_version %d" % gameplay_version
		return result
	for i in taps.size():
		if taps[i] < 0 or (i > 0 and taps[i] <= taps[i - 1]):
			result.reason = "taps must be ascending and non-negative"
			return result
	if revive_ticks.size() > SimConfig.MAX_REVIVES:
		result.reason = "too many revives"
		return result
	for i in revive_ticks.size():
		if revive_ticks[i] < 0 or (i > 0 and revive_ticks[i] <= revive_ticks[i - 1]):
			result.reason = "revives must be ascending and non-negative"
			return result
	if season < Seasons.NONE or season >= Seasons.COUNT:
		result.reason = "unknown season %d" % season
		return result
	var sim := simulate(seed_value, taps, season, revive_ticks)
	result.score = sim.state.score
	result.coins = sim.state.coins
	result.end_tick = sim.state.tick
	result.checksum = sim.checksum()
	if not sim.is_over():
		result.reason = "run did not end"
	elif sim.state.revives != revive_ticks.size():
		result.reason = "revive without a death"
	elif taps.size() > 0 and taps[taps.size() - 1] >= sim.state.tick:
		result.reason = "taps after death"
	elif sim.state.score != score:
		result.reason = "score mismatch (claimed %d, replayed %d)" % [score, sim.state.score]
	elif sim.state.coins != coins:
		result.reason = "coins mismatch (claimed %d, replayed %d)" % [coins, sim.state.coins]
	elif sim.state.tick != end_tick:
		result.reason = "end_tick mismatch"
	elif checksum != 0 and checksum != result.checksum:
		result.reason = "checksum mismatch"
	else:
		result.ok = true
	return result


func to_dict() -> Dictionary:
	return {
		"gameplay_version": gameplay_version,
		"seed": seed_value,
		"season": season,
		"taps": Array(taps),
		"revives": Array(revive_ticks),
		"score": score,
		"coins": coins,
		"end_tick": end_tick,
		"checksum": checksum,
	}


## JSON numbers arrive as floats; everything is converted back to int here.
static func from_dict(d: Dictionary) -> Replay:
	var r := Replay.new()
	r.gameplay_version = int(d.get("gameplay_version", -1))
	r.seed_value = int(d.get("seed", 0))
	r.season = int(d.get("season", Seasons.NONE))
	var tap_list := PackedInt32Array()
	for t: Variant in d.get("taps", []):
		tap_list.append(int(t))
	r.taps = tap_list
	var revive_list := PackedInt32Array()
	for t: Variant in d.get("revives", []):
		revive_list.append(int(t))
	r.revive_ticks = revive_list
	r.score = int(d.get("score", 0))
	r.coins = int(d.get("coins", 0))
	r.end_tick = int(d.get("end_tick", 0))
	r.checksum = int(d.get("checksum", 0))
	return r
