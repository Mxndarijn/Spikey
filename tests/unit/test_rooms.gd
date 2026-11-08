extends TestCase
## The room system: catalog, picking, and every room kind playable on its own.

const STEPS := 1500


func test_catalog_ids_are_unique_and_first_room_is_open() -> void:
	var seen := {}
	for def in RoomCatalog.all():
		assert_false(seen.has(def.id), "room id %s is unique" % def.id)
		seen[def.id] = true
		assert_true(def.weight > 0, "%s can be picked" % def.id)
	assert_eq(RoomCatalog.all()[RoomCatalog.first_index()].id, "open")
	assert_eq(RoomCatalog.find("open").from_score, 0)


func test_pick_respects_score_season_and_never_repeats() -> void:
	var rng := SimRng.new(31)
	for score in [10, 40, 90, 150]:
		for season in [Seasons.NONE, Seasons.HALLOWEEN]:
			var current := RoomCatalog.first_index()
			for i in 50:
				var next := RoomCatalog.pick_next(rng, current, score, season)
				var def := RoomCatalog.all()[next]
				assert_ne(next, current, "a new room at score %d" % score)
				assert_true(RoomCatalog.allowed(def, score, season), "%s allowed" % def.id)
				current = next


## Puts a fresh run straight into one room kind.
static func sim_in_room(id: String, seed_value: int, season: int = Seasons.NONE) -> GameSim:
	var sim := GameSim.new(seed_value, season)
	var index := RoomCatalog.index_of(id)
	sim.state.room_kind = index
	sim.room.start(RoomCatalog.all()[index], index, sim, SimRng.new(seed_value + 1))
	return sim


## Every room runs with a random tapper without errors, and replays the same.
func test_every_room_runs_and_is_deterministic() -> void:
	for def in RoomCatalog.all():
		var a := _run_room(def.id, 9)
		var b := _run_room(def.id, 9)
		assert_eq(a, b, "%s replays the same" % def.id)


static func _run_room(id: String, seed_value: int) -> int:
	var sim := sim_in_room(id, seed_value)
	var bot := SimRng.new(seed_value)
	sim.step(true)
	var i := 0
	while i < STEPS:
		if sim.is_over():
			sim = sim_in_room(id, seed_value + i)
			sim.step(true)
		sim.step(SimBots.random_tapper(sim, bot, 14))
		i += 1
	return sim.checksum()


func test_gravity_flip_pulls_up() -> void:
	var sim := sim_in_room("flip", 1)
	sim.step(true)
	assert_true(sim.state.vy > 0, "a flap pushes down")
	for i in 30:
		sim.step(false)
	assert_true(sim.state.vy < 0, "falls toward the ceiling")


func test_slow_mo_runs_half_as_many_steps() -> void:
	var sim := sim_in_room("slowmo", 1)
	sim.step(true)
	for i in 39:
		sim.step(false)
	assert_eq(sim.room.t, 20, "one step every other tick")


func test_midnight_runs_faster() -> void:
	var sim := sim_in_room("midnight", 1)
	sim.step(true)
	for i in 39:
		sim.step(false)
	assert_eq(sim.room.t, 50, "five steps every four ticks")


func test_squeeze_moves_walls_in_per_point() -> void:
	var sim := sim_in_room("squeeze", 2)
	assert_eq(sim.room.wall_left(), 0)
	sim.room.points = 4
	assert_eq(sim.room.wall_left(), 4 * RoomRuntime.SQUEEZE_STEP)
	assert_eq(sim.room.wall_right(), SimConfig.WORLD_W - 4 * RoomRuntime.SQUEEZE_STEP)


func test_tide_spikes_move_blink_walls_switch() -> void:
	var sim := sim_in_room("tide", 3)
	sim.room.tide_left = 0b1
	var depths := {}
	for i in RoomRuntime.TIDE_PERIOD:
		sim.room.t = i
		depths[sim.room.slot_depth(0, 0)] = true
	assert_true(depths.size() > 10, "a tide spike slides in and out")
	assert_true(depths.has(0), "a tide spike goes flat")
	assert_true(depths.has(RoomRuntime.TIDE_MAX_DEPTH), "a tide spike reaches full length")
	assert_true(RoomRuntime.TIDE_MAX_DEPTH > SimConfig.SPIKE_DEPTH, "longer than a normal spike")
	sim.room.t = 0
	assert_eq(sim.room.slot_depth(0, 1), SimConfig.SPIKE_DEPTH, "other spikes stay out")
	var blink := sim_in_room("blink", 3)
	blink.room.blink_left = 0b101
	blink.room.t = 0
	assert_eq(blink.room.wall_mask(0, 0b11), 0b11)
	blink.room.t = RoomRuntime.BLINK_PERIOD
	assert_eq(blink.room.wall_mask(0, 0b11), 0b101, "the second pattern shows")


func test_coin_garden_pays_four_coins() -> void:
	var sim := sim_in_room("garden", 4)
	var coins := 0
	for h in sim.room.hazards:
		if h.kind == "coin":
			coins += 1
			sim.state.x = h.x
			sim.state.y = h.y
			h.touch(sim)
	assert_eq(coins, 4)
	assert_eq(sim.state.coins, 4)


func test_islands_leave_room_to_fly() -> void:
	for s in 30:
		var sim := sim_in_room("isles", s)
		for h in sim.room.hazards:
			assert_true(h.y1 - h.y0 <= 36 * SimConfig.SUB, "island is low")
			assert_true(
				h.x0 >= 80 * SimConfig.SUB and h.x1 <= 280 * SimConfig.SUB, "clear of walls"
			)


func test_season_is_part_of_the_replay() -> void:
	var replay := SimBots.play(77, SimBots.gap_seeker, 1, 2000)
	replay.season = Seasons.WINTER
	var honest := Replay.simulate(replay.seed_value, replay.taps, Seasons.WINTER)
	replay.score = honest.state.score
	replay.coins = honest.state.coins
	replay.end_tick = honest.state.tick
	replay.checksum = honest.checksum()
	assert_true(replay.verify().ok, "a winter run verifies as winter")
	replay.season = 42
	assert_false(replay.verify().ok, "unknown season rejected")


func test_seasonal_rooms_only_in_their_season() -> void:
	var seasonal := 0
	for def in RoomCatalog.all():
		if def.season == Seasons.NONE:
			continue
		seasonal += 1
		assert_true(RoomCatalog.allowed(def, 500, def.season), "%s in season" % def.id)
		var other := (def.season + 1) % Seasons.COUNT
		assert_false(RoomCatalog.allowed(def, 500, other), "%s out of season" % def.id)
		assert_false(RoomCatalog.allowed(def, 500, Seasons.NONE), "%s off season" % def.id)
	assert_eq(seasonal, 13, "13 seasonal rooms")


func test_all_picked_rooms_exist() -> void:
	var ids: Array[String] = []
	for def in RoomCatalog.all():
		ids.append(def.id)
	for id in [
		"open",
		"tide",
		"isles",
		"cloud",
		"gates",
		"crawl",
		"piston",
		"swing",
		"court",
		"squeeze",
		"stalker",
		"crates",
		"pinwheel",
		"bramble",
		"beams",
		"stalac",
		"updraft",
		"bubbles",
		"hunter",
		"midnight",
		"double",
		"sawring",
		"flip",
		"blink",
		"rain",
		"garden",
		"orchard",
		"keepy",
		"slowmo",
		"pumpkin",
		"ghostdoors",
		"bats",
		"icicle",
		"gifts",
		"hearts",
		"cupid",
		"eggs",
		"bees",
		"beachball",
		"crabs",
		"fireworks",
		"countdown",
	]:
		assert_true(id in ids, "room %s exists" % id)


func test_eggs_sit_next_to_their_islands() -> void:
	for s in 20:
		var sim := sim_in_room("eggs", s, Seasons.SPRING)
		var islands: Array[Hazard] = []
		for h in sim.room.hazards:
			if h.kind == "block":
				islands.append(h)
		for h in sim.room.hazards:
			if h.kind != "coin":
				continue
			for isl in islands:
				sim.state.x = h.x
				sim.state.y = h.y
				assert_false(
					sim.bird_touches_rect(isl.x0, isl.y0, isl.x1, isl.y1),
					"egg at %d,%d is reachable without touching an island" % [h.x, h.y]
				)


func test_double_trouble_picks_a_pair() -> void:
	var kinds := {}
	for s in 40:
		var sim := sim_in_room("double", s)
		assert_eq(sim.room.hazards.size(), 2, "two hazards")
		var pair: Array[String] = []
		for h in sim.room.hazards:
			pair.append(h.kind)
		kinds[",".join(pair)] = true
	assert_true(kinds.size() >= 3, "different pairs show up (%d)" % kinds.size())


func test_the_open_first_room_never_comes_back() -> void:
	var start := RoomCatalog.first_index()
	var rng := SimRng.new(77)
	for score in [10, 40, 120]:
		for route in [SimState.ExitKind.NORMAL, SimState.ExitKind.CALM, SimState.ExitKind.WILD]:
			for i in 200:
				var next := RoomCatalog.pick_next(rng, 3, score, Seasons.NONE, route)
				assert_ne(next, start, "open is only the start")
