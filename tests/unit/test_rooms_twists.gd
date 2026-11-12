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
	"lava": ["lava", ["lava", "cold", "rafts"]],
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
	l.mode = Lava.Mode.STONE
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
	l.mode = Lava.Mode.STONE
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
	l.mode = Lava.Mode.STONE
	l.rises = 4
	# The room's exits are picked when it starts: the line rises with every
	# point still to score before the exit opens.
	var at_start := l.line_at(mini(4 + sim.points_to_exit(), Lava.MAX_RISES))
	assert_true(l.blocks_exit(sim, 1, at_start), "no exit where the lava will be")
	assert_false(l.blocks_exit(sim, 1, at_start - Lava.EXIT_CLEAR - SUB), "above it is fine")
	# One point before the exit (a revive plans it again then).
	sim.state.score = sim.next_exit_score() - 1
	var worst := l.line_at(5)
	assert_true(l.blocks_exit(sim, 1, worst), "no exit in the lava")
	assert_false(l.blocks_exit(sim, 1, worst - Lava.EXIT_CLEAR - SUB), "above it is fine")


func test_cold_wall_puts_ice_in_the_wall_just_left() -> void:
	var sim := _started("lava", 13)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.COLD
	sim.state.anchor_y = 300 * SUB
	sim.state.vx = -SimConfig.SPEED_X
	for p in Lava.STONE_AFTER - 1:
		sim.room.points += 1
		l.on_bounce(sim, SimRng.new(p))
	assert_false(l.ice_on, "no ice before the lava has risen enough")
	sim.room.points += 1
	l.on_bounce(sim, SimRng.new(5))
	assert_true(l.ice_on, "ice shows up")
	assert_false(l.stone_on, "and no stone")
	assert_eq(l.ice_side, 1, "on the wall the bird just left")
	var cy := SimConfig.slot_center_y(l.ice_slot)
	assert_true(absi(cy - sim.state.anchor_y) >= Lava.ICE_AWAY, "away from the anchor")
	assert_true(cy <= l.line_at(l.rises) - Lava.STONE_CLEAR, "clear of the lava")
	assert_true(cy >= SimConfig.KILL_TOP + Lava.STONE_EDGE, "clear of the ceiling")
	var all := (1 << SimConfig.SLOT_COUNT) - 1
	var mask: int = l.adjust_wall(sim, 1, all)
	for slot in range(maxi(l.ice_slot - 1, 0), mini(l.ice_slot + 2, SimConfig.SLOT_COUNT)):
		assert_false(RoomRules.has_slot(mask, slot), "no spike on or next to the ice")


## Generation never reads the bird: at any height, the same ice slot.
func test_the_ice_slot_never_depends_on_the_birds_height() -> void:
	var slots := {}
	for y: int in [120, 300, 480]:
		var sim := _started("lava", 13)
		var l: Lava = sim.room.hazards[0]
		l.mode = Lava.Mode.COLD
		sim.state.anchor_y = 300 * SUB
		sim.state.y = y * SUB
		sim.state.vx = -SimConfig.SPEED_X
		for p in Lava.STONE_AFTER:
			sim.room.points += 1
			l.on_bounce(sim, SimRng.new(5))
		assert_true(l.ice_on, "ice at bird height %d" % y)
		slots[l.ice_slot] = true
	assert_eq(slots.size(), 1, "one slot for every bird height")


func test_bouncing_on_the_ice_sinks_the_lava() -> void:
	var sim := _started("lava", 14)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.COLD
	l.rises = 4
	l.ice_on = true
	l.ice_side = 1
	l.ice_slot = 4
	var cy := SimConfig.slot_center_y(4)
	sim.state.x = sim.room.wall_right() - SimConfig.BIRD_RADIUS - 40 * SUB
	sim.state.y = cy
	l.touch(sim)
	assert_true(l.ice_on, "the ice is in the wall, not in the room")
	sim.state.x = sim.room.wall_right() - SimConfig.BIRD_RADIUS
	sim.state.y = cy + SimConfig.SLOT_SIZE + SimConfig.BIRD_RADIUS
	l.touch(sim)
	assert_true(l.ice_on, "a bounce past the ice misses it")
	sim.state.y = cy + 10 * SUB
	l.touch(sim)
	assert_false(l.ice_on, "a bounce on the ice uses it")
	assert_eq(l.rises, 0, "and sinks the lava")


func test_rafts_float_up_then_carry_and_sink_the_lava() -> void:
	var sim := _started("lava", 15)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.RAFTS
	l.raft_points = sim.room.points
	sim.room.points += Lava.RAFT_FROM
	l.on_bounce(sim, SimRng.new(3))
	assert_true(l.raft_on[0], "a raft floats up")
	assert_false(l.stone_on, "no stone")
	assert_true(l.raft_x[0] >= Lava.RAFT_X_MIN and l.raft_x[0] <= Lava.RAFT_X_MAX, "clear of walls")
	sim.room.points += 1
	l.on_bounce(sim, SimRng.new(4))
	assert_false(l.raft_on[1], "one raft at a time while the lava is low")
	for i in 200:
		l.step(sim)
	assert_eq(l.line, l.line_at(l.rises), "the lava is up")
	assert_true(l.raft_age[0] >= Lava.RAFT_RISE, "the raft is up")
	sim.state.x = l.raft_x[0]
	sim.state.y = l.line - SimConfig.BIRD_RADIUS + 2 * SUB
	sim.state.vy = 4 * SUB
	assert_false(l.kills(sim), "over the raft the lava is safe")
	var before := l.rises
	l.touch(sim)
	assert_false(l.raft_on[0], "the raft is used")
	assert_eq(l.rises, maxi(before - Lava.RAFT_SINK, 0), "the lava sinks two steps")
	assert_true(sim.state.vy < 0, "the bird is thrown up")
	sim.state.x = Lava.RAFT_X_MIN
	sim.state.y = l.line
	assert_true(l.kills(sim), "without a raft the lava kills")


func test_a_rising_raft_is_not_there_yet() -> void:
	var sim := _started("lava", 16)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.RAFTS
	l.rises = 3
	l.line = l.line_at(3)
	l.raft_on[0] = true
	l.raft_x[0] = 180 * SUB
	l.raft_age[0] = Lava.RAFT_RISE - 1
	sim.state.x = 180 * SUB
	sim.state.y = l.line - SimConfig.BIRD_RADIUS
	assert_true(l.kills(sim), "still rising: the lava kills")
	l.touch(sim)
	assert_true(l.raft_on[0], "and the raft does nothing")


func test_two_rafts_from_high_up() -> void:
	var sim := _started("lava", 17)
	var l: Lava = sim.room.hazards[0]
	l.mode = Lava.Mode.RAFTS
	l.raft_points = sim.room.points
	sim.room.points += Lava.RAFT_TWO
	l.on_bounce(sim, SimRng.new(1))
	sim.room.points += Lava.RAFT_EVERY
	l.on_bounce(sim, SimRng.new(2))
	assert_true(l.raft_on[0] and l.raft_on[1], "two rafts once the lava is high")


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
	# Generated mirror: it fits mid-height arrivals by turning round another
	# height (test_generated_variants.gd).
	assert_true(RoomCatalog.find("echo").fits_arrival(320 * SUB), "arrivals at mid height")


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
