extends TestCase
## Out of a portal the room is laid out for a player who is slow to react
## (GameSim._arrival_retries, ArrivalCheck).


static func _sim_at(score: int, seed_value: int) -> GameSim:
	var sim := GameSim.new(seed_value)
	sim.step(true)
	sim.state.score = score
	return sim


## Out of a portal the room is laid out so a bird that only holds its height
## for ARRIVAL_BLIND ticks (a player still reading the room) can live on.
func test_a_slow_reaction_out_of_a_portal_is_fair() -> void:
	var fair := SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW
	var ok := 0
	var count := 0
	for id: String in ["isles", "pinwheel", "swing", "stalac", "gates"]:
		var index := RoomCatalog.index_of(id)
		for i in 8:
			var sim := _sim_at(maxi(RoomCatalog.all()[index].from_score, 20), 300 + i)
			var y := 160 + (i * 53) % 320
			while not RoomCatalog.all()[index].fits_arrival(y * SimConfig.SUB):
				y = 160 + (y - 160 + 53) % 320
			sim.state.y = y * SimConfig.SUB
			sim.state.anchor_y = sim.state.y
			var side := i % 2
			for k in sim._arrival_retries(side, index):
				sim._rng.next_u32()
			sim._arrive_in(side, index)
			count += 1
			if ArrivalCheck.score(SimClone.copy(sim)) >= fair:
				ok += 1
	assert_true(ok * 10 >= count * 9, "fair arrivals: %d/%d" % [ok, count])


func test_arrival_checks_leave_the_run_untouched_and_never_nest() -> void:
	var sim := _sim_at(20, 7)
	var before := sim.checksum()
	sim._arrival_retries(0, RoomCatalog.index_of("isles"))
	assert_eq(sim.checksum(), before, "the check plays on copies only")
	var c := SimClone.copy(sim)
	c._checking = true
	assert_eq(c._arrival_retries(0, RoomCatalog.index_of("isles")), 0, "no check in a check")


## Out of a portal the picker never sends the bird into a room at a height it
## skips (RoomDef.arrival_skip).
func test_rooms_are_not_picked_at_heights_they_skip() -> void:
	for y_px in range(110, 531, 20):
		var y := y_px * SimConfig.SUB
		var rng := SimRng.new(y_px)
		var state := SimState.new()
		state.score = 200
		state.anchor_y = y
		for i in 300:
			var next := RoomCatalog.pick_next(rng, state, 0, Seasons.SPRING)
			var def: RoomDef = RoomCatalog.all()[next]
			assert_true(def.fits_arrival(y), "%s picked at %d px" % [def.id, y_px])


## Bee Line and Bat Loop time themselves out of a portal: at every height
## they can be picked at, a bird holding height stays clear of them for the
## reading time and a bit (FairLanes.ARRIVAL_PATH_MIN).
func test_moving_hazards_keep_off_a_bird_holding_height() -> void:
	for id: String in ["bees", "bats"]:
		var index := RoomCatalog.index_of(id)
		var def: RoomDef = RoomCatalog.all()[index]
		for y_px in range(120, 521, 10):
			if not def.fits_arrival(y_px * SimConfig.SUB):
				continue
			for side in 2:
				var sim := _sim_at(40, 900 + y_px + side)
				sim.state.y = y_px * SimConfig.SUB
				sim.state.anchor_y = sim.state.y
				sim._arrive_in(side, index)
				var h: Hazard = sim.room.hazards[0]
				var clear: int = h._arrival_clear(FairLanes.arrival_path(sim))
				assert_true(
					clear >= FairLanes.ARRIVAL_PATH_MIN,
					"%s at %d px, side %d: clear %d steps" % [id, y_px, side, clear]
				)


## Lantern Swing is generated round the arrival: in every variant, at every
## height, a bird holding its height anywhere in the exit stays clear of every
## lantern for the reading time (VariantCheck).
func test_swing_lanterns_keep_off_a_bird_holding_height() -> void:
	var index := RoomCatalog.index_of("swing")
	var def: RoomDef = RoomCatalog.all()[index]
	for variant: RoomVariant in def.variants:
		for y_px in range(120, 521, 40):
			for side in 2:
				var sim := _sim_at(40, 900 + y_px + side)
				sim.forced_variant = variant.id
				sim.state.y = y_px * SimConfig.SUB
				sim.state.anchor_y = sim.state.y
				sim._arrive_in(side, index)
				assert_true(
					VariantCheck.holds(sim), "%s at %d px, side %d" % [variant.id, y_px, side]
				)


## Out of a portal a room only draws variants that fit the bird's height, and
## some Lantern Swing variant fits every height.
func test_portal_draws_only_variants_that_fit() -> void:
	var index := RoomCatalog.index_of("swing")
	var def: RoomDef = RoomCatalog.all()[index]
	var seen := {}
	for y_px in range(110, 531, 10):
		var y := y_px * SimConfig.SUB
		assert_true(def.fits_arrival(y), "some variant fits %d px" % y_px)
		for i in 6:
			var sim := _sim_at(40, 3000 + y_px * 7 + i)
			sim.state.y = y
			sim.state.anchor_y = sim.state.y
			sim._arrive_in(i % 2, index)
			var v: RoomVariant = def.variants[sim.room.variant]
			assert_true(v.fits_arrival(y), "%s drawn at %d px" % [v.id, y_px])
			seen[v.id] = true
	assert_eq(seen.size(), def.variants.size(), "every variant still drawn somewhere")


## A bird that flies through the very top (or bottom) of an exit comes out of
## the portal far enough from the ceiling and floor to hop while it reads the
## room.
func test_the_portal_keeps_the_bird_off_the_ceiling_and_floor() -> void:
	var top := SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE
	var bottom := SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE
	for y_px: int in [56, 100, 300, 590]:
		var sim := _sim_at(20, 40 + y_px)
		sim.state.y = y_px * SimConfig.SUB
		sim.state.anchor_y = sim.state.y
		sim._go_through(1, SimState.ExitKind.NORMAL, sim.state.y)
		assert_between(sim.state.anchor_y, top, bottom, "the anchor too")
		assert_between(sim.state.y, top, bottom)
		if y_px == 300:
			assert_eq(sim.state.y, 300 * SimConfig.SUB, "a height in between is kept")


## Out of a portal the wall ahead keeps its spikes: the hold band is cleared
## only when no layout is fair without it (GameSim._arrival_band). It used to
## be cleared in almost every room, leaving a low-score wall bare.
func test_the_wall_ahead_keeps_its_spikes_out_of_a_portal() -> void:
	for id: String in ["tide", "crowded"]:
		var index := RoomCatalog.index_of(id)
		var bare := 0
		var banded := 0
		for i in 12:
			var sim := _sim_at(RoomCatalog.all()[index].from_score + 10 * (i % 3), 500 + i)
			var y := 160 + (i * 53) % 320
			while not RoomCatalog.all()[index].fits_arrival(y * SimConfig.SUB):
				y = 160 + (y - 160 + 53) % 320
			sim.state.y = y * SimConfig.SUB
			sim.state.anchor_y = sim.state.y
			var side := i % 2
			for k in sim._arrival_retries(side, index):
				sim._rng.next_u32()
			if sim._arrival_band:
				banded += 1
			sim._arrive_in(side, index)
			if sim.wall_mask(side) == 0:
				bare += 1
		assert_true(banded <= 1, "%s: band in %d of 12 arrivals" % [id, banded])
		assert_eq(bare, 0, "%s: a bare wall ahead" % id)
