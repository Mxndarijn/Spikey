extends TestCase
## Revive (GameSim.revive): once per run a dead bird gets the room back as it
## came into it, at the portal it came through, and the run goes on.


## A real run the gap seeker played for `active` ticks and then let fall.
## `entered` (if given) gets a copy of the sim just after its last portal.
func _dead(seed_value: int = 4242, active: int = 1500, entered: Array = []) -> GameSim:
	var sim := GameSim.new(seed_value)
	var rng := SimRng.new(3)
	while not sim.is_over():
		sim.step(sim.state.tick < active and SimBots.gap_seeker(sim, rng))
		if GameSim.Event.ROOM_CHANGE in sim.events and sim.state.alive:
			entered.clear()
			entered.append(SimCopy.copy(sim))
	return sim


func test_revive_restarts_the_room_as_the_bird_came_in() -> void:
	var entered := []
	var sim := _dead(4242, 1500, entered)
	assert_eq(entered.size(), 1, "the bot went through a portal")
	var came: GameSim = entered[0]
	var before := sim.state.copy()
	assert_true(before.score > 0, "the bot scored before it died")
	assert_true(sim.room.t > 0, "the room had moved on")
	assert_true(sim.can_revive())
	assert_true(sim.revive())
	var s := sim.state
	assert_true(s.alive)
	assert_eq(s.death_cause, SimState.DeathCause.NONE)
	assert_eq(s.revives, 1)
	assert_eq(sim.events[0], GameSim.Event.REVIVE, "the view hears about it")
	assert_eq(s.tick, before.tick, "a revive takes no time")
	assert_eq(s.score, before.score)
	assert_eq(s.coins, before.coins)
	assert_eq(s.room_index, before.room_index)
	# `came` is a copy made at the end of the arrival's tick; the room it keeps
	# for a revive was taken in that tick, right out of the portal.
	var kept: RoomRuntime = came._entry_room
	var at: SimState = came._entry_state
	assert_eq(s.room_kind, came.state.room_kind, "the same room again")
	assert_eq(sim.room.variant, came.room.variant, "the same variant")
	assert_eq(sim.room.hazards.size(), came.room.hazards.size(), "the same hazards")
	assert_eq(sim.room.t, 0, "the room starts over")
	assert_eq(sim.room.checksum(0), kept.checksum(0), "hazards and walls as it came in")
	assert_eq(at.room_index, before.room_index, "kept at this room's portal")
	assert_eq(s.y, at.y, "at the height it came in at")
	assert_eq(s.vx, at.vx, "flying the way it came in")
	assert_true(absi(at.x - came.state.x) <= SimConfig.SPEED_X * 2, "kept right out of the portal")
	if not (s.exit_open and s.exit_side == (0 if s.vx > 0 else 1)):
		assert_eq(s.x, at.x, "at the portal it came through")
	assert_eq(s.vy, 0, "flying level")
	assert_eq(s.left_spikes, at.left_spikes, "the left wall as it came in")
	assert_eq(s.right_spikes, at.right_spikes, "the right wall as it came in")
	assert_eq(s.arrival_hold, SimConfig.ARRIVAL_HOLD, "it waits with the room frozen")


func test_without_an_exit_a_revive_draws_nothing_from_the_rng() -> void:
	var sim := _dead()
	sim.state.exit_open = false
	sim.state.exit_preview = false
	var rng := sim._rng.state_checksum()
	sim.revive()
	assert_eq(sim._rng.state_checksum(), rng)


func test_the_room_restarts_the_same_way_every_time() -> void:
	var a := _dead()
	var b := _dead()
	a.revive()
	b.revive()
	assert_eq(a.checksum(), b.checksum())


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


## A dead bird of _dead() with an exit of `kind` ("open" or "ghost") on wall
## `side`, then revived.
func _revived_with_exit(kind: String, side: int) -> GameSim:
	var sim := _dead()
	sim.state.exit_open = kind == "open"
	sim.state.exit_preview = kind == "ghost"
	sim.state.exit_side = side
	sim.state.exit_a_y = SimConfig.slot_center_y(4)
	sim.state.exit_b_kind = SimState.ExitKind.NORMAL
	sim.revive()
	return sim


func test_an_open_exit_is_the_portal_the_bird_comes_out_of() -> void:
	for side: int in [0, 1]:
		var sim := _revived_with_exit("open", side)
		var s := sim.state
		var behind := 0 if s.vx > 0 else 1
		assert_true(s.exit_open, "wall %d: still open" % side)
		assert_eq(s.exit_side, behind, "wall %d: on the wall it came in by" % side)
		assert_false(ExitPlanner.blocked(sim, s.exit_a_y), "wall %d: nothing blocks it" % side)
		assert_true(
			absi(s.exit_a_y - s.y) <= SimConfig.SLOT_SIZE / 2, "wall %d: at its height" % side
		)
		assert_eq(sim.wall_mask(behind) & ExitPlanner.slots(s), 0, "wall %d: no spike in it" % side)


## Shutter Gates block an exit at the height this bird came in at: the exit is
## planned elsewhere on that wall and the bird comes out clear of its spikes.
func test_an_open_exit_a_hazard_blocks_at_the_portal_is_planned_again() -> void:
	var sim := BotSetups.gates_revived(101, true, 0, SimConfig.slot_center_y(1))
	var s := sim.state
	var behind := 0 if s.vx > 0 else 1
	var wall := sim.room.wall_left() if behind == 0 else sim.room.wall_right()
	assert_true(s.exit_open)
	assert_eq(s.exit_side, behind, "on the wall it came in by")
	assert_false(ExitPlanner.blocked(sim, s.exit_a_y), "where nothing blocks it")
	assert_true(
		absi(s.x - wall) > SimConfig.BIRD_RADIUS + sim.room.max_spike_depth(),
		"the bird is clear of the spike tips"
	)
	for i in SimConfig.ARRIVAL_HOLD + 2:
		sim.step(false)
	assert_true(s.alive, "not killed by the wall it came in by")


func test_an_exit_ends_up_on_the_wall_behind_the_bird() -> void:
	for kind: String in ["open", "ghost"]:
		for side: int in [0, 1]:
			var sim := _revived_with_exit(kind, side)
			var what := "%s on wall %d" % [kind, side]
			var behind := 0 if sim.state.vx > 0 else 1
			assert_eq(sim.state.exit_open, kind == "open", "%s: still open or not" % what)
			assert_eq(sim.state.exit_preview, kind == "ghost", "%s: still a ghost or not" % what)
			assert_eq(sim.state.exit_side, behind, "%s: on the wall it came in by" % what)


func test_an_open_exit_leaves_the_bird_clear_of_the_spikes_behind_it() -> void:
	for side: int in [0, 1]:
		var sim := _revived_with_exit("open", side)
		for i in SimConfig.ARRIVAL_HOLD + 2:
			sim.step(false)
		assert_true(sim.state.alive, "wall %d: not killed by the wall it came in by" % side)


func test_a_revive_in_the_first_room_starts_where_the_run_did() -> void:
	var sim := GameSim.new(31)
	var start := sim.state.copy()
	var walls := sim.room.checksum(0)
	for i in 40:
		sim.step(i % 9 == 0)
	sim.kill(SimState.DeathCause.FLOOR)
	assert_true(sim.revive())
	assert_eq(sim.state.x, start.x)
	assert_eq(sim.state.y, start.y)
	assert_eq(sim.state.vx, start.vx)
	assert_eq(sim.room.checksum(0), walls, "the first room as the run began")


func test_revived_runs_are_deterministic() -> void:
	var a := SimBots.play_revived(77, SimBots.gap_seeker, 2, 1200, 900)
	var b := SimBots.play_revived(77, SimBots.gap_seeker, 2, 1200, 900)
	assert_eq(a.revive_ticks.size(), 1)
	assert_eq(a.checksum, b.checksum)
	assert_eq(a.end_tick, b.end_tick)
	assert_true(
		a.end_tick > a.revive_ticks[0] + SimConfig.ARRIVAL_HOLD, "it flew on after the wait"
	)
