extends TestCase
## Updraft: a wall's free run is kept near where the bird comes off the wall
## before. A free run down at the bottom counts from its middle, so a
## bottom-only wall doesn't pin every wall after it to the bottom too (seed
## 220's chimney: two bottom-only walls with the lift between them).

const RoomsTest := preload("res://tests/unit/test_rooms.gd")

const ALL := (1 << SimConfig.SLOT_COUNT) - 1
const N := SimConfig.SLOT_COUNT


static func _air(sim: GameSim) -> Hazard:
	for h in sim.room.hazards:
		if h.kind == "updraft":
			return h
	return null


## Free slots `lo`..`hi` (inclusive), every other slot spiked.
static func _open(lo: int, hi: int) -> int:
	var free := 0
	for slot in range(lo, hi + 1):
		free |= 1 << slot
	return ALL & ~free


static func _chimney() -> GameSim:
	var sim := RoomsTest.sim_in_room("updraft", 2, Seasons.NONE, "chimney")
	sim.state.x = SimConfig.BIRD_RADIUS
	sim.state.vx = SimConfig.SPEED_X
	return sim


## The bird comes off a wall at the bottom of its free run, or at the run's
## middle when the run reaches the lowest slots.
func test_the_bird_comes_off_a_bottom_run_at_its_middle() -> void:
	var sim := _chimney()
	var air := _air(sim)
	air.last_low = SimConfig.slot_center_y(5)
	air.adjust_wall(sim, 1, _open(4, 6))
	assert_eq(air.last_low, SimConfig.slot_center_y(6), "a run up the wall: its bottom")
	air.last_low = SimConfig.slot_center_y(N - 1)
	var out: int = air.adjust_wall(sim, 1, _open(N - 4, N - 1))
	assert_eq(out, _open(N - 4, N - 1), "already where the lifted bird gets")
	var mid := (SimConfig.slot_center_y(N - 4) + SimConfig.slot_center_y(N - 1)) / 2
	assert_eq(air.last_low, mid, "a run down to the floor: its middle")


## After a bottom-only wall the next wall's free run may sit higher up: it is
## not forced down to the lowest slot again.
func test_a_bottom_only_wall_does_not_pin_the_next_one_to_the_bottom() -> void:
	var sim := _chimney()
	var air := _air(sim)
	air.last_low = SimConfig.slot_center_y(N - 1)
	air.adjust_wall(sim, 1, _open(N - 4, N - 1))
	assert_true(air._gust_on_way(sim, 0), "the chimney lifts on the way")
	var out: int = air.adjust_wall(sim, 0, _open(7, 9))
	assert_true(RoomRules.has_slot(out, N - 1), "the lowest slot keeps its spike")
	var need := mini(sim.room.def.gap, 4)
	assert_true(RoomRules.longest_gap(out) >= need, "a whole free run")
