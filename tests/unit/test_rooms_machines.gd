extends TestCase
## Machine rooms: Piston Press, Bumper Court, Crate Drop, Beam Gates,
## Stalactite Run and Hunter Spike (plus the Gift Stack and Cupid Lanes modes).

const RoomsTest := preload("res://tests/unit/test_rooms.gd")
const Piston := preload("res://sim/hazards/piston.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const Beam := preload("res://sim/hazards/beam.gd")
const Dart := preload("res://sim/hazards/dart.gd")

const SUB := SimConfig.SUB


static func _hazards(sim: GameSim, kind: String) -> Array[Hazard]:
	var out: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.kind == kind:
			out.append(h)
	return out


static func _advance(sim: GameSim, steps: int) -> void:
	for i in steps:
		sim.room.step(sim)


## Puts the bird somewhere in the room (out of the way unless a test says so).
static func _bird(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y


func test_machine_rooms_are_in_the_catalog_in_order() -> void:
	var ids: Array[String] = ["piston", "court", "crates", "beams", "stalac", "hunter"]
	var last := -1
	for id in ids:
		var i := RoomCatalog.index_of(id)
		assert_true(i > last, "%s is in the catalog after the previous room" % id)
		last = i
	assert_eq(RoomCatalog.find("hunter").group, "late")
	assert_eq(RoomCatalog.find("hunter").weight, 8)
	assert_eq(RoomCatalog.find("crates").from_score, 60)


func test_rooms_spawn_their_hazards() -> void:
	var expect := {
		"piston": ["piston", 2],
		"court": ["edge_pad", 2],
		"crates": ["crate_drop", 1],
		"beams": ["beam", 1],
		"stalac": ["stalactite", 2],
		"hunter": ["dart", 1],
	}
	for id: String in expect:
		var sim := RoomsTest.sim_in_room(id, 5)
		var want: Array = expect[id]
		assert_eq(_hazards(sim, want[0]).size(), want[1], "%s builds its hazards" % id)


## Nothing in a machine room is deadly to the bird where it starts the room.
func test_nothing_spawns_on_the_bird() -> void:
	for id: String in ["piston", "court", "crates", "beams", "stalac", "hunter"]:
		for s in 20:
			var sim := RoomsTest.sim_in_room(id, s)
			for x: int in [SimConfig.BIRD_RADIUS + 2 * SUB, SimConfig.WORLD_W - 16 * SUB]:
				for y in range(80, 560, 20):
					_bird(sim, x, y * SUB)
					for h in sim.room.hazards:
						assert_false(h.kills(sim), "%s seed %d at y %d" % [id, s, y])


# --- Piston Press -------------------------------------------------------------


func test_piston_glows_then_slams_and_kills_only_when_out() -> void:
	assert_between(Piston.GLOW_TICKS, 25, 40, "the glow lasts about half a second")
	var sim := RoomsTest.sim_in_room("piston", 3)
	var p: Hazard = _hazards(sim, "piston")[0]
	var reach_x: int = p.base_x() + (60 * SUB if p.side == 0 else -60 * SUB)
	_bird(sim, reach_x, p.y)
	var seen := {}
	var killed_in_glow := false
	var killed_out := false
	for i in p.delay + Piston.PERIOD:
		sim.room.step(sim)
		var st: int = p.state()
		seen[st] = true
		var k := p.kills(sim)
		if st == Piston.State.IDLE or st == Piston.State.GLOW:
			killed_in_glow = killed_in_glow or k
			assert_eq(p.extent(), 0, "retracted while idle or glowing")
		if st == Piston.State.HOLD:
			killed_out = killed_out or k
			assert_eq(p.extent(), Piston.REACH)
	assert_eq(seen.size(), 5, "goes through every state")
	assert_false(killed_in_glow, "the warning glow is safe")
	assert_true(killed_out, "the ram kills when out")
	# The far side of the room stays open.
	_bird(sim, p.base_x() + (300 * SUB if p.side == 0 else -300 * SUB), p.y)
	sim.room.t = p.delay + Piston.IDLE_TICKS + Piston.GLOW_TICKS + Piston.EXTEND_TICKS
	p.t = sim.room.t
	assert_eq(p.state(), Piston.State.HOLD)
	assert_false(p.kills(sim), "the ram leaves room past its reach")


# --- Bumper Court -------------------------------------------------------------


func test_court_pad_saves_the_bird_rest_of_edge_kills() -> void:
	var sim := RoomsTest.sim_in_room("court", 4)
	var pads := _hazards(sim, "edge_pad")
	for pad in pads:
		var top: bool = pad.top
		var r := SimConfig.BIRD_RADIUS
		var y := SimConfig.KILL_TOP + r - SUB if top else SimConfig.KILL_BOTTOM - r + SUB
		_bird(sim, (pad.x0() + pad.x1()) / 2, y)
		sim.state.vy = -4 * SUB if top else 4 * SUB
		assert_true(pad.guards_edge(sim, top), "pad guards its edge")
		assert_true(sim.state.vy > 0 if top else sim.state.vy < 0, "bounced back into the room")
		assert_false(pad.guards_edge(sim, not top), "only its own edge")
		# Far from the pad: not guarded.
		var away: int = (
			20 * SUB if pad.x0() > SimConfig.WORLD_W / 2 else SimConfig.WORLD_W - 20 * SUB
		)
		_bird(sim, away, y)
		assert_false(pad.guards_edge(sim, top), "edge away from the pad is not guarded")


func test_court_full_sim_bounce_on_pad_and_death_beside_it() -> void:
	# On the floor pad: the bird lives and heads up.
	var sim := RoomsTest.sim_in_room("court", 6)
	sim.state.started = true
	var floor_pad: Hazard = _hazards(sim, "edge_pad")[1]
	sim.room.step(sim)
	_bird(
		sim,
		(floor_pad.x0() + floor_pad.x1()) / 2,
		SimConfig.KILL_BOTTOM - SimConfig.BIRD_RADIUS - SUB
	)
	sim.state.vx = 0
	sim.state.vy = 4 * SUB
	sim.step(false)
	assert_true(sim.state.alive, "floor pad saves the bird")
	assert_true(sim.state.vy < 0, "and bounces it up")
	# Beside the pad: the floor kills.
	var sim2 := RoomsTest.sim_in_room("court", 6)
	sim2.state.started = true
	var pad2: Hazard = _hazards(sim2, "edge_pad")[1]
	sim2.room.step(sim2)
	var away: int = 20 * SUB if pad2.x0() > SimConfig.WORLD_W / 2 else SimConfig.WORLD_W - 60 * SUB
	_bird(sim2, away, SimConfig.KILL_BOTTOM - SimConfig.BIRD_RADIUS - SUB)
	sim2.state.vx = 0
	sim2.state.vy = 4 * SUB
	sim2.step(false)
	assert_false(sim2.state.alive, "the floor still kills away from the pad")
	assert_eq(sim2.state.death_cause, SimState.DeathCause.FLOOR)


func test_court_pads_slide() -> void:
	var sim := RoomsTest.sim_in_room("court", 2)
	var pad: Hazard = _hazards(sim, "edge_pad")[0]
	var xs := {}
	for i in 300:
		sim.room.step(sim)
		xs[pad.x0()] = true
		assert_true(pad.x0() >= 0 and pad.x1() <= SimConfig.WORLD_W, "pad stays in the room")
	assert_true(xs.size() > 50, "the pad slides along the edge")


# --- Crate Drop ---------------------------------------------------------------


func test_crates_warn_fall_and_kill() -> void:
	var sim := RoomsTest.sim_in_room("crates", 7)
	var cd: Hazard = _hazards(sim, "crate_drop")[0]
	var col: int = cd.col
	assert_true(col >= 0 and cd.warn_left > 0, "the first crate is marked before it falls")
	# During the warning the crate is not deadly even right under the marker.
	_bird(sim, cd.col_center(col), 0)
	assert_false(cd.kills(sim), "the marker is safe")
	while cd.warn_left > 0:
		sim.room.step(sim)
	_advance(sim, 10)
	assert_true(cd.falling(), "the crate falls")
	_bird(sim, cd.col_center(col), cd.y + CrateDrop.CRATE / 2)
	assert_true(cd.kills(sim), "a falling crate kills")
	# Let it land; then its stack kills.
	while cd.heights[col] == 0:
		sim.room.step(sim)
	_bird(sim, cd.col_center(col), cd.stack_top(col) - SimConfig.BIRD_RADIUS + SUB)
	assert_true(cd.kills(sim), "the top of a stack kills")
	_bird(sim, cd.col_center(col), cd.stack_top(col) - SimConfig.BIRD_RADIUS - 4 * SUB)
	if not cd.falling() or cd.col != col:
		assert_false(cd.kills(sim), "just above the stack is safe")


func test_crates_always_leave_a_path() -> void:
	for s in 10:
		var sim := RoomsTest.sim_in_room("crates", s)
		var cd: Hazard = _hazards(sim, "crate_drop")[0]
		for i in 6000:
			sim.room.step(sim)
			if i % 200 == 0:
				for c in CrateDrop.COLS:
					assert_true(cd.heights[c] <= CrateDrop.MAX_HEIGHT, "column height capped")
		var lowest_top := SimConfig.WORLD_H
		for c in CrateDrop.COLS:
			lowest_top = mini(lowest_top, cd.stack_top(c))
		# Every column full still leaves a tall open band above the stacks.
		assert_true(lowest_top - SimConfig.KILL_TOP >= 300 * SUB, "room to fly above the stacks")
		assert_eq(cd.col, -1, "stops dropping once every column is full")


func test_crate_columns_stay_clear_of_the_walls() -> void:
	var cd := CrateDrop.new()
	assert_true(cd.col_left(0) >= SimConfig.SPIKE_DEPTH, "clear of the left wall spikes")
	assert_true(
		(
			cd.col_left(CrateDrop.COLS - 1) + CrateDrop.CRATE
			<= SimConfig.WORLD_W - SimConfig.SPIKE_DEPTH
		),
		"clear of the right wall spikes"
	)


func test_gift_stack_puts_a_coin_on_each_new_stack() -> void:
	var def := RoomDef.new("gift_test", "seasonal", 0)
	def.skin = "gift"
	def.hazards.append(func() -> Hazard: return CrateDrop.new())
	var sim := GameSim.new(8)
	sim.room.start(def, 0, sim, SimRng.new(8))
	var cd: Hazard = sim.room.hazards[0]
	assert_true(cd.gifts, "the gift skin turns on gifts")
	var col: int = cd.col
	while cd.heights[col] == 0:
		sim.room.step(sim)
	assert_eq(cd.coins[col], 1, "a coin sits on the new stack")
	_bird(sim, cd.col_center(col), cd.coin_y(col))
	assert_false(cd.kills(sim), "the coin spot is safe")
	cd.touch(sim)
	assert_eq(sim.state.coins, 1, "the coin is collected")
	assert_eq(cd.coins[col], 0)
	cd.touch(sim)
	assert_eq(sim.state.coins, 1, "only once")
	# Plain crates never carry coins.
	var plain := RoomsTest.sim_in_room("crates", 8)
	var pc: Hazard = _hazards(plain, "crate_drop")[0]
	_advance(plain, 2000)
	for c in CrateDrop.COLS:
		assert_eq(pc.coins[c], 0)


# --- Beam Gates ---------------------------------------------------------------


func test_beams_warn_before_firing_and_kill_only_when_live() -> void:
	var sim := RoomsTest.sim_in_room("beams", 9)
	var b: Hazard = _hazards(sim, "beam")[0]
	for i in Beam.ROWS:
		var prev := Beam.State.OFF
		var warned := false
		var fired := false
		for tick in Beam.START_DELAY + Beam.PERIOD * 2:
			b.t = tick
			var st: int = b.state(i)
			if st == Beam.State.WARN:
				warned = true
			if st == Beam.State.ON:
				assert_true(prev != Beam.State.OFF, "row %d warns before it fires" % i)
				fired = true
			prev = st as Beam.State
			_bird(sim, SimConfig.WORLD_W / 2, b.rows[i])
			var only_this := true
			for j in Beam.ROWS:
				if j != i and b.state(j) == Beam.State.ON:
					only_this = false
			if only_this:
				assert_eq(b.kills(sim), st == Beam.State.ON, "row %d kills only when live" % i)
		assert_true(warned and fired, "row %d warns and fires" % i)


func test_beams_never_more_than_two_and_never_all_rows() -> void:
	for s in 10:
		var sim := RoomsTest.sim_in_room("beams", s)
		var b: Hazard = _hazards(sim, "beam")[0]
		var max_live := 0
		for tick in 1000:
			b.t = tick
			max_live = maxi(max_live, b.live_count())
		assert_true(max_live <= 2, "at most two beams at once")
		assert_true(max_live < Beam.ROWS, "never all rows")
		for i in Beam.ROWS:
			assert_true(b.rows[i] > SimConfig.KILL_TOP + 60 * SUB, "clear of the ceiling")
			assert_true(b.rows[i] < SimConfig.KILL_BOTTOM - 60 * SUB, "clear of the floor")
		# Nothing live right as the room starts.
		b.t = 0
		assert_eq(b.live_count(), 0)


# --- Stalactite Run -----------------------------------------------------------


func test_stalactites_kill_and_leave_a_gap() -> void:
	var sim := RoomsTest.sim_in_room("stalac", 10)
	for st in _hazards(sim, "stalactite"):
		assert_true(st.bottom_tip() - st.top_tip() >= 120 * SUB, "gap at least 120 px")
		_bird(sim, st.x, st.gap_y)
		assert_false(st.kills(sim), "the middle of the gap is safe")
		_bird(sim, st.x, st.top_tip() - 10 * SUB)
		assert_true(st.kills(sim), "the hanging rock kills")
		_bird(sim, st.x, st.bottom_tip() + 10 * SUB)
		assert_true(st.kills(sim), "the standing rock kills")


func test_stalactites_move_on_bounce() -> void:
	var sim := RoomsTest.sim_in_room("stalac", 11)
	var rocks := _hazards(sim, "stalactite")
	var moved := false
	for n in 8:
		var before: int = rocks[0].target_y
		var rng := SimRng.new(100 + n)
		for h in rocks:
			h.on_bounce(sim, rng)
		if rocks[0].target_y != before:
			moved = true
		for h in rocks:
			assert_between(h.target_y, 150 * SUB, 490 * SUB, "gap stays in the room")
		assert_true(absi(rocks[1].target_y - rocks[0].target_y) <= 120 * SUB, "gaps stay reachable")
	assert_true(moved, "gaps get new heights after bounces")
	# The gap slides to its new height rather than jumping.
	var r: Hazard = rocks[0]
	var start: int = r.gap_y
	sim.room.step(sim)
	assert_true(absi(r.gap_y - start) <= 3 * SUB, "slides smoothly")
	_advance(sim, 200)
	assert_eq(r.gap_y, r.target_y, "arrives")


func test_stalactites_shift_after_a_real_wall_bounce() -> void:
	var changes := 0
	for seed_value in 10:
		var sim := RoomsTest.sim_in_room("stalac", 30 + seed_value)
		var rock: Hazard = _hazards(sim, "stalactite")[0]
		var before: int = rock.target_y
		sim.state.started = true
		_bird(sim, SimConfig.WORLD_W - SimConfig.BIRD_RADIUS - 2 * SUB, 300 * SUB)
		sim.state.vx = SimConfig.SPEED_X
		sim.state.vy = 0
		sim.step(false)
		assert_eq(sim.state.score, 1, "the bird bounced off the wall")
		if rock.target_y != before:
			changes += 1
	assert_true(changes >= 8, "a wall bounce moves the gap")


# --- Hunter Spike / Cupid Lanes ---------------------------------------------


func test_hunter_aims_at_bird_height_glows_then_fires() -> void:
	var sim := RoomsTest.sim_in_room("hunter", 13)
	var d: Hazard = _hazards(sim, "dart")[0]
	_bird(sim, 40 * SUB, 250 * SUB)
	while d.state == Dart.State.IDLE:
		sim.room.step(sim)
	assert_eq(d.state, Dart.State.GLOW)
	assert_eq(d.lane_y, 250 * SUB, "the lane is at the bird's height")
	assert_eq(d.side, 1, "fires from the far wall")
	# The lane stays put even if the bird moves during the warning.
	_bird(sim, 40 * SUB, 400 * SUB)
	sim.room.step(sim)
	assert_eq(d.lane_y, 250 * SUB)
	# Glowing never kills, even on the lane.
	_bird(sim, SimConfig.WORLD_W - 10 * SUB, 250 * SUB)
	assert_false(d.kills(sim), "the glow is a warning only")
	var glow_steps := 1
	while d.state == Dart.State.GLOW:
		sim.room.step(sim)
		glow_steps += 1
	assert_between(glow_steps, 30, 50, "about two thirds of a second of warning")
	assert_eq(d.state, Dart.State.FLY)
	# The dart crosses the room and kills on its lane.
	var hit := false
	_bird(sim, SimConfig.WORLD_W / 2, 250 * SUB)
	for i in 80:
		sim.room.step(sim)
		hit = hit or d.kills(sim)
	assert_true(hit, "the dart kills on its lane")
	assert_eq(d.state, Dart.State.IDLE, "and is gone after crossing")


func test_hunter_misses_off_its_lane() -> void:
	var sim := RoomsTest.sim_in_room("hunter", 14)
	var d: Hazard = _hazards(sim, "dart")[0]
	_bird(sim, 40 * SUB, 200 * SUB)
	while d.state != Dart.State.FLY:
		sim.room.step(sim)
	_bird(sim, SimConfig.WORLD_W / 2, 260 * SUB)
	for i in 80:
		sim.room.step(sim)
		assert_false(d.kills(sim), "safe 60 px off the lane")


func test_cupid_lanes_flash_then_cross_at_most_two() -> void:
	var def := RoomDef.new("cupid_test", "seasonal", 0)
	def.skin = "cupid"
	def.hazards.append(func() -> Hazard: return Dart.new(false, 0))
	def.hazards.append(func() -> Hazard: return Dart.new(false, 1))
	var sim := GameSim.new(15)
	sim.room.start(def, 0, sim, SimRng.new(15))
	var darts: Array[Hazard] = []
	darts.assign(sim.room.hazards)
	for d in darts:
		assert_true(d.lanes, "the cupid skin turns on lanes mode")
	var lanes_seen := {}
	var killed_in_flash := false
	for i in 3000:
		sim.room.step(sim)
		var busy := 0
		for d in darts:
			if d.state != Dart.State.IDLE:
				busy += 1
				lanes_seen[d.lane_y] = true
				assert_true((d.lane_y - Dart.LANE_MIN) % Dart.LANE_STEP == 0, "arrows fly on lanes")
			if d.state == Dart.State.GLOW:
				_bird(sim, SimConfig.WORLD_W / 2, d.lane_y)
				killed_in_flash = killed_in_flash or d.kills(sim)
		assert_true(busy <= 2, "at most two lanes at once")
	assert_false(killed_in_flash, "a flashing lane is safe")
	assert_true(lanes_seen.size() >= 4, "the rng picks different lanes")


func test_machine_rooms_replay_the_same() -> void:
	for id: String in ["piston", "court", "crates", "beams", "stalac", "hunter"]:
		var a := RoomsTest._run_room(id, 21)
		var b := RoomsTest._run_room(id, 21)
		assert_eq(a, b, "%s is deterministic" % id)
		var c := RoomsTest._run_room(id, 22)
		assert_ne(a, c, "%s depends on the seed" % id)
