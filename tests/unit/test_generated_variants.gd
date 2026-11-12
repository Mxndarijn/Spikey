extends TestCase
## GENERATED room variants (RoomVariant.recipe, VariantParams, VariantCheck):
## built round the planned entry height, they fit every arrival height.

const Gate := preload("res://sim/hazards/gate.gd")
const Echo := preload("res://sim/hazards/echo.gd")
const SUB := SimConfig.SUB
## Rooms whose variants are generated so that no height is skipped.
const ROOMS: Array[String] = [
	"isles", "gates", "crawl", "stalac", "bubbles", "echo", "gifts", "bees", "crabs"
]


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


## The columns open round the arrival and close again once the bird is past.
func test_columns_open_for_the_arrival_and_close_again() -> void:
	var index := RoomCatalog.index_of("stalac")
	var sim := _arrived(index, "classic", 140, 0, 1)
	var rocks: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.kind == "stalactite":
			rocks.append(h)
	assert_eq(rocks.size(), 2)
	assert_true(rocks[0].open_top > 0, "the first gap opens up for a high arrival")
	for i in 400:
		sim.room.step(sim)
	for st in rocks:
		assert_eq(st.open_top, 0, "closed again")
		assert_eq(st.open_bottom, 0)
	index = RoomCatalog.index_of("gates")
	sim = _arrived(index, "single-small", 320, 0, 0)
	var g: Hazard = sim.room.hazards[0]
	assert_true(g.gap_bottom() - g.gap_top() > Gate.SMALL_GAP, "the small window opens wide")
	for i in 400:
		sim.room.step(sim)
	assert_eq(g.gap_bottom() - g.gap_top(), Gate.SMALL_GAP, "and closes to its size")


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


## Static variants keep their hand-made factories.
func test_static_variants_stay_static() -> void:
	var v := RoomCatalog.find("swing").variants[0]
	assert_eq(v.id, "big")
	assert_eq(v.kind, RoomVariant.Kind.STATIC)
	assert_eq(v.hazards.size(), 1)
	assert_eq(RoomCatalog.find("crates").variants[0].kind, RoomVariant.Kind.STATIC)


## The hard rule: a generated layout uses only the room RNG (from the run seed
## and the room's place in the run) and seed-derived parameters (the planned
## anchor_y, the score, its level), never anything the player did. Each seed is
## played twice with different taps; every generated room both plays reach is
## built the same, every hazard's position and size included.
func test_generated_rooms_are_the_same_however_the_seed_is_played() -> void:
	var compared := 0
	for seed_value: int in [11, 2024, 31337, 4206176851]:
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
