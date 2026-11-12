extends TestCase
## Crowded's walls that keep their crowd (sim/hazards/crowd_fill.gd) and the
## Buttons room (sim/hazards/button_pair.gd).

const CrowdFill := preload("res://sim/hazards/crowd_fill.gd")
const ButtonPair := preload("res://sim/hazards/button_pair.gd")

const SUB := SimConfig.SUB
const R := SimConfig.BIRD_RADIUS


## A sim in room `id` playing variant `variant`, the bird not started yet.
static func sim_in(id: String, variant: String, seed_value: int = 3) -> GameSim:
	var index := RoomCatalog.index_of(id)
	return GameSim.new(seed_value, RoomCatalog.all()[index].season, index, variant)


static func _bits(mask: int) -> int:
	var n := 0
	for slot in SimConfig.SLOT_COUNT:
		n += (mask >> slot) & 1
	return n


# --- Crowded ------------------------------------------------------------------


func test_every_crowded_variant_keeps_a_crowd() -> void:
	for v: String in ["classic", "lopsided", "storm"]:
		var sim := sim_in("crowded", v)
		assert_eq(sim.room.variant_id(), v, "%s forced" % v)
		assert_eq(sim.room.hazards.size(), 1, "%s: one hazard" % v)
		assert_eq(sim.room.hazards[0].kind, "crowd_fill", "%s: the crowd" % v)


func test_seated_spikes_stay_unless_the_free_run_needs_them() -> void:
	for seed_value in 30:
		var sim := sim_in("crowded", "classic", seed_value)
		var c: CrowdFill = sim.room.hazards[0]
		for i in 14:
			var side := i % 2
			var before := c.seats(side) | c.coming(side)
			sim._new_wall(side)
			var mask := sim.state.left_spikes if side == 0 else sim.state.right_spikes
			var run := c.last_run
			assert_eq(mask, c.seats(side), "the wall shows its crowd")
			assert_eq(mask & before, before & ~run, "nobody leaves but from the free run")
			assert_true(
				RoomRules.longest_gap(mask) >= sim.room.def.gap, "a run of free slots stays"
			)


func test_the_crowd_grows_over_the_room() -> void:
	var grew := 0
	for seed_value in 30:
		var sim := sim_in("crowded", "classic", seed_value)
		sim._new_wall(0)
		sim._new_wall(1)
		var first := _bits(sim.state.left_spikes) + _bits(sim.state.right_spikes)
		for i in 10:
			sim._new_wall(i % 2)
		var c: CrowdFill = sim.room.hazards[0]
		var last := _bits(c.seats(0)) + _bits(c.seats(1))
		if last > first + 3:
			grew += 1
	assert_true(grew >= 25, "the walls fill up (%d of 30)" % grew)


func test_newcomers_pick_seats_on_the_wall_just_left() -> void:
	var sim := sim_in("crowded", "classic", 5)
	var c: CrowdFill = sim.room.hazards[0]
	sim._new_wall(1)
	sim._new_wall(0)
	assert_eq(_bits(c.coming(1)), 1, "one newcomer on the right wall")
	assert_eq(c.coming(1) & c.seats(1), 0, "on a free seat")
	assert_eq(c.coming(0), 0, "none on the wall ahead")


func test_lopsided_fills_only_the_left_wall() -> void:
	for seed_value in 20:
		var sim := sim_in("crowded", "lopsided", seed_value)
		var c: CrowdFill = sim.room.hazards[0]
		for i in 12:
			sim._new_wall(i % 2)
			assert_eq(c.coming(1), 0, "nobody walks to the right wall")
			assert_true(_bits(c.seats(1)) <= CrowdFill.START, "the right wall stays light")


func test_storm_starts_light_and_fills_fast() -> void:
	var sim := sim_in("crowded", "storm", 4)
	var c: CrowdFill = sim.room.hazards[0]
	sim._new_wall(0)
	assert_true(_bits(c.seats(0)) <= 1, "one seat to start")
	assert_eq(_bits(c.coming(1)), 2, "two newcomers a bounce")


func test_the_crowd_comes_from_the_seed_not_the_bird() -> void:
	var a := sim_in("crowded", "classic", 12)
	var b := sim_in("crowded", "classic", 12)
	b.state.y = 120 * SUB
	b.state.vy = 3 * SUB
	for i in 10:
		a._new_wall(i % 2)
		b._new_wall(i % 2)
		assert_eq(a.state.left_spikes, b.state.left_spikes, "same left wall")
		assert_eq(a.state.right_spikes, b.state.right_spikes, "same right wall")


# --- Buttons ------------------------------------------------------------------


func test_buttons_room_and_variants() -> void:
	var def := RoomCatalog.find("buttons")
	assert_true(def != null, "the room exists")
	assert_false(def.bounce_points, "bounces don't score")
	assert_true(RoomInfo.ROOMS.has("buttons"), "has room info")
	var ids: Array[String] = []
	for v in def.variants:
		ids.append(v.id)
	assert_eq(ids, ["classic", "slim", "apart"])


func test_a_wall_bounce_scores_nothing() -> void:
	var sim := sim_in("buttons", "classic")
	var score := sim.state.score
	sim.state.x = SimConfig.WORLD_W - R
	sim.state.vx = SimConfig.SPEED_X
	sim.state.right_spikes = 0
	sim._check_walls()
	assert_true(sim.state.vx < 0, "it bounced")
	assert_eq(sim.state.score, score, "but scored nothing")


func test_pressing_the_lit_button_scores_and_lights_the_other() -> void:
	var sim := sim_in("buttons", "classic")
	var b: ButtonPair = sim.room.hazards[0]
	var score := sim.state.score
	assert_true(b.lit_top, "the top one first")
	_press(sim, b, true)
	assert_true(sim.state.alive, "a press never kills")
	assert_eq(sim.state.score, score + 1, "a point")
	assert_false(b.lit_top, "the bottom one is next")
	assert_true(sim.state.vy > 0, "pushed back down")
	_press(sim, b, true)
	assert_true(sim.state.alive, "pressing it again still bounces")
	assert_eq(sim.state.score, score + 1, "but scores nothing")
	_press(sim, b, false)
	assert_eq(sim.state.score, score + 2, "the bottom one scores")
	assert_true(sim.state.vy < 0, "and throws the bird up")
	assert_eq(b.presses, 2)


func test_beside_a_button_the_edge_still_kills() -> void:
	var sim := sim_in("buttons", "slim")
	var b: ButtonPair = sim.room.hazards[0]
	var x := b.x1(true) + ButtonPair.GRACE + 4 * SUB
	if x > SimConfig.WORLD_W - R:
		x = b.x0(true) - ButtonPair.GRACE - 4 * SUB
	sim.state.x = x
	sim.state.y = SimConfig.KILL_TOP + R - SUB
	sim._check_ceiling_floor()
	assert_false(sim.state.alive, "the ceiling kills beside the button")


func test_presses_wait_for_the_exit_once_it_is_due() -> void:
	var sim := sim_in("buttons", "classic")
	var b: ButtonPair = sim.room.hazards[0]
	var start := sim.state.score
	for i in SimConfig.POINTS_PER_ROOM:
		_press(sim, b, b.lit_top)
	assert_eq(sim.state.score, start + SimConfig.POINTS_PER_ROOM, "ten presses")
	_press(sim, b, b.lit_top)
	assert_eq(sim.state.score, start + SimConfig.POINTS_PER_ROOM, "no eleventh before the exit")
	sim.state.x = SimConfig.WORLD_W - R
	sim.state.vx = SimConfig.SPEED_X
	sim.state.right_spikes = 0
	sim._check_walls()
	assert_true(sim.state.exit_open, "the next bounce opens the exit")


func test_buttons_sit_on_the_grid_and_come_from_the_seed() -> void:
	for v: String in ["classic", "slim", "apart"]:
		var spots := {}
		for seed_value in 60:
			var sim := sim_in("buttons", v, seed_value)
			var b: ButtonPair = sim.room.hazards[0]
			for top: bool in [true, false]:
				var x0 := b.x0(top)
				assert_eq((x0 - ButtonPair.MARGIN) % ButtonPair.GRID, 0, "%s on the grid" % v)
				assert_true(x0 >= ButtonPair.MARGIN, "%s off the left wall" % v)
				assert_true(
					b.x1(top) <= SimConfig.WORLD_W - ButtonPair.MARGIN, "%s off the right wall" % v
				)
			spots[b.top_x0 * 1000 + b.bottom_x0] = true
			var again: ButtonPair = sim_in("buttons", v, seed_value).room.hazards[0]
			assert_eq(again.top_x0, b.top_x0, "%s: same seed, same top" % v)
			assert_eq(again.bottom_x0, b.bottom_x0, "%s: same seed, same bottom" % v)
		assert_true(spots.size() > 20, "%s: many spots (%d)" % [v, spots.size()])


func test_apart_puts_the_buttons_in_opposite_halves() -> void:
	var mid := SimConfig.WORLD_W / 2
	for seed_value in 80:
		var b: ButtonPair = sim_in("buttons", "apart", seed_value).room.hazards[0]
		var top := b.top_x0 + b.width / 2
		var bottom := b.bottom_x0 + b.width / 2
		assert_true((top < mid) != (bottom < mid), "other half")
		assert_true(absi(top - bottom) >= ButtonPair.APART_MIN, "far enough apart")


func test_buttons_walls_do_not_follow_the_presses() -> void:
	var a := sim_in("buttons", "classic", 21)
	var b := sim_in("buttons", "classic", 21)
	var bp: ButtonPair = b.room.hazards[0]
	for i in 12:
		if i % 3 == 0:
			_press(b, bp, bp.lit_top)
		a._new_wall(i % 2)
		b._new_wall(i % 2)
		assert_eq(a.state.left_spikes, b.state.left_spikes, "same left wall")
		assert_eq(a.state.right_spikes, b.state.right_spikes, "same right wall")
	assert_true(b.state.score > a.state.score, "though one pressed")


## The bird touches button `top` from inside the room, over its middle.
func _press(sim: GameSim, b: ButtonPair, top: bool) -> void:
	sim.state.alive = true
	sim.state.x = (b.x0(top) + b.x1(top)) / 2
	if top:
		sim.state.y = SimConfig.KILL_TOP + R - SUB
		sim.state.vy = SimConfig.FLAP_VY
	else:
		sim.state.y = SimConfig.KILL_BOTTOM - R + SUB
		sim.state.vy = SimConfig.MAX_FALL_VY
	sim._check_ceiling_floor()
