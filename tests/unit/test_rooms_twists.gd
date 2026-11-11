extends TestCase
## Twist rooms: Crosswind, Spike Belt, Lava Rise and Echo (Locked Out: test_locked_out.gd).

const Rooms := preload("res://tests/unit/test_rooms.gd")
const Wind := preload("res://sim/hazards/wind.gd")
const Belt := preload("res://sim/hazards/belt.gd")
const Lava := preload("res://sim/hazards/lava.gd")
const Echo := preload("res://sim/hazards/echo.gd")

const SUB := SimConfig.SUB
const TWISTS := {
	"crosswind": ["wind", ["steady", "split", "gusty"]],
	"belt": ["belt", ["up", "counter", "switchback"]],
	"lava": ["lava", ["lava"]],
	"echo": ["echo", ["echo", "mirror"]],
}


func test_twist_rooms_build_their_hazard_in_every_variant() -> void:
	for id: String in TWISTS:
		var def := RoomCatalog.find(id)
		assert_true(def != null, "%s exists" % id)
		assert_true(RoomInfo.ROOMS.has(id), "%s has room info" % id)
		var seen := {}
		for s in 40:
			var sim := Rooms.sim_in_room(id, s)
			assert_eq(sim.room.hazards.size(), 1, "%s: one hazard" % id)
			assert_eq(sim.room.hazards[0].kind, TWISTS[id][0], "%s hazard kind" % id)
			seen[sim.room.variant_id()] = true
		for v: String in TWISTS[id][1]:
			assert_true(seen.has(v), "%s: variant %s comes up" % [id, v])


# --- Crosswind ---------------------------------------------------------------


func test_wind_speeds_the_bird_one_way_and_slows_it_the_other() -> void:
	var sim := _started("crosswind", 1)
	var w: Wind = sim.room.hazards[0]
	w.mode = Wind.Mode.STEADY
	sim.state.y = (w.a_y0 + w.a_y1) / 2
	sim.state.x = 180 * SUB
	sim.state.vx = SimConfig.SPEED_X * w.a_dir
	var x0 := sim.state.x
	w.touch(sim)
	assert_eq(sim.state.x - x0, w.a_dir * Wind.PUSH, "pushed along the wind")
	sim.state.y = 100 * SUB
	x0 = sim.state.x
	w.touch(sim)
	assert_eq(sim.state.x, x0, "no wind outside the band")
	assert_eq(sim.state.vy, 0, "never pushes up or down")


func test_split_bands_blow_opposite_ways() -> void:
	var w := Wind.new(Wind.Mode.SPLIT)
	w.setup(GameSim.new(2), SimRng.new(2))
	assert_eq(w.b_dir, -w.a_dir, "opposite")
	assert_true(w.a_y1 < w.b_y0, "two separate bands")


func test_gusts_start_calm_and_warn_first() -> void:
	var w := Wind.new(Wind.Mode.GUSTY)
	w.setup(GameSim.new(3), SimRng.new(3))
	var first_blow := -1
	var warned := false
	for t in Wind.GUST_PERIOD:
		w.t = t
		if w.warning():
			warned = true
		if w.blowing() and first_blow < 0:
			first_blow = t
	assert_true(warned, "a warning comes first")
	assert_true(first_blow >= SimConfig.ARRIVAL_BLIND, "calm while a new arrival reads the room")


# --- Spike Belt --------------------------------------------------------------


func test_belt_holds_while_reading_then_slides_and_resets_on_a_new_wall() -> void:
	var sim := _started("belt", 4)
	var b: Belt = sim.room.hazards[0]
	b.mode = Belt.Mode.UP
	b.left_dir = -1
	b.right_dir = -1
	sim.state.vx = SimConfig.SPEED_X
	for i in SimConfig.ARRIVAL_BLIND:
		sim.room.step(sim)
	assert_eq(b.right_shift, 0, "still while the player reads the room")
	for i in 20:
		sim.room.step(sim)
	assert_eq(b.right_shift, -20 * Belt.SPEED, "slides up at its speed")
	assert_eq(sim.wall_shift(1), b.right_shift, "the sim sees the shift")
	b.on_bounce(sim, SimRng.new(1))
	assert_eq(b.right_shift, 0, "a new wall starts at rest")


func test_belt_spikes_hit_where_they_are_drawn() -> void:
	var sim := _started("belt", 5)
	var b: Belt = sim.room.hazards[0]
	sim.state.right_spikes = 1 << 6
	b.right_shift = 30 * SUB
	sim.state.x = SimConfig.WORLD_W - SimConfig.BIRD_RADIUS - 4 * SUB
	sim.state.y = SimConfig.slot_center_y(6) + 30 * SUB
	sim._check_spikes()
	assert_false(sim.state.alive, "hit at the shifted height")
	sim = _started("belt", 5)
	b = sim.room.hazards[0]
	sim.state.right_spikes = 1 << 6
	b.right_shift = 50 * SUB
	sim.state.x = SimConfig.WORLD_W - SimConfig.BIRD_RADIUS - 4 * SUB
	sim.state.y = SimConfig.slot_center_y(6) - 10 * SUB
	sim._check_spikes()
	assert_true(sim.state.alive, "the slot's old height is clear")


func test_belt_stops_on_an_open_exit() -> void:
	var sim := _started("belt", 6)
	var b: Belt = sim.room.hazards[0]
	sim.room.t = 100
	b.t = 100
	sim.state.exit_open = true
	sim.state.exit_side = 1
	b.step(sim)
	assert_eq(b.right_shift, 0, "the exit's opening never moves")
	assert_ne(b.left_shift, 0, "the other wall still runs")


# --- Lava Rise ---------------------------------------------------------------


func test_lava_rises_per_point_and_a_stone_sinks_it() -> void:
	var sim := _started("lava", 10)
	var l: Lava = sim.room.hazards[0]
	l.line = l.rest()
	for p in Lava.STONE_AFTER:
		sim.room.points += 1
		l.on_bounce(sim, SimRng.new(p))
	assert_eq(l.rises, Lava.STONE_AFTER, "one rise per point")
	assert_true(l.stone_on, "a stone shows up")
	assert_true(
		l.stone_y <= l.line_at(l.rises) - Lava.STONE_CLEAR, "the stone is clear of the lava"
	)
	for i in 200:
		l.step(sim)
	assert_eq(l.line, l.line_at(Lava.STONE_AFTER), "the lava glides up")
	sim.state.x = 180 * SUB
	sim.state.y = l.line - SimConfig.BIRD_RADIUS
	assert_true(l.kills(sim), "touching the lava kills")
	sim.state.x = l.stone_x
	sim.state.y = l.stone_y
	l.touch(sim)
	assert_eq(l.rises, 0, "the stone cools it")
	for i in 200:
		l.step(sim)
	assert_eq(l.line, SimConfig.KILL_BOTTOM, "back to rest")


func test_lava_stops_rising_and_keeps_a_free_run() -> void:
	var sim := _started("lava", 11)
	var l: Lava = sim.room.hazards[0]
	l.line = l.rest()
	sim.room.points = 20
	l.on_bounce(sim, SimRng.new(1))
	assert_eq(l.rises, Lava.MAX_RISES, "it stops rising")
	var edge := l.line_at(Lava.MAX_RISES)
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	sim.state.y = 320 * SUB
	var mask: int = l.adjust_wall(sim, 1, all)
	var run := 0
	var best := 0
	for slot in SimConfig.SLOT_COUNT:
		if l._slot_clear(slot, edge) and not RoomRules.has_slot(mask, slot):
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	assert_true(best >= Lava.RUN, "a free run clear of the line")


func test_lava_keeps_exits_out_of_its_reach() -> void:
	var sim := _started("lava", 12)
	var l: Lava = sim.room.hazards[0]
	l.rises = 4
	var worst := l.line_at(5)
	assert_true(l.blocks_exit(sim, 1, worst), "no exit in the lava")
	assert_false(l.blocks_exit(sim, 1, worst - Lava.EXIT_CLEAR - SUB), "above it is fine")


# --- Echo --------------------------------------------------------------------


func test_echo_flies_the_path_one_second_late() -> void:
	var sim := _started("echo", 13)
	var e: Echo = sim.room.hazards[0]
	e.mode = Echo.Mode.ECHO
	var path: Array[Vector2i] = []
	for i in Echo.DELAY * 2:
		sim.state.x = (40 + i) * SUB
		sim.state.y = (200 + i) * SUB
		path.append(Vector2i(sim.state.x, sim.state.y))
		e.t = i + 1
		e.step(sim)
		if i < Echo.DELAY:
			assert_false(e.shown, "hidden for the first second")
			assert_false(e.kills(sim), "harmless while hidden")
		else:
			assert_eq(Vector2i(e.x, e.y), path[i - Echo.DELAY], "a second behind")
	sim.state.x = e.x
	sim.state.y = e.y
	assert_true(e.kills(sim), "touching it kills")


func test_mirror_flies_opposite_through_the_middle() -> void:
	var sim := _started("echo", 14)
	var e: Echo = sim.room.hazards[0]
	e.mode = Echo.Mode.MIRROR
	sim.state.x = 100 * SUB
	sim.state.y = 200 * SUB
	e.t = Echo.DELAY + 1
	e.step(sim)
	assert_eq(e.x, SimConfig.WORLD_W - 100 * SUB)
	assert_eq(e.y, SimConfig.WORLD_H - 200 * SUB)
	assert_false(e.kills(sim), "far apart off the middle")
	assert_false(RoomCatalog.find("echo").fits_arrival(320 * SUB), "no arrivals at mid height")


func test_twist_hazards_are_deterministic() -> void:
	for id: String in TWISTS:
		assert_eq(_run_room(id, 21), _run_room(id, 21), "%s replays the same" % id)


static func _run_room(id: String, seed_value: int) -> int:
	var sim := Rooms.sim_in_room(id, seed_value)
	var bot := SimRng.new(seed_value)
	sim.step(true)
	for i in 900:
		if sim.is_over():
			break
		sim.step(SimBots.random_tapper(sim, bot, 14))
	return sim.checksum()


static func _started(id: String, seed_value: int) -> GameSim:
	var sim := Rooms.sim_in_room(id, seed_value)
	sim.state.started = true
	return sim
