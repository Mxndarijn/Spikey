extends TestCase
## Updraft and its six variants: chimney, twin, drift, gust, updown, coins.

const Rooms := preload("res://tests/unit/test_rooms.gd")
const SkyTests := preload("res://tests/unit/test_rooms_sky.gd")
const Updraft := preload("res://sim/hazards/updraft.gd")
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")

const SUB := SimConfig.SUB
const IDS := ["chimney", "twin", "drift", "gust", "updown", "coins"]


## A started Updraft room playing variant `id` (the first seed from `from` that draws it).
static func in_variant(id: String, from: int = 1) -> GameSim:
	for s in range(from, from + 500):
		var sim := Rooms.sim_in_room("updraft", s)
		if sim.room.variant_id() == id:
			sim.state.started = true
			return sim
	return null


## The bird hangs at `x_px` (no sideways speed) from `vy0`; its vy after `steps`.
static func vy_after(sim: GameSim, x_px: int, vy0: int, steps: int) -> int:
	sim.state.x = x_px * SUB
	sim.state.y = 450 * SUB
	sim.state.vx = 0
	sim.state.vy = vy0
	for i in steps:
		sim.step(false)
	return sim.state.vy


func test_the_room_has_six_variants() -> void:
	var ids := []
	for v in RoomCatalog.find("updraft").variants:
		ids.append(v.id)
	assert_eq(ids, IDS)
	assert_true(RoomCatalog.find("updraft").hazards.is_empty(), "the air comes from the variant")


func test_every_variant_shows_up_and_builds_its_air() -> void:
	var want := {
		"chimney": ["updraft"],
		"twin": ["updraft", "updraft"],
		"drift": ["updraft"],
		"gust": ["updraft"],
		"updown": ["updraft", "updraft"],
		"coins": ["updraft", "coin", "coin", "coin"],
	}
	for id: String in IDS:
		var sim := in_variant(id)
		assert_true(sim != null, "%s is drawn" % id)
		if sim == null:
			continue
		var kinds: Array = []
		for h in sim.room.hazards:
			kinds.append(h.kind)
		assert_eq(kinds, want[id], "%s builds its air" % id)


## Coins: today's soft column. Inside, the bird floats (falls far slower);
## outside it falls normally. It never rises on its own.
func test_soft_column_only_slows_the_fall() -> void:
	var inside := vy_after(in_variant("coins"), 180, 0, 30)
	var outside := vy_after(in_variant("coins"), 40, 0, 30)
	assert_true(inside >= 0, "it never rises on its own")
	assert_true(inside * 2 < outside, "it falls far slower inside")


func test_chimney_carries_the_bird_up() -> void:
	var sim := in_variant("chimney")
	var y0 := 450 * SUB
	var vy := vy_after(sim, 180, 0, 30)
	assert_eq(vy, 30 * (SimConfig.GRAVITY - Updraft.CHIMNEY), "net half a gravity upward")
	assert_true(sim.state.y < y0, "rises from rest")
	assert_eq(vy_after(in_variant("chimney"), 40, 0, 30), 30 * SimConfig.GRAVITY, "normal outside")


## Out of a portal high up, the hover-lane variants aren't drawn: a tap to hold
## height in a hover lane keeps rising into the ceiling.
func test_hover_lanes_skip_high_portal_arrivals() -> void:
	for v in RoomCatalog.find("updraft").variants:
		var hover: bool = v.id == "twin" or v.id == "updown"
		assert_eq(v.fits_arrival(130 * SUB), not hover, "%s at 130 px" % v.id)
		assert_true(v.fits_arrival(180 * SUB), "%s at 180 px" % v.id)


func test_twin_lanes_hover_and_the_middle_is_still_air() -> void:
	for x_px in [100, 260]:
		assert_eq(vy_after(in_variant("twin"), x_px, 3 * SUB, 30), 3 * SUB, "hover at %d" % x_px)
	assert_eq(vy_after(in_variant("twin"), 180, 0, 20), 20 * SimConfig.GRAVITY, "middle is still")


func test_updown_floats_then_sinks() -> void:
	assert_eq(vy_after(in_variant("updown"), 120, 2 * SUB, 20), 2 * SUB, "the updraft hovers")
	var g := SimConfig.GRAVITY
	assert_eq(
		vy_after(in_variant("updown"), 240, 0, 20), 20 * 2 * g, "the downdraft doubles gravity"
	)
	assert_eq(vy_after(in_variant("updown"), 180, 0, 20), 20 * g, "still air between")


## The drifting lane moves 1 px per step between centers 70 and 290 px and
## back, from a start drawn per seed.
func test_drift_slides_wall_to_wall_at_one_px_per_step() -> void:
	var phases := {}
	for s in 8:
		var sim := in_variant("drift", 1 + s * 50)
		var h: Updraft = sim.room.hazards[0]
		phases[h.phase] = true
		var lo := SimConfig.WORLD_W
		var hi := 0
		var last := h.x0
		for i in 460:
			sim.room.step(sim)
			assert_true(absi(h.x0 - last) <= SUB, "at most 1 px a step")
			assert_eq(h.x1 - h.x0, 100 * SUB, "100 px wide")
			last = h.x0
			var c := (h.x0 + h.x1) / 2
			lo = mini(lo, c)
			hi = maxi(hi, c)
		assert_eq(lo, 70 * SUB, "reaches the left end")
		assert_eq(hi, 290 * SUB, "reaches the right end")
	assert_true(phases.size() > 1, "the start comes from the RNG")


## A gust room starts off, warns for a full ARRIVAL_BLIND, then blows; no lift
## until it blows.
func test_gust_always_warns_for_a_second_first() -> void:
	for s in 12:
		var sim := in_variant("gust", 1 + s * 40)
		var h: Updraft = sim.room.hazards[0]
		assert_eq(h.gust, Updraft.Gust.OFF, "starts off")
		var warn := 0
		var steps := 0
		while h.gust != Updraft.Gust.ON:
			sim.room.step(sim)
			steps += 1
			if h.gust == Updraft.Gust.WARN:
				warn += 1
		assert_eq(warn, SimConfig.ARRIVAL_BLIND, "a full warning before the gust")
		assert_true(steps > SimConfig.ARRIVAL_BLIND, "never blows in the first second")
		var on := 0
		while h.gust == Updraft.Gust.ON:
			sim.room.step(sim)
			on += 1
		assert_eq(on, Updraft.GUST_ON, "blows for 1.5 s")
		assert_eq(h.gust, Updraft.Gust.OFF, "then rests")


func test_gust_lifts_only_while_it_blows() -> void:
	var sim := in_variant("gust")
	var h: Updraft = sim.room.hazards[0]
	assert_eq(vy_after(sim, 180, 0, 1), SimConfig.GRAVITY, "off: no lift")
	while h.gust != Updraft.Gust.WARN:
		sim.room.step(sim)
	assert_eq(vy_after(sim, 180, 0, 1), SimConfig.GRAVITY, "warning: no lift yet")
	while h.gust != Updraft.Gust.ON:
		sim.room.step(sim)
	assert_eq(vy_after(sim, 180, 0, 1), SimConfig.GRAVITY - Updraft.STRONG, "on: twice gravity")


func test_thermal_coins_are_collected_in_the_column() -> void:
	var sim := in_variant("coins")
	var before := sim.state.coins
	for h in sim.room.hazards:
		var coin := h as CoinPickup
		if coin == null:
			continue
		sim.state.x = coin.x
		sim.state.y = coin.y
		sim.state.vx = 0
		sim.state.vy = 0
		sim.step(false)
		assert_false(coin.alive, "taken")
	assert_eq(sim.state.coins - before, 3, "three coins")


func test_moving_air_is_deterministic() -> void:
	for id: String in ["drift", "gust"]:
		var a := in_variant(id, 7)
		var b := in_variant(id, 7)
		for i in 300:
			a.room.step(a)
			b.room.step(b)
		assert_eq(a.room.hazards[0].checksum(1), b.room.hazards[0].checksum(1), id)


## Every variant's air draws through a whole gust cycle and a drift.
func test_every_variant_draws() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var sim := GameSim.new(3)
	var canvas := SkyTests.SkinCanvas.new()
	tree.root.add_child(canvas)
	var list: Array[Hazard] = []
	for v in RoomCatalog.find("updraft").variants:
		for f: Callable in v.hazards:
			var h: Hazard = f.call()
			canvas.add(h, "")
			list.append(h)
	sim.room.hazards = list
	for h in list:
		h.setup(sim, SimRng.new(4))
	for i in Updraft.GUST_PERIOD + 20:
		sim.room.step(sim)
		if i % 15 == 0:
			canvas.queue_redraw()
			await tree.process_frame
	canvas.free()
