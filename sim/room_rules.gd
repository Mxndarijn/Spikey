class_name RoomRules
extends RefCounted
## Side-wall spike generation, from a room's RoomDef. Part of the gameplay
## rules: changing these or the order of RNG draws needs a GAMEPLAY_VERSION bump.

## How far (centre to centre) the free run may be from the bird in a room with
## hazards: they can stop the bird crossing the room's full height in one trip.
const GAP_REACH := 200 * SimConfig.SUB


## Spikes per wall. `bonus` is the room variant's extra (or fewer) spikes; a
## spiked room always keeps at least one.
static func spike_count(score: int, def: RoomDef, bonus: int = 0) -> int:
	if not def.spikes:
		return 0
	var n := SimConfig.BASE_SPIKES + score / SimConfig.POINTS_PER_EXTRA_SPIKE + def.extra_spikes
	var room_for_spikes := SimConfig.SLOT_COUNT - def.gap
	return maxi(mini(mini(n, def.max_spikes) + bonus, room_for_spikes), 1)


## How far the free run may be from the bird in this room (0 = anywhere).
static func gap_reach(def: RoomDef) -> int:
	if def.reach > 0:
		return def.reach
	# Squeeze Box: the walls close in, so a crossing can be too short to reach
	# a free run anywhere on the wall.
	if not def.hazards.is_empty() or not def.combos.is_empty() or def.squeeze:
		return GAP_REACH
	# Rooms that keep their hazards only in variants count too (a generated
	# variant builds its hazards from its recipe).
	for variant: RoomVariant in def.variants:
		if not variant.hazards.is_empty() or variant.kind == RoomVariant.Kind.GENERATED:
			return GAP_REACH
	return 0


## Returns a bitmask of spiked slots for one wall.
## A run of `def.gap` consecutive slots is always left free. With a known bird
## height `bird_y`, that run is within gap_reach(def) of it (or `p_reach`,
## when that is 0 or more).
static func generate_wall(
	rng: SimRng, score: int, def: RoomDef, bird_y: int = -1, bonus: int = 0, p_reach: int = -1
) -> int:
	return generate_wall_run(rng, score, def, bird_y, bonus, p_reach)[0]


## generate_wall, with the free run it kept: [mask, start, lo, hi], `start`
## the run's first slot, drawn from `lo` to `hi` (the starts the reach
## allowed). -1s when the wall has no spikes. The same draws.
static func generate_wall_run(
	rng: SimRng, score: int, def: RoomDef, bird_y: int = -1, bonus: int = 0, p_reach: int = -1
) -> Array[int]:
	var n := spike_count(score, def, bonus)
	if n == 0:
		return [0, -1, -1, -1]
	var gap := def.gap
	var lo := 0
	var hi := SimConfig.SLOT_COUNT - gap
	var reach := gap_reach(def) if p_reach < 0 else p_reach
	if bird_y >= 0 and reach > 0:
		var first := hi
		var last := lo
		for start in range(lo, hi + 1):
			var center := SimConfig.slot_center_y(start) + (gap - 1) * SimConfig.SLOT_SIZE / 2
			if absi(center - bird_y) <= reach:
				first = mini(first, start)
				last = maxi(last, start)
		if first <= last:
			lo = first
			hi = last
	var gap_start := lo + rng.next_below(hi - lo + 1)
	var candidates: Array[int] = []
	for slot in SimConfig.SLOT_COUNT:
		if slot < gap_start or slot >= gap_start + gap:
			candidates.append(slot)
	var mask := 0
	for i in n:
		var j := i + rng.next_below(candidates.size() - i)
		var picked := candidates[j]
		candidates[j] = candidates[i]
		candidates[i] = picked
		mask |= 1 << picked
	return [mask, gap_start, lo, hi]


static func has_slot(mask: int, slot: int) -> bool:
	return (mask >> slot) & 1 == 1


## Longest run of free slots in a wall mask.
static func longest_gap(mask: int) -> int:
	var best := 0
	var run := 0
	for slot in SimConfig.SLOT_COUNT:
		if has_slot(mask, slot):
			run = 0
		else:
			run += 1
			best = maxi(best, run)
	return best


## The slots of the first longest run of free slots in a wall mask.
static func longest_gap_mask(mask: int) -> int:
	var best := 0
	var best_end := 0
	var run := 0
	for slot in SimConfig.SLOT_COUNT:
		if has_slot(mask, slot):
			run = 0
		else:
			run += 1
			if run > best:
				best = run
				best_end = slot
	var out := 0
	for slot in range(best_end - best + 1, best_end + 1):
		out |= 1 << slot
	return out


## `mask` if it has a run of `need` free slots all in `ok` (a slot mask);
## else `mask` with the run of `need` slots of `ok` nearest the middle of its
## free run cleared (unchanged if `ok` has no such run). No RNG draws.
static func keep_run(mask: int, need: int, ok: int) -> int:
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	if need <= 0 or longest_gap(mask | (all & ~ok)) >= need:
		return mask
	var free := longest_gap_mask(mask)
	var mid := 0
	var n := 0
	for slot in SimConfig.SLOT_COUNT:
		if (free >> slot) & 1 == 1:
			mid += SimConfig.slot_center_y(slot)
			n += 1
	if n > 0:
		mid /= n
	var best := -1
	var best_d := 0
	var span := (1 << need) - 1
	for start in SimConfig.SLOT_COUNT - need + 1:
		if (ok >> start) & span != span:
			continue
		var y := SimConfig.slot_center_y(start) + (need - 1) * SimConfig.SLOT_SIZE / 2
		var d := absi(y - mid)
		if best < 0 or d < best_d:
			best = start
			best_d = d
	if best < 0:
		return mask
	return mask & ~(span << best)
