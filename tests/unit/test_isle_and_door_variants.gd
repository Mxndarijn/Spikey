extends TestCase
## Floating Isles (drifting, one big rock), Egg Hunt (drifting isles, golden
## egg), Shutter Gates (single small gate) and Ghost Doors (one row, flicker).

const Block := preload("res://sim/hazards/block.gd")
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")
const Gate := preload("res://sim/hazards/gate.gd")

const SUB := SimConfig.SUB


static func practice(id: String, seed_value: int, variant: String) -> GameSim:
	var index := RoomCatalog.index_of(id)
	var def: RoomDef = RoomCatalog.all()[index]
	return GameSim.new(seed_value, def.season, index, variant)


static func of_kind(sim: GameSim, kind: String) -> Array[Hazard]:
	var out: Array[Hazard] = []
	for h in sim.room.hazards:
		if h.kind == kind and h.alive:
			out.append(h)
	return out


# --- Floating Isles: drifting ----------------------------------------------------


## The islands sway sideways together: same offset for all, so the gaps
## between them never change; the whole sway stays Block.SIDE clear of the walls.
func test_drifting_isles_sway_together_and_stay_clear_of_the_walls() -> void:
	for s in 20:
		var sim := practice("isles", s, "drifting")
		var islands := of_kind(sim, "block")
		assert_true(islands.size() >= 2, "seed %d: islands" % s)
		var seen := {}
		for i in Block.DRIFT_PERIOD:
			sim.room.step(sim)
			var off: int = islands[0].x0 - islands[0].home_x
			seen[off] = true
			for b: Hazard in islands:
				assert_eq(b.x0 - b.home_x, off, "they sway together")
				assert_true(b.x0 >= Block.SIDE, "clear of the left wall")
				assert_true(b.x1 <= SimConfig.WORLD_W - Block.SIDE, "clear of the right wall")
		assert_true(seen.has(Block.DRIFT) and seen.has(-Block.DRIFT), "the full sway each way")


## A drifting island only kills where it is now.
func test_a_drifting_island_kills_where_it_is() -> void:
	var sim := practice("isles", 3, "drifting")
	var b: Hazard = of_kind(sim, "block")[0]
	for i in Block.DRIFT_PERIOD / 4:
		sim.room.step(sim)
	assert_eq(b.x0, b.home_x + Block.DRIFT, "a quarter loop in, it is furthest right")
	sim.state.y = (b.y0 + b.y1) / 2
	sim.state.x = b.home_x + 2 * SUB
	assert_false(b.kills(sim), "where it was is clear now")
	sim.state.x = b.x1 - 2 * SUB
	assert_true(b.kills(sim), "where it is kills")


# --- Floating Isles: one big rock -------------------------------------------------


func test_one_big_rock_sits_across_the_middle() -> void:
	var placed := 0
	for s in 40:
		var sim := practice("isles", s, "one-big")
		var rocks := of_kind(sim, "block")
		assert_true(rocks.size() <= 1, "one rock")
		if rocks.is_empty():
			continue
		placed += 1
		var b: Hazard = rocks[0]
		assert_true(b.x1 - b.x0 >= 150 * SUB, "wide")
		assert_eq(b.x0 + b.x1, SimConfig.WORLD_W, "centred")
		assert_true(b.x0 >= Block.SIDE, "clear of the walls")
		assert_true(b.y0 >= Block.BIG_TOP and b.y1 <= Block.BIG_BOTTOM, "in the middle")
		for side in 2:
			assert_true(b.blocks_exit(sim, side, (b.y0 + b.y1) / 2), "no exit level with it")
	assert_eq(placed, 40, "the rock fits off every practice start")


# --- Egg Hunt -------------------------------------------------------------------


## Drifting isles: each egg keeps its place beside its island as they sway.
func test_eggs_ride_along_with_drifting_isles() -> void:
	for s in 10:
		var sim := practice("eggs", s, "drifting")
		var pairs := []
		var islands := {}
		for h in sim.room.hazards:
			# A band with no island this time (alive false) keeps its egg still.
			if h.kind == "block" and h.alive:
				islands[h.band] = h
			elif h.kind == "coin" and islands.has(h.beside_band):
				pairs.append([islands[h.beside_band], h, h.x - islands[h.beside_band].x0])
		assert_eq(pairs.size(), islands.size(), "an egg per island")
		assert_true(pairs.size() >= 2, "seed %d: isles placed" % s)
		for i in Block.DRIFT_PERIOD:
			sim.room.step(sim)
			for p: Array in pairs:
				assert_eq(p[1].x - p[0].x0, p[2], "the egg rides along")
				assert_true(p[1].x <= CoinPickup.BESIDE_MAX_X, "stays in the room")


## Golden egg: the lowest isle's egg pays CoinPickup.GOLD_VALUE and sits on its
## wall side; the other three are plain.
func test_the_golden_egg_pays_more_and_hides_behind_its_isle() -> void:
	for s in 20:
		var sim := practice("eggs", s, "golden")
		var golden := 0
		for h in sim.room.hazards:
			if h.kind != "coin":
				continue
			if h.value == 1:
				continue
			golden += 1
			assert_eq(h.value, CoinPickup.GOLD_VALUE)
			assert_eq(h.beside_band, 3, "behind the lowest isle")
			var isle: Hazard = null
			for b in sim.room.hazards:
				if b.kind == "block" and b.band == 3:
					isle = b
			var left: bool = isle.x0 + isle.x1 < SimConfig.WORLD_W
			assert_eq(h.x < isle.x0, left, "on the wall side of its isle")
			var before := sim.state.coins
			sim.state.x = h.x
			sim.state.y = h.y
			h.touch(sim)
			assert_eq(sim.state.coins - before, CoinPickup.GOLD_VALUE, "worth five")
		assert_eq(golden, 1, "one golden egg")


# --- Shutter Gates: single gate ------------------------------------------------


func test_single_gate_is_one_wide_fast_gate_in_the_middle() -> void:
	var sim := practice("gates", 4, "single")
	var gates := of_kind(sim, "gate")
	assert_eq(gates.size(), 1, "one gate")
	var g: Hazard = gates[0]
	assert_eq(g.x, SimConfig.WORLD_W / 2, "in the middle")
	assert_eq(g.gap_bottom() - g.gap_top(), Gate.GEN_GAP, "the generated window")
	sim.state.x = g.x
	sim.state.y = g.gap_y
	assert_false(g.kills(sim), "the window's middle is safe")
	sim.state.y = g.gap_top() - 4 * SUB
	assert_true(g.kills(sim) or g.gap_top() - 4 * SUB < SimConfig.KILL_TOP, "above it kills")
	sim.state.y = g.gap_bottom() + 4 * SUB
	assert_true(g.kills(sim) or g.gap_bottom() + 4 * SUB > SimConfig.KILL_BOTTOM, "below it kills")


# --- Ghost Doors ----------------------------------------------------------------


## One row: three doors, and at every step exactly one is open, in turn from
## the left.
func test_row_doors_open_one_at_a_time_in_turn() -> void:
	var sim := practice("ghostdoors", 2, "row")
	var doors := of_kind(sim, "block")
	assert_eq(doors.size(), 3, "three doors")
	var order: Array[int] = []
	for i in 2 * CatalogRow.period():
		sim.room.step(sim)
		var open: Array[int] = []
		for d in doors.size():
			if not doors[d].solid():
				open.append(d)
		assert_eq(open.size(), 1, "one door open at step %d" % i)
		if order.is_empty() or order[-1] != open[0]:
			order.append(open[0])
	assert_eq(order.slice(0, 4), [0, 1, 2, 0] as Array[int], "left to right, then again")
	for d: Hazard in doors:
		assert_eq(d.y0, doors[0].y0, "one row")


## No exit opens level with the row on either wall (the doors at the ends sit
## near the walls), and a portal never drops the bird in at the row's height.
func test_row_keeps_exits_off_its_height() -> void:
	var sim := practice("ghostdoors", 2, "row")
	var doors := of_kind(sim, "block")
	var mid: int = (doors[0].y0 + doors[0].y1) / 2
	for side in 2:
		var any := false
		for d: Hazard in doors:
			any = any or d.blocks_exit(sim, side, mid)
		assert_true(any, "wall %d: no exit level with the row" % side)


## Flicker: the same grid as the classic doors, on a much shorter cycle, each
## door out of step with the others; a door still warns (fades in) before it
## is solid again.
func test_flicker_doors_are_the_grid_on_a_fast_cycle() -> void:
	var classic := of_kind(practice("ghostdoors", 2, "classic"), "block")
	var sim := practice("ghostdoors", 2, "flicker")
	var doors := of_kind(sim, "block")
	assert_eq(doors.size(), classic.size(), "same doors")
	var phases := {}
	for i in doors.size():
		var d: Hazard = doors[i]
		assert_eq(
			[d.x0, d.y0, d.x1, d.y1], [classic[i].x0, classic[i].y0, classic[i].x1, classic[i].y1]
		)
		assert_true(d.fade_period * 3 / 2 <= classic[i].fade_period, "fades fast")
		phases[d.phase] = true
	assert_eq(phases.size(), doors.size(), "out of step")
	var d0: Hazard = doors[0]
	for i in d0.fade_period:
		sim.room.step(sim)
		var next_solid: bool = posmod(i + 2 + d0.phase, d0.fade_period) < d0.solid_ticks
		if not d0.solid() and next_solid:
			assert_true(d0.opacity() > SimTrig.ONE / 2, "it shows before it is solid again")


## Lets the row test name the cycle without reaching into the catalog script.
class CatalogRow:
	static func period() -> int:
		return preload("res://sim/rooms/catalog_seasonal.gd").ROW_PERIOD
