class_name RoomRules
extends RefCounted
## Room kinds and side-wall spike generation. Part of the gameplay rules:
## changing these or the order of RNG draws needs a GAMEPLAY_VERSION bump.

## Each kind: [extra_spikes, guaranteed_gap_slots]
const KINDS: Array[Array] = [
	[0, 4],  # 0 Open
	[1, 4],  # 1 Crowded
	[1, 3],  # 2 Narrow
]


static func kind_count() -> int:
	return KINDS.size()


static func spike_count(score: int, kind: int) -> int:
	var n: int = SimConfig.BASE_SPIKES + score / SimConfig.POINTS_PER_EXTRA_SPIKE + KINDS[kind][0]
	var room_for_spikes: int = SimConfig.SLOT_COUNT - gap_size(kind)
	return mini(mini(n, SimConfig.MAX_SPIKES), room_for_spikes)


static func gap_size(kind: int) -> int:
	return KINDS[kind][1]


## Picks the room kind for the next room, never repeating the current one.
static func next_kind(rng: SimRng, current: int) -> int:
	var pick := rng.next_below(kind_count() - 1)
	return pick if pick < current else pick + 1


## Returns a bitmask of spiked slots for one wall.
## A run of gap_size(kind) consecutive slots is always left free.
static func generate_wall(rng: SimRng, score: int, kind: int) -> int:
	var gap := gap_size(kind)
	var gap_start := rng.next_below(SimConfig.SLOT_COUNT - gap + 1)
	var candidates: Array[int] = []
	for slot in SimConfig.SLOT_COUNT:
		if slot < gap_start or slot >= gap_start + gap:
			candidates.append(slot)
	var n := spike_count(score, kind)
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
