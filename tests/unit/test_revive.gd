extends TestCase
## Revive (GameSim.revive, gameplay version 15): once per run a dead bird
## arrives in the same room again as if through a portal, and the run goes on.


## A real run the gap seeker played for `active` ticks and then let fall.
func _dead(seed_value: int = 4242, active: int = 1500) -> GameSim:
	var sim := GameSim.new(seed_value)
	var rng := SimRng.new(3)
	while not sim.is_over():
		sim.step(sim.state.tick < active and SimBots.gap_seeker(sim, rng))
	return sim


func test_revive_brings_the_bird_back_in_the_same_room() -> void:
	var sim := _dead()
	var before := sim.state.copy()
	assert_true(before.score > 0, "the bot scored before it died")
	assert_true(sim.can_revive())
	assert_true(sim.revive())
	var s := sim.state
	assert_true(s.alive)
	assert_eq(s.death_cause, SimState.DeathCause.NONE)
	assert_eq(s.revives, 1)
	assert_eq(sim.events[0], GameSim.Event.REVIVE, "the view hears about it first")
	assert_eq(s.tick, before.tick, "a revive takes no time")
	assert_eq(s.score, before.score)
	assert_eq(s.coins, before.coins)
	assert_eq(s.room_index, before.room_index)
	assert_eq(s.room_kind, before.room_kind, "the same room again")
	assert_eq(s.y, SimConfig.BIRD_START_Y, "at mid height")
	assert_eq(s.vy, 0, "flying level")
	assert_eq(s.arrival_hold, SimConfig.ARRIVAL_HOLD, "it waits like out of a portal")
	assert_eq(sim.room.t, 0, "the room starts fresh")


func test_the_run_goes_on_after_a_revive() -> void:
	var sim := _dead()
	var score := sim.state.score
	sim.revive()
	var rng := SimRng.new(5)
	for i in 900:
		sim.step(SimBots.gap_seeker(sim, rng))
		if sim.is_over():
			break
	assert_true(sim.state.score > score, "the bot scores again after the revive")


func test_only_a_dead_bird_in_a_real_run_revives_and_only_once() -> void:
	var alive := GameSim.new(1)
	alive.step(true)
	var sum := alive.checksum()
	assert_false(alive.can_revive())
	assert_false(alive.revive(), "not while alive")
	assert_eq(alive.checksum(), sum, "nothing changed")

	var sim := _dead()
	assert_true(sim.revive())
	while not sim.is_over():
		sim.step(false)
	sum = sim.checksum()
	assert_false(sim.can_revive())
	assert_false(sim.revive(), "one revive per run")
	assert_eq(sim.checksum(), sum, "nothing changed")
	assert_true(sim.is_over())

	var practice := GameSim.new(1, Seasons.NONE, RoomCatalog.first_index())
	practice.step(true)
	practice.kill(SimState.DeathCause.FLOOR)
	assert_false(practice.revive(), "practice has no revive")


func test_the_bird_keeps_flying_the_way_it_was_going() -> void:
	for dir: int in [1, -1]:
		var sim := _dead()
		sim.state.exit_open = false
		sim.state.exit_preview = false
		sim.state.vx = dir * SimConfig.SPEED_X
		sim.revive()
		_expect_start(sim, 1 if dir > 0 else 0, "no exit, flying %d" % dir)


func test_the_bird_faces_an_open_exit() -> void:
	for side: int in [0, 1]:
		var sim := _dead()
		sim.state.exit_preview = false
		sim.state.exit_open = true
		sim.state.exit_side = side
		sim.state.exit_a_y = SimConfig.slot_center_y(4)
		# Flying away from it when it died (say off a bumper).
		sim.state.vx = SimConfig.SPEED_X if side == 0 else -SimConfig.SPEED_X
		sim.revive()
		_expect_start(sim, side, "exit open on %d" % side)
		assert_true(sim.state.exit_open, "the exit stays open")
		assert_eq(sim.state.exit_a_y, SimConfig.slot_center_y(4), "where it was")


func test_the_bird_starts_with_its_back_to_a_ghost_exit() -> void:
	for side: int in [0, 1]:
		var sim := _dead()
		sim.state.exit_open = false
		sim.state.exit_preview = true
		sim.state.exit_side = side
		sim.state.exit_a_y = SimConfig.slot_center_y(6)
		sim.revive()
		_expect_start(sim, 1 - side, "ghost on %d" % side)
		assert_true(sim.state.exit_preview, "still a ghost")
		assert_false(sim.state.exit_open)


## The revived bird sits at the wall opposite `toward`, flying toward it.
func _expect_start(sim: GameSim, toward: int, what: String) -> void:
	var r := SimConfig.BIRD_RADIUS
	if toward == 1:
		assert_true(sim.state.vx > 0, "%s: flies right" % what)
		assert_eq(sim.state.x, sim.room.wall_left() + r, "%s: at the left wall" % what)
		assert_eq(sim.state.left_spikes, 0, "%s: no spikes behind it" % what)
	else:
		assert_true(sim.state.vx < 0, "%s: flies left" % what)
		assert_eq(sim.state.x, sim.room.wall_right() - r, "%s: at the right wall" % what)
		assert_eq(sim.state.right_spikes, 0, "%s: no spikes behind it" % what)


func test_revived_runs_are_deterministic() -> void:
	var a := SimBots.play_revived(77, SimBots.gap_seeker, 2, 1200, 900)
	var b := SimBots.play_revived(77, SimBots.gap_seeker, 2, 1200, 900)
	assert_eq(a.revive_ticks.size(), 1)
	assert_eq(a.checksum, b.checksum)
	assert_eq(a.end_tick, b.end_tick)
	assert_true(
		a.end_tick > a.revive_ticks[0] + SimConfig.ARRIVAL_HOLD, "it flew on after the wait"
	)
