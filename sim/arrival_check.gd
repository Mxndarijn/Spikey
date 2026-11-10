class_name ArrivalCheck
extends RefCounted
## Out of a portal the player needs a moment to read the new room. This plays
## the arrival on a copy: for ARRIVAL_BLIND ticks the bird only holds its
## height (the player hasn't looked yet), then a few simple ways to play on
## each get ARRIVAL_FOLLOW ticks. The arrival is fair when one of them lives.

## Heights the simple players aim at, around the gap ahead or where the bird
## came in.
const OFFSETS := [0, -24 * SimConfig.SUB, 24 * SimConfig.SUB]
const HOLD_SHIFTS := [0, -60 * SimConfig.SUB, 60 * SimConfig.SUB]


## Ticks the best simple player lived (ARRIVAL_BLIND + ARRIVAL_FOLLOW = fair).
## `sim` is a copy that is used up.
static func score(sim: GameSim) -> int:
	var y0 := sim.state.y
	var n := 0
	while n < SimConfig.ARRIVAL_BLIND:
		sim.step(_toward(sim, y0))
		if sim.is_over():
			return n
		n += 1
	var best := 0
	for kind in 2:
		for i in 3:
			var c := SimCopy.copy(sim)
			var lived := _follow(c, kind, i, y0)
			if lived >= SimConfig.ARRIVAL_FOLLOW:
				return n + lived
			best = maxi(best, lived)
	return n + best


## Plays on: kind 0 aims for the gap (or exit) on the wall ahead, kind 1 holds
## a height near where the bird came in.
static func _follow(sim: GameSim, kind: int, i: int, y0: int) -> int:
	var n := 0
	while n < SimConfig.ARRIVAL_FOLLOW:
		var target: int = y0 + HOLD_SHIFTS[i]
		if kind == 0:
			target = gap_target(sim) + OFFSETS[i]
		sim.step(_toward(sim, target))
		if sim.is_over():
			return n
		n += 1
	return n


## Tap when the bird has sunk past `target` (with gravity) and isn't rising.
static func _toward(sim: GameSim, target: int) -> bool:
	var g := sim.room.def.gravity_sign
	return (sim.state.y - target) * g > 0 and sim.state.vy * g >= 0


## The middle of the widest gap on the wall the bird is heading to, or the
## open exit there.
static func gap_target(sim: GameSim) -> int:
	var s := sim.state
	var side := 1 if s.vx > 0 else 0
	if s.exit_open and s.exit_side == side:
		return s.exit_a_y
	var mask := sim.wall_mask(side)
	var best_start := 0
	var best_len := 0
	var run_start := 0
	var run_len := 0
	for slot in SimConfig.SLOT_COUNT:
		if RoomRules.has_slot(mask, slot):
			run_len = 0
			continue
		if run_len == 0:
			run_start = slot
		run_len += 1
		if run_len > best_len:
			best_len = run_len
			best_start = run_start
	if best_len == 0:
		return s.y
	var top := SimConfig.slot_center_y(best_start)
	return (top + SimConfig.slot_center_y(best_start + best_len - 1)) / 2
