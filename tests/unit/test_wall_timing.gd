extends TestCase
## A bounce off a wall draws that wall's next spikes at once, sliding out as
## the bird leaves (about two crossings to see them); the wall ahead keeps the
## spikes it got at the bounce before. A new spike only kills as far as it
## has slid all the way out (GameSim.SPIKE_SLIDE), and never a bird still
## flying away from its wall.

const MID_Y := (SimConfig.KILL_TOP + SimConfig.KILL_BOTTOM) / 2
const ALL := (1 << SimConfig.SLOT_COUNT) - 1


static func _sim(seed_value: int = 5) -> GameSim:
	var index := RoomCatalog.index_of("open")
	return GameSim.new(seed_value, RoomCatalog.all()[index].season, index)


static func _mask(sim: GameSim, side: int) -> int:
	return sim.state.left_spikes if side == 0 else sim.state.right_spikes


## Flies level in the middle (the bird can't die) until the next wall bounce;
## returns the wall bounced off.
static func _to_bounce(sim: GameSim) -> int:
	var walls := sim.room.walls
	var heading := 1 if sim.state.vx > 0 else 0
	for i in 400:
		sim.state.alive = true
		sim.state.y = MID_Y
		sim.state.vy = 0
		sim.step(false)
		if sim.room.walls != walls:
			return heading
	return -1


func test_a_bounce_draws_the_wall_just_left_and_keeps_the_wall_ahead() -> void:
	var sim := _sim()
	sim.step(true)
	var side := _to_bounce(sim)
	assert_true(side >= 0, "a bounce")
	assert_eq(sim.room.walls, 2, "the first bounce draws both walls")
	assert_true(_mask(sim, side) != 0, "the wall just left has its next spikes")
	assert_true(_mask(sim, 1 - side) != 0, "the wall ahead has spikes")
	for i in 6:
		var ahead := _mask(sim, side)
		side = _to_bounce(sim)
		assert_true(side >= 0, "bounce %d" % i)
		assert_eq(_mask(sim, 1 - side), ahead, "the wall ahead is the one shown since before")
		var drawn := sim.state.left_drawn if side == 0 else sim.state.right_drawn
		assert_eq(drawn, sim.room.t, "the wall just left is drawn at the bounce")


func test_a_new_spike_kills_only_once_it_is_all_the_way_out() -> void:
	var sim := _sim()
	var r := SimConfig.BIRD_RADIUS
	var wall := sim.room.wall_right()
	sim.state.right_spikes = ALL
	sim.state.right_new = ALL
	sim.state.right_drawn = sim.room.t
	sim.state.y = SimConfig.slot_center_y(6)
	sim.state.vx = SimConfig.SPEED_X
	# Half a spike deep: hit once the spike is all the way out.
	sim.state.x = wall - r - sim.room.spike_depth() / 2
	assert_false(sim._hits_wall(1, wall, -1), "just drawn: still in the wall")
	sim.room.t += GameSim.SPIKE_SLIDE - 1
	assert_false(sim._hits_wall(1, wall, -1), "nearly out")
	sim.room.t += 1
	assert_true(sim._hits_wall(1, wall, -1), "all the way out")
	# A spike that was already there is out at once.
	sim.state.right_new = 0
	sim.state.right_drawn = sim.room.t
	assert_true(sim._hits_wall(1, wall, -1), "a kept spike")


func test_new_spikes_never_kill_a_bird_flying_away_from_their_wall() -> void:
	var sim := _sim()
	var r := SimConfig.BIRD_RADIUS
	var wall := sim.room.wall_right()
	sim.state.right_spikes = ALL
	sim.state.right_new = ALL
	sim.state.right_drawn = sim.room.t
	sim.room.t += 5 * GameSim.SPIKE_SLIDE
	sim.state.y = SimConfig.slot_center_y(6)
	# A wall that closed in on the bird (Narrow Cage, Squeeze Box).
	sim.state.x = wall - r
	sim.state.vx = -SimConfig.SPEED_X
	assert_false(sim._hits_wall(1, wall, -1), "flying away")
	sim.state.vx = SimConfig.SPEED_X
	assert_true(sim._hits_wall(1, wall, -1), "heading back to it")


func test_a_bump_back_sends_the_wall_just_left_back_in() -> void:
	var sim := _sim()
	sim.step(true)
	var side := _to_bounce(sim)
	var ahead := _mask(sim, 1 - side)
	assert_true(_mask(sim, side) != 0, "the wall just left shows its next spikes")
	# Bumped back from in front: it flies to the wall it just left.
	var dir := 1 if sim.state.vx > 0 else -1
	sim.bump_bird_from(sim.state.x + dir * SimConfig.SUB, sim.state.y)
	assert_eq(1 if sim.state.vx > 0 else 0, side, "turned back")
	assert_eq(_mask(sim, side), 0, "laid out for later: back in the wall")
	assert_eq(_mask(sim, 1 - side), ahead, "the other wall keeps its spikes")
