extends TestCase
## Every exit and its ghost are on the right wall (SimConfig.EXIT_WALL), so a
## bird the Bumper Cloud turned back leaves each room the same way as every
## other player of the seed, and they meet the same rooms after it.

const Portals := preload("res://tests/unit/test_portals.gd")


# Turned back an odd number of times (Bumper Cloud), the bird bounces off the
# left wall at 9: the ghost is still on the right wall, ahead of it, and every
# player of the seed leaves the room there.
func test_ghost_and_exit_stay_on_the_right_wall_after_a_turn_back() -> void:
	for seed_value in 6:
		var sim := Portals._sim_at(8, seed_value)
		var straight := Portals._sim_at(8, seed_value)
		Portals._hit_wall(straight, 1, 300 * SimConfig.SUB)
		Portals._hit_wall(sim, 0, 300 * SimConfig.SUB)
		var s := sim.state
		assert_eq(s.score, 9)
		assert_true(s.exit_preview, "a ghost at 9")
		assert_eq(s.exit_side, 1, "on the right wall, ahead of the bird")
		assert_eq(s.exit_a_y, straight.state.exit_a_y, "where every player meets it")
		var y := s.exit_a_y
		var room_before := s.room_index
		Portals._hit_wall(sim, 1, y)
		assert_eq(s.room_index, room_before, "no way through a ghost")
		assert_eq(s.score, 10)
		assert_true(s.exit_open, "it opens at 10")
		assert_eq(s.exit_side, 1, "still on the right wall, behind the bird")
		Portals._hit_wall(sim, 0, 300 * SimConfig.SUB)
		assert_eq(s.score, 10, "no points while the exit is open")
		Portals._hit_wall(sim, 1, y)
		assert_eq(s.room_index, room_before + 1, "coming back, it leads through")
		Portals._hit_wall(straight, 0, 300 * SimConfig.SUB)
		Portals._hit_wall(straight, 1, y)
		assert_eq(straight.state.room_index, room_before + 1)
		assert_eq(s.room_kind, straight.state.room_kind, "seed %d: same room" % seed_value)
		assert_eq(sim.room.variant_id(), straight.room.variant_id())
		assert_eq(s.anchor_y, straight.state.anchor_y)
		assert_true(s.vx > 0, "out of the left wall, heading right")
