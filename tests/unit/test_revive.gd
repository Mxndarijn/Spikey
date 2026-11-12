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


func test_an_open_exit_is_the_rooms_planned_exit_on_the_wall_behind() -> void:
	for side: int in [0, 1]:
		var sim := _revived_with_exit("open", side)
		var s := sim.state
		var behind := 0 if s.vx > 0 else 1
		var wall := sim.room.wall_left() if behind == 0 else sim.room.wall_right()
		assert_true(s.exit_open, "wall %d: still open" % side)
		assert_eq(s.exit_side, behind, "wall %d: on the wall it came in by" % side)
		var planned := s.plan_a_y_left if behind == 0 else s.plan_a_y_right
		assert_eq(s.exit_a_y, planned, "wall %d: where the room planned it" % side)
		assert_eq(sim.wall_mask(behind) & ExitPlanner.slots(s), 0, "wall %d: no spike in it" % side)
		assert_eq(
			sim.wall_mask(behind) & sim._slots_level_with(s.y),
			0,
			"wall %d: no spike level with the bird at its portal" % side
		)
		assert_true(absi(s.x - wall) <= SimConfig.BIRD_RADIUS + 1, "wall %d: at its portal" % side)


## Shutter Gates: the exit stays the room's planned one, and the bird comes
## out of its portal with no spike level with it on the wall it came in by.
func test_an_open_exit_in_shutter_gates_stays_planned() -> void:
	var sim := BotSetups.gates_revived(101, true, 0, SimConfig.slot_center_y(1))
	var s := sim.state
	var behind := 0 if s.vx > 0 else 1
	var wall := sim.room.wall_left() if behind == 0 else sim.room.wall_right()
	assert_true(s.exit_open)
	assert_eq(s.exit_side, behind, "on the wall it came in by")
	assert_eq(s.exit_a_y, s.plan_a_y_left if behind == 0 else s.plan_a_y_right, "as planned")
	assert_true(absi(s.x - wall) <= SimConfig.BIRD_RADIUS + 1, "at its portal")
	assert_eq(sim.wall_mask(behind) & sim._slots_level_with(s.y), 0, "no spike level with it")
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


## Same seed, a revive at two different moments of one room (and none at
## all): the room's planned exits, and the exit that then shows, are the same.
func test_a_revive_never_moves_the_rooms_exits() -> void:
	var start := GameSim.new(2024)
	var rng := SimRng.new(1)
	while not start.is_over() and start.state.room_index < 1:
		start.step(SimBots.gap_seeker(start, rng))
	assert_eq(start.state.room_index, 1, "the bot reached room 1")
	var plan := _plan(start.state)
	var shown: Array = []
	for die_after: int in [5, 300, 600]:
		var sim := SimCopy.copy(start)
		var bot := SimRng.new(3)
		for i in die_after:
			if sim.is_over():
				break
			sim.step(SimBots.gap_seeker(sim, bot))
		if sim.state.room_index != 1:
			continue
		var at_death := sim.state.exit_open or sim.state.exit_preview
		while not sim.is_over():
			sim.step(false)
		assert_true(sim.revive(), "revived after %d ticks" % die_after)
		assert_eq(_plan(sim.state), plan, "after %d ticks: the room's exits as planned" % die_after)
		if at_death:
			var s := sim.state
			var planned := s.plan_a_y_left if s.exit_side == 0 else s.plan_a_y_right
			assert_eq(s.exit_a_y, planned, "after %d ticks: the exit shown is planned" % die_after)
		# Fly on to the ghost: it shows where the room planned it.
		var bot2 := SimRng.new(5)
		for i in 1200:
			if sim.is_over() or sim.state.exit_preview or sim.state.room_index != 1:
				break
			sim.step(SimBots.gap_seeker(sim, bot2))
		if sim.state.exit_preview:
			var s := sim.state
			var planned := s.plan_a_y_left if s.exit_side == 0 else s.plan_a_y_right
			assert_eq(s.exit_a_y, planned, "after %d ticks: the ghost is planned" % die_after)
			shown.append(s.exit_a_y)
	assert_true(shown.size() >= 1, "a revived bot reached the ghost")


static func _plan(s: SimState) -> Array[int]:
	return [
		s.plan_at,
		s.plan_a_y_left,
		s.plan_a_kind_left,
		s.plan_b_y_left,
		s.plan_a_y_right,
		s.plan_a_kind_right,
		s.plan_b_y_right
	]
