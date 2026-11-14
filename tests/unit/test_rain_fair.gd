extends TestCase
## Spike Rain keeps a fair way past its drops: the wall the bird flies to keeps
## a free run no drop falls past in front of the bird as it gets there.

const RoomsTest := preload("res://tests/unit/test_rooms.gd")

const SUB := SimConfig.SUB
const ALL := (1 << SimConfig.SLOT_COUNT) - 1


## Longest run of slots that are free in `mask` and set in `ok`.
static func _free_ok(mask: int, ok: int) -> int:
	return RoomRules.longest_gap(mask | (ALL & ~ok))


static func _dist2(dx: int, dy: int) -> int:
	return dx * dx + dy * dy


## Spike Rain: the wall the bird flies to keeps a run of free heights no drop
## falls past in front of the bird while it gets there and turns (the drops'
## columns come from their own RNG, so a copy played forward meets them), and
## working that out leaves the drops as they were.
func test_a_wall_keeps_a_way_past_the_spike_rain() -> void:
	var checked := 0
	var moved := 0
	for variant: String in ["classic", "drizzle", "hail", "sweep", "shatter", "wobble", "stake"]:
		for seed_value in range(1, 4):
			var sim := RoomsTest.sim_in_room("rain", seed_value, Seasons.NONE, variant)
			var drops: Array[Hazard] = []
			for h in sim.room.hazards:
				if h.kind == "drop":
					drops.append(h)
			for k: int in range(0, 600, 41):
				for i in 41:
					for h in drops:
						h.step(sim)
				sim.state.x = (40 + k % 280) * SUB
				sim.state.vx = SimConfig.SPEED_X if k % 2 == 0 else -SimConfig.SPEED_X
				var side := 1 if sim.state.vx > 0 else 0
				var blocked := _rain_blocked(sim, side)
				var safe := ALL & ~blocked
				var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
				var sums: Array[int] = []
				for h in drops:
					sums.append(h.checksum(0))
				for gap_start: int in [0, 4, 9]:
					var mask := ALL & ~(0b1111 << gap_start)
					var out: int = drops[0].adjust_wall(sim, side, mask)
					assert_true(
						_free_ok(out, safe) >= need,
						"%s seed %d step %d run %d" % [variant, seed_value, k, gap_start]
					)
					if out != mask:
						moved += 1
					for i in range(1, drops.size()):
						assert_eq(
							drops[i].adjust_wall(sim, side, mask), mask, "the first drop does it"
						)
					checked += 1
				for i in drops.size():
					assert_eq(drops[i].checksum(0), sums[i], "%s: the drop is put back" % variant)
	assert_true(checked > 300)
	assert_true(moved > 0, "some walls had to make way")


## Heights by wall `side` a drop comes within 4 px of the bird, from 30 steps
## before the bird gets there to 12 after: every drop of a copy of the room
## stepped forward on its own clock.
static func _rain_blocked(sim: GameSim, side: int) -> int:
	var at := sim.steps_to_wall(side)
	var r := SimConfig.BIRD_RADIUS
	var edge := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	var into := -1 if side == 1 else 1
	var copy := SimCopy.copy(sim)
	var out := 0
	for k in range(1, at + 13):
		for h in copy.room.hazards:
			if h.kind != "drop":
				continue
			h.step(copy)
			var d := k - at
			if d < -30 or not h.falling():
				continue
			var bx := edge + into * absi(d) * SimConfig.SPEED_X
			var reach: int = h.radius + r + 4 * SUB
			for slot in SimConfig.SLOT_COUNT:
				if _dist2(bx - h.x, SimConfig.slot_center_y(slot) - h.y) < reach * reach:
					out |= 1 << slot
	return out
