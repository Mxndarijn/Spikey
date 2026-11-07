extends TestCase


func test_bird_waits_until_first_tap() -> void:
	var sim := GameSim.new(1)
	for i in 120:
		sim.step(false)
	assert_false(sim.state.started)
	assert_eq(sim.state.x, SimConfig.BIRD_START_X)
	assert_eq(sim.state.y, SimConfig.BIRD_START_Y)
	assert_true(sim.state.alive)


func test_first_tap_starts_and_flaps() -> void:
	var sim := GameSim.new(1)
	sim.step(true)
	assert_true(sim.state.started)
	assert_true(GameSim.Event.START in sim.events)
	assert_true(GameSim.Event.FLAP in sim.events)
	assert_true(sim.state.y < SimConfig.BIRD_START_Y, "bird moves up after a flap")


func test_no_taps_falls_to_floor() -> void:
	var sim := GameSim.new(1)
	sim.step(true)
	while not sim.is_over() and sim.state.tick < 1000:
		sim.step(false)
	assert_true(sim.is_over())
	assert_eq(sim.state.death_cause, SimState.DeathCause.FLOOR)


func test_constant_tapping_hits_ceiling() -> void:
	var sim := GameSim.new(1)
	while not sim.is_over() and sim.state.tick < 1000:
		sim.step(true)
	assert_eq(sim.state.death_cause, SimState.DeathCause.CEILING)


func test_wall_bounce_scores_and_spawns_spikes_ahead() -> void:
	var sim := GameSim.new(3)
	sim.step(true)
	var bounced := false
	while not bounced and sim.state.alive and sim.state.tick < 500:
		# Hover near the middle so the bird reaches the empty first wall.
		sim.step(sim.state.y > SimConfig.BIRD_START_Y and sim.state.vy >= 0)
		bounced = GameSim.Event.BOUNCE in sim.events
	assert_true(bounced, "bird reached the right wall")
	assert_eq(sim.state.score, 1)
	assert_true(sim.state.vx < 0, "now heading left")
	assert_eq(sim.state.right_spikes, 0)
	assert_ne(sim.state.left_spikes, 0)


func test_dead_sim_ignores_steps() -> void:
	var sim := GameSim.new(1)
	sim.step(true)
	while not sim.is_over():
		sim.step(false)
	var tick := sim.state.tick
	var sum := sim.checksum()
	sim.step(true)
	assert_eq(sim.state.tick, tick)
	assert_eq(sim.checksum(), sum)
	assert_true(sim.events.is_empty())


func test_same_inputs_same_checksum() -> void:
	var a := SimBots.play(777, SimBots.gap_seeker, 5)
	var b := SimBots.play(777, SimBots.gap_seeker, 5)
	assert_eq(a.checksum, b.checksum)
	assert_eq(a.taps, b.taps)
