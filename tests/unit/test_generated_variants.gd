extends TestCase
## GENERATED room variants (RoomVariant.recipe, VariantParams, VariantCheck):
## built round the planned entry height, they fit every arrival height.

const Gate := preload("res://sim/hazards/gate.gd")
const Stalactite := preload("res://sim/hazards/stalactite.gd")
const Echo := preload("res://sim/hazards/echo.gd")
const SUB := SimConfig.SUB
## Each test is its own piece of work (tests/run_tests.gd): they share no file.
const PARALLEL := true
## Rooms whose variants are generated so that no height is skipped.
const ROOMS: Array[String] = [
	"isles",
	"gates",
	"crawl",
	"stalac",
	"bubbles",
	"echo",
	"gifts",
	"bees",
	"crabs",
	"updraft",
	"pinwheel",
	"swing",
	"crates",
	"bramble",
	"rain",
	"cave",
	"pegs",
	"sawring",
	"bats",
	"ghostdoors",
	"pumpkin",
	"eggs",
]
## The hard rule: a generated layout is built once, at room start, and stays
## as it is while the bird is in the room. Per hazard kind, the fields that
## make its layout (its declared moving parts, like a swing's angle, a wheel's
## turn or a falling drop, are left out).
const LAYOUT_FIELDS := {
	"updraft": ["half_w", "lift", "y0", "y1", "drift_min", "drift_span"],
	"rotor":
	[
		"blades",
		"blade_max",
		"blade_min",
		"half_w",
		"hub_radius",
		"period",
		"spin",
		"hubs",
		"spread_x",
		"spread_y",
		"lean",
		"center_x",
		"center_y",
	],
	"pendulum":
	[
		"pivot_x",
		"pivot_y",
		"length",
		"radius",
		"amplitude",
		"period",
		"gust",
		"gust_period",
		"winch",
		"winch_period",
		"twin_x",
		"twin_length",
	],
	"crate_drop": ["cols", "col_w", "col_x0", "crate_w", "crate_h", "max_height", "pair", "gifts"],
	"bouncer": ["lane"],
	"drop": ["speed", "gap", "delay", "warn", "radius", "style"],
	"block": ["y0", "y1", "home_x", "band", "drift", "big"],
	"crawler": ["lane", "start", "segments", "seg_radius", "spacing", "speed"],
	"bubble": ["lane", "radius", "spiked", "coin_bubble"],
	"echo": ["mode", "pivot_y"],
	"mover": ["mode", "count", "loop_w", "loop_h", "loop_period", "center_y", "center_x", "phase"],
	"gate": ["x", "period", "phase", "gap_size", "lo_y", "hi_y", "lag"],
	"stalactite":
	[
		"x",
		"gap",
		"half_w",
		"top",
		"bottom",
		"fixed_lo",
		"fixed_hi",
		"scheduled",
		"schedule",
		"start_y"
	],
	"cave_rock":
	[
		"top_x",
		"top_y",
		"bot_x",
		"bot_y",
		"isle_x",
		"isle_top",
		"isle_bot",
		"reach_top",
		"reach_bottom"
	],
	"cave_drip": ["x", "tip_y", "floor_y", "first", "every"],
	"peg": ["x", "base_y", "bob", "phase"],
}
## Rooms built once when they start and never reshaped: only the declared
## moving parts (MOVING) of their hazards change after that.
const FIXED_ROOMS: Array[String] = ["gates", "stalac", "cave", "pegs"]
## Declared moving parts, per hazard kind: the fields a fixed room's hazard may
## change after the room starts (visible motion on a timetable fixed then).
const MOVING := {
	"gate": ["gap_y"],
	"stalactite": ["gap_y", "target_y", "slides"],
	"cave_rock": [],
	"cave_drip": ["falling", "y", "eta"],
	"mover": ["xs", "ys", "facing"],
	"peg": ["y"],
}


static func _arrived(index: int, variant: String, anchor_px: int, dy_px: int, side: int) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(4100 + anchor_px + side, def.season)
	sim.forced_variant = variant
	sim.step(true)
	sim.state.score = maxi(def.from_score, 20)
	sim.state.anchor_y = GameSim._arrival_y(anchor_px * SUB)
	sim.state.y = GameSim._arrival_y(sim.state.anchor_y + dy_px * SUB)
	sim._arrive_in(side, index)
	return sim


func test_generated_rooms_skip_no_arrival_height() -> void:
	for id in ROOMS:
		var def := RoomCatalog.find(id)
		assert_true(def.arrival_skip.is_empty(), "%s skips no height" % id)
		var generated := 0
		for v in def.variants:
			if v.kind == RoomVariant.Kind.GENERATED:
				generated += 1
				assert_true(v.arrival_skip.is_empty(), "%s/%s skips no height" % [id, v.id])
				assert_true(v.hazards.is_empty(), "%s/%s has no fixed factories" % [id, v.id])
		assert_true(generated > 0, "%s has a generated variant" % id)
		# A recipe builds hazards: the wall's free run stays within reach.
		assert_eq(RoomRules.gap_reach(def), RoomRules.GAP_REACH, "%s keeps the gap in reach" % id)
		for y_px in range(110, 531, 20):
			assert_true(def.fits_arrival(y_px * SUB), "%s fits %d px" % [id, y_px])


## The fairness contract: out of a portal at any height, a bird anywhere in
## the exit holding its height touches nothing deadly (VariantCheck), the
## fallback included.
func test_generated_variants_leave_a_safe_opening_at_every_height() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		var def: RoomDef = RoomCatalog.all()[index]
		for v in def.variants:
			if v.kind != RoomVariant.Kind.GENERATED:
				continue
			for y_px in range(120, 521, 50):
				for side in 2:
					var sim := _arrived(index, v.id, y_px, 0, side)
					assert_eq(sim.room.variant_id(), v.id)
					assert_true(
						VariantCheck.holds(sim, v.avoid_touch, v.hold_steps),
						"%s/%s at %d px, side %d" % [id, v.id, y_px, side]
					)


## Same seed, same map: the layout comes from the planned height (anchor_y),
## never from where in the exit the bird itself came through.
func test_generated_layouts_do_not_read_the_birds_height() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		for v in RoomCatalog.all()[index].variants:
			if v.kind != RoomVariant.Kind.GENERATED:
				continue
			for y_px: int in [140, 320, 500]:
				var a := _arrived(index, v.id, y_px, -40, 1)
				var b := _arrived(index, v.id, y_px, 40, 1)
				assert_eq(_layout(a), _layout(b), "%s/%s at %d px" % [id, v.id, y_px])
				assert_eq(a._rng.next_u32(), b._rng.next_u32(), "same draws")


static func _layout(sim: GameSim) -> int:
	var h := 0
	for hz in sim.room.hazards:
		if hz.kind == "echo":
			h = SimHash.mix(h, hz.pivot_y)
			continue
		h = hz.checksum(h)
	return h


## The generator contract: the layout at room start equals the layout at every
## later step, apart from each hazard's declared moving parts, however the
## room is flown (a surviving line, bounces included).
func test_fixed_rooms_never_change_shape_after_they_start() -> void:
	for id in FIXED_ROOMS:
		var index := RoomCatalog.index_of(id)
		for v in RoomCatalog.all()[index].variants:
			for y_px: int in [150, 450]:
				var sim := _arrived(index, v.id, y_px, 0, 1)
				var start := _shapes(sim)
				var search := SurvivalSearch.new()
				search.run(SimCopy.copy(sim), 700)
				var last := sim.room.t
				var steps := 0
				for tap in search.best_inputs:
					sim.step(tap == 1)
					if sim.is_over() or sim.room.t < last or sim.room.def.id != id:
						break
					last = sim.room.t
					steps += 1
					assert_eq(
						_shapes(sim), start, "%s/%s at %d px, step %d" % [id, v.id, y_px, steps]
					)
					if _shapes(sim) != start:
						break
				assert_true(steps > 200, "%s/%s at %d px: flew %d steps" % [id, v.id, y_px, steps])


## Every field of every hazard, but `t` and its kind's MOVING ones.
static func _shapes(sim: GameSim) -> String:
	var out := ""
	for h in sim.room.hazards:
		var skip: Array = MOVING.get(h.kind, [])
		out += h.kind
		for prop in h.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var field: String = prop.name
			if field == "t" or field in skip:
				continue
			var value: Variant = h.get(field)
			if value is Object:
				continue
			out += "|%s=%s" % [field, str(value)]
		out += ";"
	return out


## Fixed rooms fit every planned height out of a portal, 10 px apart, with no
## opening that closes later.
func test_fixed_rooms_fit_every_arrival_height() -> void:
	for id in FIXED_ROOMS:
		var index := RoomCatalog.index_of(id)
		for v in RoomCatalog.all()[index].variants:
			for y_px in range(110, 531, 10):
				var sim := _arrived(index, v.id, y_px, 0, 1)
				assert_true(VariantCheck.holds(sim), "%s/%s at %d px" % [id, v.id, y_px])


## A generated gate keeps its wide window all room, and out of a portal every
## window is round the hold band while the bird flies past it.
func test_gates_keep_one_window_size_timed_for_the_arrival() -> void:
	var index := RoomCatalog.index_of("gates")
	for y_px: int in [110, 300, 530]:
		var sim := _arrived(index, "classic", y_px, 0, 1)
		var gates: Array[Hazard] = []
		for h in sim.room.hazards:
			if h.kind == "gate":
				gates.append(h)
		assert_eq(gates.size(), 2)
		var p := VariantParams.make(sim, SimRng.new(1))
		assert_true(Gate._fits(sim, p, gates, gates[0].phase), "timed at %d px" % y_px)
		for i in 800:
			sim.room.step(sim)
			for g in gates:
				assert_eq(g.gap_bottom() - g.gap_top(), Gate.GEN_GAP, "one size")


## Stalactite classic: the entry column's gap never moves; the far column's
## slides only to its drawn heights, each within MAX_STEP of the last.
func test_stalactite_far_column_follows_its_schedule() -> void:
	var index := RoomCatalog.index_of("stalac")
	var sim := _arrived(index, "classic", 300, 0, 1)
	var cols: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.kind == "stalactite":
			cols.append(h)
	assert_eq(cols.size(), 2)
	assert_true(cols[0].fixed_lo >= 0 and not cols[0].scheduled, "entry column still")
	assert_true(cols[1].scheduled and cols[1].x > cols[0].x, "far column scheduled")
	var prev: int = cols[1].gap_y
	for y: int in cols[1].schedule:
		assert_true(absi(y - prev) <= Stalactite.MAX_STEP, "a step within reach")
		prev = y


## The mirror's turning height keeps off a bird holding its height.
func test_mirror_turns_round_a_height_away_from_the_arrival() -> void:
	var index := RoomCatalog.index_of("echo")
	for y_px in range(120, 521, 20):
		var sim := _arrived(index, "mirror", y_px, 0, 0)
		var e: Hazard = sim.room.hazards[0]
		assert_true(e.pivot_y >= Echo.PIVOT_LO and e.pivot_y <= Echo.PIVOT_HI, "in range")
		var anchor := sim.state.anchor_y
		var top := GameSim._arrival_y(anchor - SimConfig.EXIT_FIT) - FairLanes.FIRST_HOP
		var bottom := GameSim._arrival_y(anchor + SimConfig.EXIT_FIT)
		assert_true(
			e.pivot_y <= top - Echo.PIVOT_CLEAR or e.pivot_y >= bottom + Echo.PIVOT_CLEAR,
			"pivot clear of the hold band at %d px" % y_px
		)


## Static variants keep their hand-made factories (Piston Press and Beam Gates
## stay hand made).
func test_static_variants_stay_static() -> void:
	for id: String in ["piston"]:
		for v in RoomCatalog.find(id).variants:
			assert_eq(v.kind, RoomVariant.Kind.STATIC, "%s/%s" % [id, v.id])
			assert_false(v.hazards.is_empty(), "%s/%s has its factories" % [id, v.id])
	assert_true(RoomCatalog.find("beams").variants.is_empty(), "beams has no variants")


## The hard rule: a generated layout uses only the room RNG (from the run seed
## and the room's place in the run) and seed-derived parameters (the planned
## anchor_y, the score, its level), never anything the player did. Each seed is
## played twice with different taps; every generated room both plays reach is
## built the same, every hazard's position and size included.
func test_generated_rooms_are_the_same_however_the_seed_is_played() -> void:
	var compared := 0
	for seed_value: int in [
		11, 7, 99, 1, 2, 3, 123, 777, 8, 13, 55, 2024, 31337, 5150, 65536, 42, 9001
	]:
		var a := _played_layouts(seed_value, 3)
		var b := _played_layouts(seed_value, 8)
		for room: int in a:
			if not b.has(room):
				continue
			compared += 1
			assert_eq(a[room], b[room], "seed %d, room %d" % [seed_value, room])
	assert_true(compared >= 4, "generated rooms met by both plays: %d" % compared)


## Out of the same exit, a bird anywhere in it, and out of a fork's Calm or
## Wild exit (both lead to one door), the generated room is built the same.
func test_generated_layouts_ignore_the_birds_place_and_the_fork_taken() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		var def: RoomDef = RoomCatalog.all()[index]
		for v in def.variants:
			if v.kind != RoomVariant.Kind.GENERATED:
				continue
			for exit_px: int in [140, 400]:
				var high := _through(index, v.id, SimState.ExitKind.NORMAL, exit_px, -40)
				var low := _through(index, v.id, SimState.ExitKind.NORMAL, exit_px, 40)
				assert_eq(high, low, "%s/%s at %d px" % [id, v.id, exit_px])
				var calm := _through(index, v.id, SimState.ExitKind.CALM, exit_px, 20)
				var wild := _through(index, v.id, SimState.ExitKind.WILD, exit_px + 80, -30)
				assert_eq(calm, wild, "%s/%s, Calm or Wild" % [id, v.id])


## Every generated room a play enters (by its place in the run), with its
## layout as built out of the portal.
static func _played_layouts(seed_value: int, bot_seed: int) -> Dictionary:
	var out := {}
	var sim := GameSim.new(seed_value)
	var bot := SimRng.new(bot_seed)
	for i in 12000:
		if sim.is_over():
			break
		sim.step(SimBots.gap_seeker(sim, bot))
		if GameSim.Event.ROOM_CHANGE in sim.events and not sim.room.def.variants.is_empty():
			if sim.room.def.variants[sim.room.variant].kind == RoomVariant.Kind.GENERATED:
				out[sim.state.room_index] = _named_layout(sim)
	return out


## Practice in a variant, then through an exit of `kind` at `exit_px`, the bird
## `dy_px` from its middle.
static func _through(index: int, variant: String, kind: int, exit_px: int, dy_px: int) -> String:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(5150, def.season, index, variant)
	sim.step(true)
	sim.state.score = maxi(def.from_score, 20)
	sim.state.y = (exit_px + dy_px) * SUB
	sim._go_through(1, kind, exit_px * SUB)
	return _named_layout(sim)


static func _named_layout(sim: GameSim) -> String:
	return "%s/%s %d" % [sim.room.def.id, sim.room.variant_id(), _layout(sim)]


func test_generated_layouts_stay_fixed_while_the_bird_is_in_the_room() -> void:
	for id in ROOMS:
		var index := RoomCatalog.index_of(id)
		for v in RoomCatalog.all()[index].variants:
			if v.kind != RoomVariant.Kind.GENERATED:
				continue
			for y_px: int in [140, 320, 500]:
				for side in 2:
					var sim := _arrived(index, v.id, y_px, 0, side)
					var start := _snapshot(sim)
					var room := sim.state.room_index
					var bot := SimRng.new(y_px + side)
					for i in 900:
						if sim.is_over() or sim.state.room_index != room:
							break
						sim.step(SimBots.random_tapper(sim, bot, 14))
						if i % 30 == 29 and not sim.is_over() and sim.state.room_index == room:
							assert_eq(
								_snapshot(sim, start.size()),
								start,
								"%s/%s at %d px, side %d, tick %d" % [id, v.id, y_px, side, i]
							)


## Every hazard's layout fields (LAYOUT_FIELDS), the first `count` hazards
## (a hazard may add pieces later, a split ball's half).
static func _snapshot(sim: GameSim, count: int = -1) -> Array:
	var out := []
	var n := sim.room.hazards.size() if count < 0 else mini(count, sim.room.hazards.size())
	for i in n:
		var h: Hazard = sim.room.hazards[i]
		var row := [h.kind]
		for f: String in LAYOUT_FIELDS.get(h.kind, []):
			row.append(h.get(f))
		out.append(row)
	return out


## Cave Tunnel: every exit the room plans, at every planned height and both
## ways in, sits where a mouth of its wall holds its box and a bird flying the
## gallery reaches it (a fork's far branch once lay out of reach: v22 seed 139).
func test_cave_exits_are_planned_within_reach_of_the_gallery() -> void:
	var index := RoomCatalog.index_of("cave")
	for v in RoomCatalog.all()[index].variants:
		for y_px in range(110, 531, 20):
			for side in 2:
				var sim := _arrived(index, v.id, y_px, 0, side)
				var st := sim.state
				for h in sim.room.hazards:
					if h.kind != "cave_rock":
						continue
					var plans := [[0, st.plan_a_y_left], [1, st.plan_a_y_right]]
					for q: Array in plans:
						assert_false(
							h.blocks_exit(sim, q[0], q[1]),
							(
								"cave/%s at %d px, side %d: exit at %d px"
								% [v.id, y_px, side, q[1] / SUB]
							)
						)
