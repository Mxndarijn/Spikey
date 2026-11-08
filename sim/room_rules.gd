class_name RoomRules
extends RefCounted
## Side-wall spike generation, from a room's RoomDef. Part of the gameplay
## rules: changing these or the order of RNG draws needs a GAMEPLAY_VERSION bump.

## How far (centre to centre) the free run may be from the bird in a room with
## hazards: they can stop the bird crossing the room's full height in one trip.
const GAP_REACH := 200 * SimConfig.SUB


static func spike_count(score: int, def: RoomDef) -> int:
	if not def.spikes:
		return 0
	var n := SimConfig.BASE_SPIKES + score / SimConfig.POINTS_PER_EXTRA_SPIKE + def.extra_spikes
	var room_for_spikes := SimConfig.SLOT_COUNT - def.gap
	return mini(mini(n, def.max_spikes), room_for_spikes)


## Returns a bitmask of spiked slots for one wall.
## A run of `def.gap` consecutive slots is always left free. In rooms with
## hazards and a known bird height `bird_y`, that run is within GAP_REACH of it.
static func generate_wall(rng: SimRng, score: int, def: RoomDef, bird_y: int = -1) -> int:
	var n := spike_count(score, def)
	if n == 0:
		return 0
	var gap := def.gap
	var lo := 0
	var hi := SimConfig.SLOT_COUNT - gap
	if bird_y >= 0 and (not def.hazards.is_empty() or not def.combos.is_empty()):
		var first := hi
		var last := lo
		for start in range(lo, hi + 1):
			var center := SimConfig.slot_center_y(start) + (gap - 1) * SimConfig.SLOT_SIZE / 2
			if absi(center - bird_y) <= GAP_REACH:
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
	return mask


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
