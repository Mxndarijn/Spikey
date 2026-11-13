extends TestCase
## Revive (GameSim.revive): once per run a dead bird gets the room back as it
## came into it, at the portal it came through, with the score and coins it
## had then, and the run goes on as if it had never died there.


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
	assert_eq(s.room_index, before.room_index)
	# `came` is a copy made at the end of the arrival's tick; the room it keeps
	# for a revive was taken in that tick, right out of the portal.
	var kept: RoomRuntime = came._entry_room
	var at: SimState = came._entry_state
	assert_true(before.score > at.score, "the bot scored in this room")
	assert_eq(s.score, at.score, "the room's points are gone")
	assert_eq(s.coins, at.coins, "the room's coins are gone")
	assert_eq(s.flaps, before.flaps, "the taps carry on")
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
	assert_eq(s.vy, at.vy, "flying as it came in")
	assert_eq(s.left_spikes, at.left_spikes, "the left wall as it came in")
	assert_eq(s.right_spikes, at.right_spikes, "the right wall as it came in")
	assert_eq(s.arrival_hold, SimConfig.ARRIVAL_HOLD, "it waits with the room frozen")


## Everything but the tick, the revive count and the taps is as the bird came
## in: the rest of the run is the one a player who never died there meets.
func test_the_whole_state_and_the_rngs_are_as_the_bird_came_in() -> void:
	var entered := []
	var sim := _dead(4242, 1500, entered)
	var came: GameSim = entered[0]
	sim.revive()
	var want := came._entry_state.copy()
	want.tick = sim.state.tick
	want.revives = 1
	want.flaps = sim.state.flaps
	want.started = true
	want.arrival_hold = SimConfig.ARRIVAL_HOLD
	assert_eq(sim.state.checksum(), want.checksum(), "the state as it came in")
	assert_eq(sim._rng.state_checksum(), came._entry_rng.state_checksum(), "the room's RNG")
	assert_eq(sim._spine.state_checksum(), came._entry_spine.state_checksum(), "the run's RNG")
	assert_eq(sim.state.coin_active, want.coin_active, "the room's coin as it was")
	assert_eq(sim.state.exit_open, want.exit_open, "the exit as it was")
	assert_eq(sim.state.exit_preview, want.exit_preview, "the ghost as it was")


## An exit open or showing at the death is gone after the revive, unless the
## room had it when the bird came in: the score is back, and so is its exit.
func test_an_exit_at_the_death_goes_back_to_the_entry() -> void:
	for kind: String in ["open", "ghost"]:
		var entered := []
		var sim := _dead(4242, 1500, entered)
		var at: SimState = (entered[0] as GameSim)._entry_state
		sim.state.exit_open = kind == "open"
		sim.state.exit_preview = kind == "ghost"
		sim.state.exit_side = 1 - at.exit_side
		sim.revive()
		assert_eq(sim.state.exit_open, at.exit_open, kind)
		assert_eq(sim.state.exit_preview, at.exit_preview, kind)
		assert_eq(sim.state.exit_side, at.exit_side, kind)
		for i in SimConfig.ARRIVAL_HOLD + 2:
			sim.step(false)
		assert_true(sim.state.alive, "%s: the bird lives through the wait" % kind)


func test_the_room_restarts_the_same_way_every_time() -> void:
	var a := _dead()
	var b := _dead()
	a.revive()
	b.revive()
	assert_eq(a.checksum(), b.checksum())


func test_the_run_goes_on_after_a_revive() -> void:
	# A seed whose revived room the gap seeker gets through (the room deck).
	var sim := _dead(3)
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
	assert_eq(sim.state.score, 0, "no points yet")
	for i in SimConfig.ARRIVAL_HOLD:
		sim.step(false)
	assert_true(sim.state.started, "it flies on by itself after the wait")


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
		while not sim.is_over():
			sim.step(false)
		assert_true(sim.revive(), "revived after %d ticks" % die_after)
		assert_eq(_plan(sim.state), plan, "after %d ticks: the room's exits as planned" % die_after)
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


## The map one seed's rooms show: kind, variant, seed and planned exits of each
## room, and the side, score, tick in the room, spikes, anchor and room state
## of each wall,
## keyed by room and wall number. With `die_at_room` >= 0 the bot stops
## tapping in that room or later once the score ends in `die_digit`, and is
## revived.
static func _map(seed_value: int, die_at_room: int, die_digit: int) -> Dictionary:
	var sim := GameSim.new(seed_value)
	var rng := SimRng.new(1)
	var out := {}
	var dying := false
	out["room 0"] = _room_key(sim)
	for i in 12000:
		var s := sim.state
		if (
			die_at_room >= 0
			and s.revives == 0
			and s.room_index >= die_at_room
			and s.score % 10 == die_digit
			and s.arrival_hold == 0
			and not s.exit_preview
		):
			dying = true
		var tap := SimBots.gap_seeker(sim, rng)
		sim.step(tap and not dying)
		if GameSim.Event.ROOM_CHANGE in sim.events:
			out["room %d" % sim.state.room_index] = _room_key(sim)
		# When the exit opened, in room ticks (they stand still in the hold).
		if GameSim.Event.EXIT_OPEN in sim.events:
			out["open %d" % sim.state.room_index] = sim.room.ticks
		if GameSim.Event.BOUNCE in sim.events or GameSim.Event.ROOM_CHANGE in sim.events:
			var side := 1 if sim.state.vx > 0 else 0
			var mask := sim.state.left_spikes if side == 0 else sim.state.right_spikes
			var wall := "%d:%d" % [sim.state.room_index, sim.room.walls]
			out[wall] = [
				side,
				sim.state.score,
				sim.room.ticks,
				mask,
				sim.state.anchor_y,
				sim.room.checksum(0)
			]
		if sim.is_over():
			if not dying or not sim.revive():
				break
			dying = false
			out["revived"] = sim.state.room_index
	return out


static func _room_key(sim: GameSim) -> Array:
	return [sim.state.room_kind, sim.room.variant, sim.room.rng_seed, _plan(sim.state)]


## Two players on one seed meet the same map: one dies on an even or an odd
## score and is revived, the other never dies there. Every room and wall both
## reached is the same (an odd score once flipped the exit wall, so every later
## room came in from the other side and differed).
func test_a_revived_run_meets_the_same_map() -> void:
	var compared := 0
	# Seeds where the gap seeker gets past the revived room and that room's
	# exit opens at the same room tick in both plays (else nothing after it is
	# compared): found by a scan of seeds 20..139 after Bumper Court went out.
	for seed_value: int in [45, 63, 126, 127]:
		for digit: int in [4, 5]:
			var a := _map(seed_value, -1, 0)
			var r := _map(seed_value, 1, digit)
			if not r.has("revived"):
				continue
			# A room whose exit opened at another tick, or in one play only (the
			# other died there), was played another way (Bumper Cloud, wind): the
			# rooms after it follow from that play.
			var last := 1 << 30
			for k: String in a.keys() + r.keys():
				if k.begins_with("open ") and a.get(k, -1) != r.get(k, -1):
					last = mini(last, int(k.substr(5)))
			for k: String in a:
				if not r.has(k) or k == "revived" or k.begins_with("open "):
					continue
				# That room's arrival still counts, its walls and later rooms not.
				var room := k.begins_with("room ")
				var at := int(k.substr(5)) if room else int(k.get_slice(":", 0))
				if at > last or (at == last and not room):
					continue
				var what := "seed %d, death on ..%d: %s" % [seed_value, digit, k]
				var want: Array = a[k]
				var got: Array = r[k]
				# A bounce at another tick in the room, or with the hazards
				# elsewhere, may meet other spikes in a room whose walls follow
				# its hazards (Lava Rise, Locked Out), for any two players: only
				# the side and score must match then.
				if not k.begins_with("room ") and (got[2] != want[2] or got[5] != want[5]):
					want = want.slice(0, 2)
					got = got.slice(0, 2)
				assert_eq(got, want, what)
				if k.begins_with("room ") and int(k.substr(5)) > int(r["revived"]):
					compared += 1
	assert_true(compared > 0, "some run went on past the revived room")
