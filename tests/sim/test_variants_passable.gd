extends TestCase
## Narrow, Tide Spikes, Bumper Cloud, Bramble Ball, Spike Rain, Lantern Swing
## and Updraft (every variant of each) can be played: SurvivalSearch finds a way
## through each practice seed, long enough to take the first portal.

## Practice seeds per room variant.
const SEEDS_EACH := 2
## [room id, ticks]: ten points and a portal (a Narrow crossing is shorter).
const CASES := [
	["narrow", 900],
	["tide", 1150],
	["cloud", 1150],
	["bramble", 1150],
	["rain", 1150],
	["swing", 1150],
	["updraft", 1150],
]

const PARALLEL := true
## The searches are shared out over this many parts, which can run side by side.
const PARTS := 8


func test_rooms_are_passable_in_every_variant(part: int, parts: int) -> void:
	var cases := _cases()
	for i in range(part, cases.size(), parts):
		var c: Array = cases[i]
		var index := RoomCatalog.index_of(c[0])
		var def: RoomDef = RoomCatalog.all()[index]
		var sim := GameSim.new(c[1], def.season, index)
		var what := "%s seed %d (%s)" % [c[0], c[1], sim.room.variant_id()]
		var search := SurvivalSearch.new()
		var ok := search.run(sim, c[2])
		assert_true(ok, "%s: all died at tick %d" % [what, search.ticks_survived])
		if ok:
			assert_true(search.best.state.room_index >= 1, "%s: took a portal" % what)


## Every room has a practice seed for each variant, SEEDS_EACH of them.
func test_every_variant_has_seeds() -> void:
	var found := {}
	for c: Array in _cases():
		found[c[0]] = int(found.get(c[0], 0)) + 1
	for c: Array in CASES:
		var def: RoomDef = RoomCatalog.all()[RoomCatalog.index_of(c[0])]
		var want := maxi(def.variants.size(), 1) * SEEDS_EACH
		assert_eq(found.get(c[0], 0), want, "%s: every variant tried" % c[0])


## The searches: [room id, practice seed, ticks], SEEDS_EACH seeds per variant.
static func _cases() -> Array:
	var out := []
	for c: Array in CASES:
		var index := RoomCatalog.index_of(c[0])
		var def: RoomDef = RoomCatalog.all()[index]
		# How many seeds each variant still needs.
		var wanted := {}
		for v in maxi(def.variants.size(), 1):
			wanted[v] = SEEDS_EACH
		var seed_value := 500
		while not wanted.is_empty() and seed_value < 6000:
			seed_value += 37
			var v := GameSim.new(seed_value, def.season, index).room.variant
			if not wanted.has(v):
				continue
			wanted[v] -= 1
			if wanted[v] == 0:
				wanted.erase(v)
			out.append([c[0], seed_value, c[1]])
	return out
