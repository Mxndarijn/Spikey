extends TestCase
## SimConfig.TAP_GAP: a tap fewer than TAP_GAP ticks after the last flap is
## dropped, so nobody (player or bot) double jumps.


## A run started by a flap at tick 0, then `n` ticks without a tap.
func _flapped(n: int) -> GameSim:
	var sim := GameSim.new(11)
	sim.step(true)
	for i in n:
		sim.step(false)
	return sim


func test_a_tap_inside_the_gap_does_nothing() -> void:
	for wait in SimConfig.TAP_GAP - 1:
		var sim := _flapped(wait)
		var other := _flapped(wait)
		assert_false(sim.state.can_flap(), "gap %d" % (wait + 1))
		sim.step(true)
		other.step(false)
		assert_false(sim.events.has(GameSim.Event.FLAP), "gap %d flapped" % (wait + 1))
		assert_eq(sim.state.flaps, 1)
		assert_eq(sim.checksum(), other.checksum(), "gap %d: same as no tap" % (wait + 1))


func test_a_tap_at_the_end_of_the_gap_flaps() -> void:
	var sim := _flapped(SimConfig.TAP_GAP - 1)
	assert_eq(sim.state.tick, SimConfig.TAP_GAP)
	assert_true(sim.state.can_flap())
	sim.step(true)
	assert_true(sim.events.has(GameSim.Event.FLAP))
	assert_eq(sim.state.flaps, 2)
	assert_eq(sim.state.flap_tick, SimConfig.TAP_GAP)


func test_a_dropped_tap_does_not_restart_the_gap() -> void:
	var sim := _flapped(1)
	sim.step(true)
	for i in SimConfig.TAP_GAP - 3:
		sim.step(false)
	assert_eq(sim.state.tick, SimConfig.TAP_GAP)
	sim.step(true)
	assert_eq(sim.state.flaps, 2)


func test_the_first_tap_always_flaps() -> void:
	var sim := GameSim.new(11)
	assert_true(sim.state.can_flap())
	sim.step(true)
	assert_true(sim.events.has(GameSim.Event.FLAP))


## Out of a portal the bird comes out level and can flap at once (vy is 0, so
## nothing stacks), and the room it meets is the same whenever it last flapped.
func test_out_of_a_portal_the_bird_can_flap_at_once() -> void:
	var recent := _flapped(1)
	var long_ago := SimCopy.copy(recent)
	long_ago.state.flap_tick = -100
	recent._go_through(1, SimState.ExitKind.NORMAL, 320 * SimConfig.SUB)
	long_ago._go_through(1, SimState.ExitKind.NORMAL, 320 * SimConfig.SUB)
	assert_true(recent.state.can_flap())
	assert_eq(long_ago.checksum(), recent.checksum())


func test_a_replay_drops_the_same_taps() -> void:
	var taps := PackedInt32Array([0, 2, 6, 7, 30])
	var sim := Replay.simulate(11, taps, Seasons.NONE)
	var kept := Replay.simulate(11, PackedInt32Array([0, 6, 30]), Seasons.NONE)
	assert_eq(sim.state.flaps, 3)
	assert_eq(sim.checksum(), kept.checksum())
