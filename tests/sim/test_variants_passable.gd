extends TestCase
## Narrow, Tide Spikes (every variant) and Bumper Cloud (one and two clouds)
## can be played: SurvivalSearch finds a way through each practice seed, long
## enough to take the first portal.

## Practice seeds per room variant.
const SEEDS_EACH := 2
## [room id, ticks]: ten points and a portal (a Narrow crossing is shorter).
const CASES := [["narrow", 900], ["tide", 1150], ["cloud", 1150]]


func test_rooms_are_passable_in_every_variant() -> void:
	for c: Array in CASES:
		var index := RoomCatalog.index_of(c[0])
		var def: RoomDef = RoomCatalog.all()[index]
		# How many seeds each variant still needs.
		var wanted := {}
		for v in maxi(def.variants.size(), 1):
			wanted[v] = SEEDS_EACH
		var seed_value := 500
		while not wanted.is_empty() and seed_value < 2000:
			seed_value += 37
			var sim := GameSim.new(seed_value, def.season, index)
			var v := sim.room.variant
			if not wanted.has(v):
				continue
			wanted[v] -= 1
			if wanted[v] == 0:
				wanted.erase(v)
			var what := "%s seed %d (%s)" % [c[0], seed_value, sim.room.variant_id()]
			var search := SurvivalSearch.new()
			var ok := search.run(sim, c[1])
			assert_true(ok, "%s: all died at tick %d" % [what, search.ticks_survived])
			if ok:
				assert_true(search.best.state.room_index >= 1, "%s: took a portal" % what)
		assert_true(wanted.is_empty(), "%s: every variant tried" % c[0])
