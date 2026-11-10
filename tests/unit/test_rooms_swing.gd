extends TestCase
## Lantern Swing: every variant (big, twin, chimes, gusty, winch).

const SUB := SimConfig.SUB
const SWING_VARIANTS: Array[String] = ["big", "twin", "chimes", "gusty", "winch"]
## Steps over which a lantern's speed is measured.
const WINDOW := 8


static func sim_in_room(id: String, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	var index := RoomCatalog.index_of(id)
	sim.state.room_kind = index
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	return sim


static func put_bird(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y


## A sim in Lantern Swing with variant `variant_id`'s lanterns set up.
static func sim_in_swing(variant_id: String, seed_value: int) -> GameSim:
	var sim := sim_in_room("swing", seed_value)
	var def := sim.room.def
	var rng := SimRng.new(seed_value + 2)
	sim.room.hazards.clear()
	for i in def.variants.size():
		if def.variants[i].id != variant_id:
			continue
		sim.room.variant = i
		for f: Callable in def.variants[i].hazards:
			var h: Hazard = f.call()
			sim.room.hazards.append(h)
			h.setup(sim, rng)
	return sim


## Lantern centres of a pendulum: [x, y] pairs (two for a twin).
static func lamps(p: Hazard) -> Array:
	var out := [[p.x, p.y]]
	if p.has_twin():
		out.append([p.x2, p.y2])
	return out


func test_every_swing_variant_shows_up() -> void:
	var seen := {}
	for s in 80:
		seen[sim_in_room("swing", s).room.variant_id()] = true
	assert_eq(seen.keys().size(), SWING_VARIANTS.size(), "swing variants: %s" % [seen.keys()])
	for id: String in SWING_VARIANTS:
		assert_true(seen.has(id), "%s shows up" % id)


func test_lantern_kills_and_chain_is_safe() -> void:
	for id: String in SWING_VARIANTS:
		var sim := sim_in_swing(id, 2)
		assert_true(sim.room.hazards.size() > 0, "%s has lanterns" % id)
		for p: Hazard in sim.room.hazards:
			put_bird(sim, p.x, p.y)
			assert_true(p.kills(sim), "%s: the lantern kills" % id)
			# Halfway up the chain.
			put_bird(sim, (p.x + p.pivot_x) / 2, (p.y + p.pivot_y) / 2)
			assert_false(p.kills(sim), "%s: the chain is safe" % id)
			if p.has_twin():
				put_bird(sim, p.x2, p.y2)
				assert_true(p.kills(sim), "%s: the twin lantern kills" % id)
				put_bird(sim, (p.x2 + p.twin_x) / 2, (p.y2 + p.pivot_y) / 2)
				assert_false(p.kills(sim), "%s: the twin chain is safe" % id)


## Every lantern stays inside x 40..320 px (clear of a bird at either wall),
## well above the floor, moves slower than the bird and swings a good way.
func test_lanterns_swing_inside_the_room_slower_than_the_bird() -> void:
	for id: String in SWING_VARIANTS:
		var sim := sim_in_swing(id, 2)
		var low := {}
		var high := {}
		var last := {}
		var ok := true
		for i in 2100:
			sim.room.step(sim)
			var k := 0
			for p: Hazard in sim.room.hazards:
				for lamp: Array in lamps(p):
					var x: int = lamp[0]
					var y: int = lamp[1]
					if x - p.radius < 40 * SUB or x + p.radius > 320 * SUB:
						ok = false
					if y + p.radius >= SimConfig.KILL_BOTTOM - 100 * SUB:
						ok = false
					# Over WINDOW steps: one step can jump a little more,
					# as the swing angle is a whole SimTrig unit.
					if i % WINDOW == 0:
						if last.has(k):
							var dx: int = x - last[k][0]
							var dy: int = y - last[k][1]
							var most := WINDOW * SimConfig.SPEED_X
							if dx * dx + dy * dy >= most * most:
								ok = false
						last[k] = [x, y]
					low[k] = mini(low.get(k, x), x)
					high[k] = maxi(high.get(k, x), x)
					k += 1
		assert_true(ok, "%s: inside x 40..320, high, slower than the bird" % id)
		for k: int in low:
			assert_true(high[k] - low[k] > 60 * SUB, "%s: lantern %d swings" % [id, k])


func test_big_lantern_is_bigger_than_the_classic() -> void:
	var sim := sim_in_swing("big", 2)
	var p: Hazard = sim.room.hazards[0]
	assert_true(p.radius > p.RADIUS, "a bigger lantern")
	assert_true(p.length > p.LENGTH, "on a longer chain")
	var reach := 0
	for i in p.period:
		sim.room.step(sim)
		reach = maxi(reach, absi(p.x - p.pivot_x))
	assert_true(reach > 100 * SUB, "swings wider (%d px)" % (reach / SUB))


func test_twin_lanterns_swing_opposite_ways() -> void:
	var sim := sim_in_swing("twin", 3)
	var p: Hazard = sim.room.hazards[0]
	assert_true(p.has_twin(), "two lanterns")
	for i in p.period:
		sim.room.step(sim)
		if p.angle != 0:
			assert_true((p.x > p.pivot_x) != (p.x2 > p.twin_x), "opposite at step %d" % i)


func test_chimes_swing_on_their_own_beats() -> void:
	var sim := sim_in_swing("chimes", 2)
	assert_eq(sim.room.hazards.size(), 3)
	var periods := {}
	for p: Hazard in sim.room.hazards:
		periods[p.period] = true
		assert_true(p.radius < 22 * SUB, "small lanterns")
	assert_eq(periods.size(), 3, "three swing times")


func test_gusty_swing_grows_and_shrinks() -> void:
	var sim := sim_in_swing("gusty", 2)
	var p: Hazard = sim.room.hazards[0]
	# Around the gust's peak (a quarter of the way in) and its calm (three
	# quarters), each window long enough for the swing to reach its widest.
	var widest := [0, 0]
	var quarter: int = p.gust_period / 4
	for i in p.gust_period:
		sim.room.step(sim)
		if absi(i - quarter) < quarter / 2:
			widest[0] = maxi(widest[0], absi(p.angle))
		elif absi(i - 3 * quarter) < quarter / 2:
			widest[1] = maxi(widest[1], absi(p.angle))
	assert_true(widest[0] > widest[1] + 20, "wide, then calm: %s" % [widest])


func test_winch_winds_the_chain_up_and_down() -> void:
	var sim := sim_in_swing("winch", 2)
	var p: Hazard = sim.room.hazards[0]
	var shortest := 1 << 40
	var longest := 0
	for i in p.winch_period:
		sim.room.step(sim)
		shortest = mini(shortest, p.chain)
		longest = maxi(longest, p.chain)
	assert_between(shortest, 199 * SUB, 201 * SUB)
	assert_between(longest, 329 * SUB, 331 * SUB)
