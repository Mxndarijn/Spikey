extends TestCase
## Pinwheel (sim/hazards/rotor.gd) and its six variants.

const Rotor := preload("res://sim/hazards/rotor.gd")
const Motion := preload("res://sim/rooms/catalog_motion.gd")
const SUB := SimConfig.SUB


## A sim in Pinwheel playing variant `shape` (the first seed that draws it).
static func sim_with(shape: String, from_seed: int = 1) -> GameSim:
	var index := RoomCatalog.index_of("pinwheel")
	for s in range(from_seed, from_seed + 400):
		var sim := GameSim.new(s)
		sim.state.room_kind = index
		sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(s + 1))
		if sim.room.variant_id() == shape:
			return sim
	return null


static func advance(sim: GameSim, steps: int) -> void:
	for i in steps:
		sim.room.step(sim)


static func put_bird(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y


func test_every_variant_is_drawn() -> void:
	var index := RoomCatalog.index_of("pinwheel")
	var seen := {}
	for s in 200:
		var sim := GameSim.new(s)
		sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(s))
		seen[sim.room.variant_id()] = true
		assert_eq(sim.room.hazards.size(), 1, "one rotor hazard")
		assert_eq(sim.room.hazards[0].kind, "rotor")
	for shape: String in Motion.PINWHEELS:
		assert_true(seen.has(shape), "%s is drawn" % shape)


func test_pinwheel_is_smaller_and_double_trouble_keeps_the_big_wheel() -> void:
	var big := Rotor.new()
	assert_eq(big.reach(), 88 * SUB, "the original wheel")
	var trim: Hazard = sim_with("trim").room.hazards[0]
	assert_eq(trim.reach(), 71 * SUB, "Trim: blades 64, half width 7")
	assert_eq(trim.hub_radius, 14 * SUB)
	assert_eq(trim.blades, 4)
	for shape: String in Motion.PINWHEELS:
		var r: Hazard = sim_with(shape).room.hazards[0]
		assert_true(r.reach() < big.reach(), "%s is smaller than the original" % shape)


func test_hubs_and_blades_kill_and_the_gaps_are_safe() -> void:
	for shape: String in Motion.PINWHEELS:
		var sim := sim_with(shape)
		var r: Hazard = sim.room.hazards[0]
		advance(sim, 37)
		for h in r.hubs:
			var cx: int = r.hub_x(h)
			var cy: int = r.hub_y(h)
			put_bird(sim, cx, cy)
			assert_true(r.kills(sim), "%s: hub %d kills" % [shape, h])
			for i in r.blades:
				var a: int = r.blade_angle(h, i)
				var d: int = r.blade_length * 3 / 4
				put_bird(
					sim,
					cx + d * SimTrig.cos_t(a) / SimTrig.ONE,
					cy + d * SimTrig.sin_t(a) / SimTrig.ONE
				)
				assert_true(r.kills(sim), "%s: blade %d of hub %d kills" % [shape, i, h])
				# Between this blade and the next, just past the tips.
				var mid: int = a + SimTrig.TURN / (2 * r.blades)
				var far: int = r.blade_length + SimConfig.BIRD_RADIUS
				put_bird(
					sim,
					cx + far * SimTrig.cos_t(mid) / SimTrig.ONE,
					cy + far * SimTrig.sin_t(mid) / SimTrig.ONE
				)
				assert_false(
					r.kills(sim), "%s: between blades %d and %d is safe" % [shape, i, i + 1]
				)


func test_a_steady_wheel_turns_once_a_period() -> void:
	for shape: String in ["trim", "three", "lean"]:
		var sim := sim_with(shape)
		var r: Hazard = sim.room.hazards[0]
		var start: int = r.angle
		advance(sim, r.period / 4)
		var quarter := posmod((r.angle - start) * r.dir, SimTrig.TURN)
		assert_between(quarter, 250, 262, "%s: a quarter turn in a quarter period" % shape)
		advance(sim, r.period * 3 / 4)
		assert_between(posmod(r.angle - start, SimTrig.TURN), 0, 4, "%s: round in a period" % shape)


func test_three_blades_sit_a_third_of_a_turn_apart() -> void:
	var r: Hazard = sim_with("three").room.hazards[0]
	assert_eq(r.blades, 3)
	assert_eq(r.blade_angle(0, 1) - r.blade_angle(0, 0), SimTrig.TURN / 3)


func test_twin_hubs_sit_apart_and_turn_opposite_ways() -> void:
	var sim := sim_with("twin")
	var r: Hazard = sim.room.hazards[0]
	assert_eq(r.hubs, 2)
	assert_eq([r.hub_x(0), r.hub_y(0)], [120 * SUB, 248 * SUB], "upper left")
	assert_eq([r.hub_x(1), r.hub_y(1)], [240 * SUB, 392 * SUB], "lower right")
	for i in 5:
		advance(sim, 13)
		assert_eq(posmod(r.blade_angle(0, 0) + r.blade_angle(1, 0), SimTrig.TURN), 0, "mirrored")
	# Neither hub's blades ever reach the other hub's blades.
	var dx: int = r.hub_x(1) - r.hub_x(0)
	var dy: int = r.hub_y(1) - r.hub_y(0)
	assert_true(dx * dx + dy * dy > 4 * r.reach() * r.reach(), "the wheels never touch")


func test_rocking_wheel_slows_stops_and_turns_back() -> void:
	var sim := sim_with("rock")
	var r: Hazard = sim.room.hazards[0]
	var full: int = SimTrig.TURN / r.period + 1
	var last: int = r.angle
	var forward := 0
	var back := 0
	var still := 0
	for i in Rotor.ROCK_HALF * 4:
		advance(sim, 1)
		var moved := posmod((r.angle - last) * r.dir + SimTrig.TURN / 2, SimTrig.TURN)
		moved -= SimTrig.TURN / 2
		assert_true(absi(moved) <= full, "never faster than full speed (step %d)" % i)
		if moved > 0:
			forward += 1
		elif moved < 0:
			back += 1
		else:
			still += 1
		last = r.angle
	assert_true(forward > Rotor.ROCK_RUN, "turns one way")
	assert_true(back > Rotor.ROCK_RUN, "and back the other way")
	assert_true(still >= Rotor.ROCK_PAUSE, "stands still between")
	# A reversal takes over a second from full speed to full speed back.
	assert_true(2 * Rotor.ROCK_EASE + Rotor.ROCK_PAUSE >= SimConfig.TICKS_PER_SECOND)


func test_breathing_wheel_grows_and_shrinks() -> void:
	var sim := sim_with("breathe")
	var r: Hazard = sim.room.hazards[0]
	assert_eq(r.blade_length, 40 * SUB, "starts short")
	advance(sim, Rotor.BREATHE_HOLD + Rotor.BREATHE_MOVE / 2)
	assert_between(r.blade_length, 50 * SUB, 62 * SUB, "growing")
	advance(sim, Rotor.BREATHE_MOVE / 2 + 10)
	assert_eq(r.blade_length, 72 * SUB, "long")
	assert_eq(r.reach(), 79 * SUB, "reach uses the long blade")
	advance(sim, Rotor.BREATHE_CYCLE - Rotor.BREATHE_HOLD - Rotor.BREATHE_MOVE - 10)
	assert_eq(r.blade_length, 40 * SUB, "short again after a cycle")


func test_off_centre_wheel_sits_by_a_wall_and_leaves_room_by_it() -> void:
	var sides := {}
	for s in range(1, 400, 7):
		var sim := sim_with("lean", s)
		if sim == null:
			continue
		var r: Hazard = sim.room.hazards[0]
		assert_true(r.center_x in [128 * SUB, 232 * SUB], "by a wall: %d" % r.center_x)
		sides[r.center_x] = true
		# A whole bird fits between the blade tips and the spike tips.
		var gap: int = mini(r.center_x, SimConfig.WORLD_W - r.center_x) - r.reach()
		assert_true(gap - SimConfig.SPIKE_DEPTH > 2 * SimConfig.BIRD_RADIUS, "room by the wall")
	assert_eq(sides.size(), 2, "both walls")


## Out of a portal every variant sits off the bird's height: a bird that holds
## its height (hopping up about HOP) clears every hub's blades.
func test_every_variant_moves_off_the_arriving_bird() -> void:
	var index := RoomCatalog.index_of("pinwheel")
	var seen := {}
	for i in 60:
		var sim := GameSim.new(500 + i)
		sim.step(true)
		sim.state.score = 40
		sim.state.y = (120 + (i * 37) % 400) * SUB
		sim._arrive_in(i % 2, index)
		var r: Hazard = sim.room.hazards[0]
		seen[sim.room.variant_id()] = true
		var reach: int = r.reach() + SimConfig.BIRD_RADIUS
		for h in r.hubs:
			var below: int = r.hub_y(h) - sim.state.y
			assert_true(
				below >= reach or -below >= reach + Rotor.HOP,
				"%s clear at %d (hub %d)" % [sim.room.variant_id(), i, h]
			)
		if r.lean != 0:
			var right := sim.state.vx > 0
			assert_eq(r.center_x > Rotor.CENTER_X, right, "off-centre on the far side")
	assert_eq(seen.size(), Motion.PINWHEELS.size(), "every variant arrived")
	var start := GameSim.new(3)
	start._enter_room(index)
	assert_eq(start.room.hazards[0].center_y, Rotor.CENTER_Y, "in the middle at a run's start")
