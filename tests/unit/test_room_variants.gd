extends TestCase
## Room variants (Tide Spikes sizes, one or two Bumper Clouds) and Narrow's
## sliding walls.

const SUB := SimConfig.SUB


static func sim_in_room(id: String, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	var index := RoomCatalog.index_of(id)
	sim.state.room_kind = index
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	return sim


func test_rooms_without_variants_play_as_before() -> void:
	var sim := sim_in_room("open", 1)
	assert_eq(sim.room.variant, 0)
	assert_eq(sim.room.variant_id(), "")
	assert_eq(sim.room.spike_depth(), SimConfig.SPIKE_DEPTH)
	assert_eq(sim.room.spike_half_base(), SimConfig.SPIKE_HALF_BASE)
	assert_eq(sim.room.spike_bonus(), 0)
	assert_eq(sim.room.inset(), 0)


func test_every_variant_shows_up() -> void:
	var ids: Array[String] = ["tide", "cloud", "bramble", "rain", "swing", "updraft"]
	ids.append_array(["bubbles", "garden", "slowmo"])
	ids.append_array(["crowded", "squeeze", "blink", "hunter", "flip", "midnight"])
	ids.append_array(["sawring", "bats", "cupid", "fireworks"])
	ids.append_array(["crawl", "crabs", "pumpkin", "keepy", "beachball", "hearts"])
	ids.append_array(["isles", "eggs", "gates", "ghostdoors"])
	ids.append_array(["piston", "stalac", "crates", "gifts", "lava", "cave", "pegs", "beams"])
	for id: String in ids:
		var seen := {}
		for s in 200:
			seen[sim_in_room(id, s).room.variant_id()] = true
		assert_eq(seen.size(), RoomCatalog.find(id).variants.size(), "%s variants" % id)


func test_tide_variants_scale_the_spikes() -> void:
	var sim := sim_in_room("tide", 1)
	var def := sim.room.def
	var normal := RoomRules.spike_count(40, def)
	for i in def.variants.size():
		sim.room.variant = i
		var depth := sim.room.spike_depth()
		var half := sim.room.spike_half_base()
		var count := RoomRules.spike_count(40, def, sim.room.spike_bonus())
		match def.variants[i].id:
			"normal":
				assert_eq(depth, SimConfig.SPIKE_DEPTH)
				assert_eq(half, SimConfig.SPIKE_HALF_BASE)
				assert_eq(count, normal)
			"big":
				assert_true(depth > SimConfig.SPIKE_DEPTH, "big spikes are longer")
				assert_true(half > SimConfig.SPIKE_HALF_BASE, "and wider")
				assert_true(half <= SimConfig.SLOT_SIZE / 2, "but stay in their slot")
				assert_true(count < normal, "and there are fewer")
			"small":
				assert_true(depth < SimConfig.SPIKE_DEPTH, "small spikes are shorter")
				assert_true(half < SimConfig.SPIKE_HALF_BASE, "and thinner")
				assert_true(count > normal, "and there are more")
		if def.variants[i].id == "big":
			# Big spikes slide out half as far again as the others: 2.25 times.
			assert_eq(sim.room.tide_max_depth(), depth * 9 / 4, "big high tide is 2.25 times")
		else:
			assert_eq(sim.room.tide_max_depth(), depth * 3 / 2, "high tide is 1.5 times")
		assert_eq(sim.room.slot_depth(0, 0), depth, "a still spike has the variant's size")


## Tide big's sliding spikes reach past COIN_MIN_X: its coins keep clear of the
## full reach on both walls; the other Tide variants keep the usual box.
func test_tide_coins_clear_the_high_tide() -> void:
	for id: String in ["normal", "big", "small"]:
		var sim := sim_in_room("tide", 1)
		for i in sim.room.def.variants.size():
			if sim.room.def.variants[i].id == id:
				sim.room.variant = i
		var reach := sim.room.max_spike_depth() + SimConfig.COIN_RADIUS
		var lo := SimConfig.WORLD_W
		var hi := 0
		for n in 300:
			sim.state.coin_active = false
			sim._spawn_coin()
			lo = mini(lo, sim.state.coin_x)
			hi = maxi(hi, sim.state.coin_x)
		assert_true(lo >= reach, "%s: coin clear of the left high tide" % id)
		assert_true(hi <= SimConfig.WORLD_W - reach, "%s: and the right" % id)
		assert_true(
			lo >= SimConfig.COIN_MIN_X and hi <= SimConfig.COIN_MAX_X, "%s: in the box" % id
		)
		if id != "big":
			assert_true(lo < SimConfig.COIN_MIN_X + 10 * SUB, "%s: the usual box" % id)


## A big spike kills where a normal one would not reach, a small one spares
## where a normal one would kill.
func test_spike_size_is_what_kills() -> void:
	var r := SimConfig.BIRD_RADIUS
	var between := (SimConfig.SPIKE_DEPTH + 6 * SUB) + r
	for id: String in ["normal", "big", "small"]:
		var sim := sim_in_room("tide", 1)
		for i in sim.room.def.variants.size():
			if sim.room.def.variants[i].id == id:
				sim.room.variant = i
		sim.state.started = true
		sim.state.left_spikes = 1 << 5
		sim.state.right_spikes = 0
		sim.state.vx = -SimConfig.SPEED_X
		sim.state.vy = -SimConfig.GRAVITY
		sim.state.y = SimConfig.slot_center_y(5)
		# After one step the bird's edge is 6 px past a normal spike's tip.
		sim.state.x = between + SimConfig.SPEED_X
		sim.step(false)
		assert_eq(sim.is_over(), id == "big", "%s spike, 6 px past a normal tip" % id)
		if id == "big":
			continue
		# And 6 px inside a normal spike's reach.
		sim.state.x = between - 12 * SUB + SimConfig.SPEED_X
		sim.state.y = SimConfig.slot_center_y(5)
		sim.state.vy = -SimConfig.GRAVITY
		sim.step(false)
		assert_eq(sim.is_over(), id == "normal", "%s spike, 6 px inside a normal tip" % id)


func test_two_clouds_ride_opposite_sides_of_the_loop() -> void:
	var found := false
	for s in 40:
		var sim := sim_in_room("cloud", s)
		if sim.room.variant_id() != "two":
			assert_eq(sim.room.hazards.size(), 1, "one cloud")
			continue
		found = true
		assert_eq(sim.room.hazards.size(), 2, "two clouds")
		var a: Hazard = sim.room.hazards[0]
		var b: Hazard = sim.room.hazards[1]
		for i in 600:
			sim.room.step(sim)
			var dx: int = (a.x - b.x) / SUB
			var dy: int = (a.y - b.y) / SUB
			assert_true(dx * dx + dy * dy >= 150 * 150, "the clouds stay apart (seed %d)" % s)
	assert_true(found, "the two-cloud variant shows up")


func test_narrow_walls_slide_in() -> void:
	var sim := sim_in_room("narrow", 3)
	var def := sim.room.def
	assert_true(def.inset > 0, "narrow has an inset")
	assert_eq(sim.room.inset(), 0, "the room starts at full width")
	var last := 0
	var steps := 0
	while sim.room.inset() < def.inset and steps < 600:
		sim.room.t += 1
		steps += 1
		var now := sim.room.inset()
		assert_true(now > last, "the walls keep moving in")
		assert_true(now - last <= RoomRuntime.INSET_SPEED, "a little per step, never a jump")
		last = now
	assert_true(steps >= 10, "the slide takes a while (%d steps)" % steps)
	assert_eq(sim.room.wall_left(), def.inset)
	assert_eq(sim.room.wall_right(), SimConfig.WORLD_W - def.inset)
	sim.room.t += 500
	assert_eq(sim.room.inset(), def.inset, "then they stay")


## The wall never reaches a bird that just came out of a portal in it.
func test_narrow_walls_never_catch_the_arriving_bird() -> void:
	for side in 2:
		var sim := GameSim.new(5, Seasons.NONE, RoomCatalog.index_of("narrow"))
		var r := SimConfig.BIRD_RADIUS
		sim.state.started = true
		sim.state.arrival_hold = 0
		sim.state.left_spikes = 0
		sim.state.right_spikes = 0
		sim.state.x = r if side == 1 else SimConfig.WORLD_W - r
		sim.state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
		for i in 40:
			sim.state.y = SimConfig.BIRD_START_Y
			sim.state.vy = 0
			sim.step(false)
			assert_false(sim.is_over(), "alive while the walls slide")
			assert_eq(sim.state.score, RoomCatalog.find("narrow").from_score, "no bounce yet")


func test_narrow_keeps_gap_and_exit_near_the_bird() -> void:
	var def := RoomCatalog.find("narrow")
	var rng := SimRng.new(9)
	for i in 300:
		var bird_y := (60 + rng.next_below(520)) * SUB
		var mask := RoomRules.generate_wall(rng, 40, def, bird_y)
		var near := false
		for start in SimConfig.SLOT_COUNT - def.gap + 1:
			var free := true
			for k in def.gap:
				free = free and not RoomRules.has_slot(mask, start + k)
			var center := SimConfig.slot_center_y(start) + (def.gap - 1) * SimConfig.SLOT_SIZE / 2
			if free and absi(center - bird_y) <= def.reach:
				near = true
		assert_true(near, "a free run within reach of y %d" % (bird_y / SUB))


## Every room with more than one variant (RoomCatalog indexes).
static func _rooms_with_variants() -> Array[int]:
	var out: Array[int] = []
	for i in RoomCatalog.all().size():
		if RoomCatalog.all()[i].variants.size() > 1:
			out.append(i)
	return out


## Plays `sim` for `ticks` with a fixed tap pattern; the checksum of each tick.
static func _checksums(sim: GameSim, ticks: int) -> Array[int]:
	var out: Array[int] = []
	for t in ticks:
		sim.step(t % 23 == 0 or t % 23 == 9)
		out.append(sim.checksum())
	return out


## Bots can force a variant (GameSim's forced_variant). Unset, or forced to the
## variant the RNG drew anyway, the run is the same tick for tick: forcing
## never changes what the RNG draws.
func test_forced_variant_unset_or_same_plays_the_normal_run() -> void:
	assert_eq(GameSim.new(5).forced_variant, "", "unset by default")
	for index in _rooms_with_variants():
		var def: RoomDef = RoomCatalog.all()[index]
		for s in 3:
			var seed_value := 300 + s * 41
			var normal := GameSim.new(seed_value, def.season, index)
			var unset := GameSim.new(seed_value, def.season, index, "")
			var same := GameSim.new(seed_value, def.season, index, normal.room.variant_id())
			var want := _checksums(normal, 240)
			assert_eq(_checksums(unset, 240), want, "%s seed %d unset" % [def.id, seed_value])
			assert_eq(
				_checksums(same, 240), want, "%s seed %d forced as drawn" % [def.id, seed_value]
			)


func test_forced_variant_plays_that_variant() -> void:
	for index in _rooms_with_variants():
		var def: RoomDef = RoomCatalog.all()[index]
		for v in def.variants:
			for s in 4:
				var sim := GameSim.new(700 + s * 13, def.season, index, v.id)
				assert_eq(sim.room.variant_id(), v.id, "%s forced %s" % [def.id, v.id])
			# Copies (searches) and revives keep the forced variant.
			var played := GameSim.new(711, def.season, index, v.id)
			var copy := SimCopy.copy(played)
			assert_eq(copy.forced_variant, v.id, "%s copy keeps it" % def.id)
			copy.room.start(def, index, copy, SimRng.new(3))
			assert_eq(copy.room.variant_id(), v.id, "%s restart keeps it" % def.id)


## A variant id this room doesn't have plays the drawn one.
func test_unknown_forced_variant_plays_the_drawn_one() -> void:
	for index in _rooms_with_variants():
		var def: RoomDef = RoomCatalog.all()[index]
		var normal := GameSim.new(900, def.season, index)
		var odd := GameSim.new(900, def.season, index, "no-such-variant")
		assert_eq(odd.room.variant_id(), normal.room.variant_id(), def.id)
		assert_eq(odd.checksum(), normal.checksum(), def.id)
