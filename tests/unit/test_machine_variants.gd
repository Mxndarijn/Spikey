extends TestCase
## Variants of Piston Press (double slam, ladder), Stalactite Run (floor fangs,
## ceiling only, alternating, short fangs), Crate Drop and Gift Stack (wide,
## pairs), and the landing look of crate stacks (floor spikes sink).

const RoomsTest := preload("res://tests/unit/test_rooms.gd")
const Piston := preload("res://sim/hazards/piston.gd")
const CrateDrop := preload("res://sim/hazards/crate_drop.gd")
const CratePainter := preload("res://game/run/painters/crate_drop_painter.gd")

const SUB := SimConfig.SUB
const R := SimConfig.BIRD_RADIUS


static func _sim(id: String, variant: String, seed_value: int) -> GameSim:
	var season := Seasons.WINTER if id == "gifts" else Seasons.NONE
	return RoomsTest.sim_in_room(id, seed_value, season, variant)


static func _hazards(sim: GameSim, kind: String) -> Array[Hazard]:
	var out: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.kind == kind:
			out.append(h)
	return out


static func _bird(sim: GameSim, x: int, y: int) -> void:
	sim.state.x = x
	sim.state.y = y


static func _bounce(sim: GameSim, seed_value: int) -> void:
	var rng := SimRng.new(seed_value)
	for h in sim.room.hazards:
		h.on_bounce(sim, rng)


func test_rooms_have_their_variants() -> void:
	var want := {
		"piston": ["classic", "double-slam", "ladder"],
		"stalac": ["classic", "floor", "ceiling-only", "alternating", "short-fangs"],
		"crates": ["classic", "wide", "pairs"],
		"gifts": ["classic", "wide", "pairs"],
	}
	for id: String in want:
		var ids := []
		for v in RoomCatalog.find(id).variants:
			ids.append(v.id)
		assert_eq(ids, want[id], "%s variants" % id)
		assert_true(RoomCatalog.find(id).hazards.is_empty(), "%s: hazards only in variants" % id)


# --- Piston Press -------------------------------------------------------------


func test_double_slam_fires_both_rams_together_at_one_height() -> void:
	for s in 6:
		var sim := _sim("piston", "double-slam", s)
		var ps := _hazards(sim, "piston")
		assert_eq(ps.size(), 2, "two pistons")
		var a: Hazard = ps[0]
		var b: Hazard = ps[1]
		assert_ne(a.side, b.side, "one in each wall")
		assert_true(a.glow_ticks >= 60, "a 1 s warning")
		var heights := {}
		for i in 900:
			sim.room.step(sim)
			if i % 37 == 0 and a.state() == Piston.State.IDLE:
				_bounce(sim, s * 100 + i)
			assert_eq(a.y, b.y, "same height")
			assert_eq(a.state(), b.state(), "fire together")
			heights[a.y] = true
			if a.state() == Piston.State.HOLD:
				var gap: int = b.tip_x() - a.tip_x()
				assert_true(gap >= 2 * R + 20 * SUB, "a gap between the two tips")
				# The middle of the gap is safe, the rams are not.
				_bird(sim, (a.tip_x() + b.tip_x()) / 2, a.y)
				assert_false(a.kills(sim) or b.kills(sim), "the middle is open")
				_bird(sim, a.tip_x() - 30 * SUB, a.y)
				assert_true(a.kills(sim), "the left ram kills")
		assert_true(heights.size() >= 2, "the slam height moves between bounces")
		assert_between(a.y, Piston.Y_MIN, Piston.Y_MAX, "inside the room")


func test_ladder_fires_top_to_bottom_at_fixed_heights() -> void:
	var sim := _sim("piston", "ladder", 4)
	var ps := _hazards(sim, "piston")
	assert_eq(ps.size(), 3, "three rungs")
	var ys: Array[int] = []
	for p in ps:
		assert_eq(p.side, 1, "all in one wall")
		ys.append(p.y)
	for i in 2:
		assert_true(ys[i] < ys[i + 1], "listed top to bottom")
		var free: int = (ys[i + 1] - Piston.HALF_H) - (ys[i] + Piston.HALF_H)
		assert_true(free >= 2 * R + 40 * SUB, "room for the bird between rungs")
	# Each rung starts its slam after the one above it.
	var first_out := [-1, -1, -1]
	for t in 400:
		sim.room.step(sim)
		if t % 50 == 0:
			_bounce(sim, t)
		for i in 3:
			assert_eq(ps[i].y, ys[i], "rung %d never moves" % i)
			if first_out[i] < 0 and ps[i].extent() > 0:
				first_out[i] = t
	assert_true(first_out[0] >= 0, "the top rung fires")
	assert_true(first_out[0] < first_out[1] and first_out[1] < first_out[2], "a wave downwards")
	# Never all three out at once: there is always a way to the wall.
	for t in 2000:
		sim.room.step(sim)
		var out := 0
		for p in ps:
			if p.extent() > 0:
				out += 1
		assert_true(out < 3, "never all rungs out")


# --- Stalactite Run -----------------------------------------------------------


func test_floor_fangs_and_ceiling_only_have_one_rock() -> void:
	for v: String in ["floor", "ceiling-only"]:
		var sim := _sim("stalac", v, 12)
		var rocks := _hazards(sim, "stalactite")
		assert_eq(rocks.size(), 2, "%s: two columns" % v)
		_advance(sim, 1)
		for n in 6:
			_bounce(sim, 40 + n)
			_advance(sim, 120)
			for st in rocks:
				var ceiling := v == "ceiling-only"
				assert_eq(st.top, ceiling, "%s: hanging rock" % v)
				assert_eq(st.bottom, not ceiling, "%s: standing rock" % v)
				# The open side is open all the way to the edge.
				var open_y := SimConfig.KILL_TOP + R + SUB
				if ceiling:
					open_y = SimConfig.KILL_BOTTOM - R - SUB
				_bird(sim, st.x, open_y)
				assert_false(st.kills(sim), "%s: the open side is clear" % v)
				# The rock still kills, and the gap's middle is safe.
				var rock_y: int = st.top_tip() - 10 * SUB if ceiling else st.bottom_tip() + 10 * SUB
				_bird(sim, st.x, rock_y)
				assert_true(st.kills(sim), "%s: the rock kills" % v)
				_bird(sim, st.x, st.gap_y)
				assert_false(st.kills(sim), "%s: the gap is safe" % v)


func test_alternating_fingers_hang_stand_hang_around_a_still_middle() -> void:
	for y_px: int in [240, 320, 400]:
		var sim := RoomsTest.sim_in_room("stalac", 7, Seasons.NONE, "alternating")
		sim.state.y = y_px * SUB
		for h in sim.room.hazards:
			h.setup(sim, SimRng.new(1))
		var rocks := _hazards(sim, "stalactite")
		assert_eq(rocks.size(), 3, "three columns")
		for i in 3:
			assert_eq(rocks[i].top, i % 2 == 0, "column %d hangs" % i)
			assert_eq(rocks[i].bottom, i % 2 == 1, "column %d stands" % i)
		var middle: int = rocks[0].gap_y
		assert_between(middle, (y_px - 80) * SUB, (y_px + 80) * SUB, "starts near the bird")
		_advance(sim, 1)
		for n in 6:
			_bounce(sim, n)
			_advance(sim, 100)
			for st in rocks:
				assert_eq(st.gap_y, middle, "the middle never moves")
		# A bird in the middle passes every column.
		for st in rocks:
			_bird(sim, st.x, middle)
			assert_false(st.kills(sim), "the open middle is safe")
		assert_true(rocks[0].bottom_tip() - rocks[0].top_tip() >= 140 * SUB, "a big middle")
		# The fingers are long: they reach past a third of the room.
		assert_true(rocks[0].top_tip() >= 180 * SUB, "long hanging finger")
		assert_true(rocks[1].bottom_tip() <= 460 * SUB, "long standing finger")


func test_short_fangs_leave_a_300_px_corridor_that_never_moves() -> void:
	var sim := _sim("stalac", "short-fangs", 3)
	var rocks := _hazards(sim, "stalactite")
	assert_eq(rocks.size(), 3, "three columns")
	_advance(sim, 1)
	for n in 6:
		_bounce(sim, n)
		_advance(sim, 100)
		for st in rocks:
			assert_eq(st.bottom_tip() - st.top_tip(), 300 * SUB, "a 300 px corridor")
			assert_eq(st.gap_y, 320 * SUB, "in the middle, never moving")
			_bird(sim, st.x, st.top_tip() + R + SUB)
			assert_false(st.kills(sim), "the corridor's top edge is clear")
			_bird(sim, st.x, st.top_tip() - 10 * SUB)
			assert_true(st.kills(sim), "the short rock kills")


## Out of a portal the three-column variants only come where the bird
## holding its height passes every column.
func test_still_columns_only_come_out_of_a_portal_where_they_fit() -> void:
	var def := RoomCatalog.find("stalac")
	for v in def.variants:
		if v.id != "alternating" and v.id != "short-fangs":
			continue
		for y_px in range(90, 560, 10):
			if not v.fits_arrival(y_px * SUB):
				continue
			var sim := RoomsTest.sim_in_room("stalac", 2, Seasons.NONE, v.id)
			sim.state.y = y_px * SUB
			for h in sim.room.hazards:
				h.setup(sim, SimRng.new(1))
			for st in _hazards(sim, "stalactite"):
				# Holding height: it hops up to about 62 px and sinks back.
				for dy in range(-64, 3, 4):
					_bird(sim, st.x, (y_px + dy) * SUB)
					assert_false(st.kills(sim), "%s at %d px" % [v.id, y_px])


# --- Crate Drop / Gift Stack --------------------------------------------------


func test_crate_variants_cap_their_stacks_and_stay_off_the_walls() -> void:
	for id: String in ["crates", "gifts"]:
		for v: String in ["classic", "wide", "pairs"]:
			for s in 4:
				var sim := _sim(id, v, s)
				var cd: Hazard = _hazards(sim, "crate_drop")[0]
				assert_eq(cd.gifts, id == "gifts", "%s %s gifts" % [id, v])
				assert_true(cd.col_left(0) >= SimConfig.SPIKE_DEPTH, "clear of the left wall")
				var right: int = cd.col_left(cd.cols - 1) + cd.crate_w
				assert_true(right <= SimConfig.WORLD_W - SimConfig.SPIKE_DEPTH, "and the right")
				_advance(sim, 6000)
				var lowest_top := SimConfig.WORLD_H
				for c in cd.cols:
					assert_true(cd.heights[c] <= cd.max_height, "column height capped")
					lowest_top = mini(lowest_top, cd.stack_top(c))
				assert_true(
					lowest_top - SimConfig.KILL_TOP >= 300 * SUB, "%s %s: room above" % [id, v]
				)
				assert_eq(cd.col, -1, "stops once every column is full")


func test_wide_crates_are_bigger() -> void:
	var sim := _sim("crates", "wide", 1)
	var cd: Hazard = _hazards(sim, "crate_drop")[0]
	assert_true(cd.crate_w >= 60 * SUB, "wide crates")
	assert_true(cd.cols < CrateDrop.COLS, "in fewer columns")
	var col: int = cd.col
	while cd.heights[col] == 0:
		sim.room.step(sim)
	# The whole width of the stack kills, right to its edges.
	var x0: int = cd.col_left(col)
	for x: int in [x0 + SUB, x0 + cd.crate_w / 2, x0 + cd.crate_w - SUB]:
		_bird(sim, x, cd.stack_top(col) - R + SUB)
		assert_true(cd.kills(sim), "the stack kills over its width")


func test_pairs_drop_two_crates_at_once_in_different_columns() -> void:
	for id: String in ["crates", "gifts"]:
		var sim := _sim(id, "pairs", 5)
		var cd: Hazard = _hazards(sim, "crate_drop")[0]
		var pairs := 0
		for _r in 6:
			var a: int = cd.col
			var b: int = cd.col_b
			if a < 0:
				break
			assert_true(b >= 0 and b != a, "a second crate in another column")
			while cd.warn_left > 0:
				sim.room.step(sim)
			_advance(sim, 5)
			assert_true(cd.falling(), "both fall")
			_bird(sim, cd.col_center(a), cd.y + cd.crate_h / 2)
			assert_true(cd.kills(sim), "crate a kills")
			_bird(sim, cd.col_center(b), cd.y_b + cd.crate_h / 2)
			assert_true(cd.kills(sim), "crate b kills")
			var ha: int = cd.heights[a]
			var hb: int = cd.heights[b]
			var drops: int = cd.drops
			while cd.drops == drops:
				sim.room.step(sim)
			assert_eq(cd.heights[a], ha + 1, "crate a landed")
			assert_eq(cd.heights[b], hb + 1, "crate b landed")
			pairs += 1
		assert_true(pairs >= 4, "%s: pairs keep coming" % id)


func test_gift_variants_put_a_coin_on_new_stacks() -> void:
	for v: String in ["wide", "pairs"]:
		var sim := _sim("gifts", v, 6)
		var cd: Hazard = _hazards(sim, "crate_drop")[0]
		var col: int = cd.col
		while cd.heights[col] == 0:
			sim.room.step(sim)
		assert_eq(cd.coins[col], 1, "%s: a coin on the new stack" % v)
		_bird(sim, cd.col_center(col), cd.coin_y(col))
		assert_false(cd.kills(sim), "%s: the coin spot is safe" % v)


# --- Landing look -------------------------------------------------------------


## Floor spikes wholly under a new stack sink over SINK_TIME; the others stay.
func test_floor_spikes_sink_only_under_a_stack() -> void:
	for v: String in ["classic", "wide", "pairs"]:
		var sim := _sim("crates", v, 2)
		var cd: Hazard = _hazards(sim, "crate_drop")[0]
		var painter := CratePainter.new()
		painter._track_landings(cd, 0.0)
		var col: int = cd.col
		while cd.heights[col] == 0:
			sim.room.step(sim)
		painter._track_landings(cd, 1.0)
		var left := HazardLayer.px(cd.col_left(col))
		var right := left + HazardLayer.px(cd.crate_w)
		var step := 40.0
		var under := 0
		for i in 9:
			var a := step * i
			var b := a + step
			var sink := painter.floor_sink(cd, a, b)
			assert_eq(sink, 0.0, "%s: nothing sunk the moment it lands" % v)
			painter._track_landings(cd, 1.0 + CratePainter.SINK_TIME)
			sink = painter.floor_sink(cd, a, b)
			painter._track_landings(cd, 1.0)
			var inside := (
				a >= left - CratePainter.SINK_SLACK and b <= right + CratePainter.SINK_SLACK
			)
			var other_stack := false
			for c in cd.cols:
				if c != col and cd.heights[c] > 0:
					other_stack = true
			if not other_stack:
				assert_eq(sink, 1.0 if inside else 0.0, "%s: spike %d" % [v, i])
			if inside:
				under += 1
				# The sim kills over the whole sunk spike: no safe spot appears.
				for x in [a + 2.0, (a + b) / 2.0, b - 2.0]:
					var bx := int(clampf(x, left, right) * SUB)
					_bird(sim, bx, SimConfig.KILL_BOTTOM - R)
					assert_true(cd.kills(sim), "%s: the sunk spot still kills" % v)
		assert_true(under >= 1, "%s: a spike sinks under the stack" % v)


static func _advance(sim: GameSim, steps: int) -> void:
	for i in steps:
		sim.room.step(sim)


## A still column next to a wall keeps that wall's exit inside its gap; a
## moving one never blocks (its gap follows the bird).
func test_still_columns_keep_the_exit_in_reach() -> void:
	for v: String in ["alternating", "short-fangs", "classic"]:
		var sim := _sim("stalac", v, 9)
		for side in 2:
			sim.state.exit_side = side
			var open := 0
			for slot in SimConfig.SLOT_COUNT:
				var y := SimConfig.slot_center_y(slot)
				if ExitPlanner.blocked(sim, y):
					continue
				open += 1
				for st in _hazards(sim, "stalactite"):
					var wall := 0 if side == 0 else SimConfig.WORLD_W
					if absi(st.x - wall) > 120 * SUB:
						continue
					_bird(sim, st.x, y)
					assert_false(st.kills(sim), "%s: exit at %d px past the column" % [v, y / SUB])
			if v == "classic":
				assert_eq(open, SimConfig.SLOT_COUNT, "a moving gap blocks no exit")
			else:
				assert_true(open >= 3, "%s: the exit still has room" % v)
