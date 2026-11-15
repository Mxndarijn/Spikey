extends TestCase
## The last bounces before an exit steer each new wall's free run toward the
## exit. The run still stays within reach of every free spot of the other wall
## (the one met first), wherever the bird comes off it. Seed 10058's Spike Rain:
## a steered run sat 246 px above the low run the bird left, with drops falling
## in between.

const RoomsTest := preload("res://tests/unit/test_rooms.gd")

const ALL := (1 << SimConfig.SLOT_COUNT) - 1


## Free slots `lo`..`hi` (inclusive), every other slot spiked.
static func _open(lo: int, hi: int) -> int:
	var free := 0
	for slot in range(lo, hi + 1):
		free |= 1 << slot
	return ALL & ~free


func test_a_steered_wall_stays_in_reach_of_the_whole_wall_before() -> void:
	var reach := RoomRules.GAP_REACH
	var gap := RoomCatalog.find("rain").gap
	var top := SimConfig.slot_center_y(9)
	var bottom := SimConfig.slot_center_y(12)
	var drawn := 0
	for seed_value in range(1, 201):
		var sim := RoomsTest.sim_in_room("rain", seed_value, Seasons.NONE, "classic")
		# Two points before the exit, planned high on the exit wall: walls steer up.
		sim.state.score = sim.next_exit_score() - 2
		sim.state.plan_a_y_right = SimConfig.slot_center_y(1)
		sim.state.plan_a_kind_right = SimState.ExitKind.NORMAL
		# The wall met first (right) is free only low down.
		sim.state.right_spikes = _open(9, 12)
		sim.room.walls = 1
		sim._new_wall(0, false)
		var start := sim.wall_run[0]
		if start < 0:
			continue
		drawn += 1
		var center := SimConfig.slot_center_y(start) + (gap - 1) * SimConfig.SLOT_SIZE / 2
		assert_true(
			center >= bottom - reach and center <= top + reach,
			(
				"seed %d: run at %d px, the wall before free %d..%d px"
				% [seed_value, center / SimConfig.SUB, top / SimConfig.SUB, bottom / SimConfig.SUB]
			)
		)
	assert_true(drawn > 100, "walls with spikes drawn")
