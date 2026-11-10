extends TestCase
## Narrow, Tide Spikes, Bumper Cloud, Bramble Ball, Spike Rain, Lantern Swing,
## Updraft, the twist rooms (Crosswind, Spike Belt, Locked Exit, Lava Rise,
## Echo), Bubble Lift, Coin Garden, Slow-Mo Breather, Bumper Court, Crowded,
## Squeeze Box, Blink Walls, Hunter Spike, Gravity Flip, Midnight Cage, Saw Ring,
## Bat Loop, Cupid Lanes, Firework Burst, Caterpillar Crawl, Crab Walk, Pumpkin
## Bounce, Keepy-Uppy, Beach Ball, Heart Bumpers, Floating Isles, Egg Hunt,
## Shutter Gates, Ghost Doors and the machine rooms (Piston Press, Stalactite
## Run, Crate Drop, Gift Stack), every variant of each, can be played:
## SurvivalSearch finds a way through each practice seed, long enough to take
## the first portal.
##
## The full check runs on FastSim (`tools/fastsim.ps1 -Mode check -Check
## passable`, part of tools/check.ps1): every case below and more seeds per
## variant. Here the real sim plays every SAMPLE_EVERY-th case of it.

## Practice seeds per room variant (FastSim plays more: Checks.cs SEEDS_EACH).
const SEEDS_EACH := 2
## The GDScript sample: one search in this many.
const SAMPLE_EVERY := 10
## [room id, ticks]: ten points and a portal (a Narrow crossing is shorter).
## Locked Exit: a bot that skips the key waits for the exit to open by itself.
## Slow-Mo Breather runs at half speed, so it needs twice the ticks.
const CASES := [
	["narrow", 900],
	["tide", 1150],
	["cloud", 1150],
	["bramble", 1150],
	["rain", 1150],
	["swing", 1150],
	["updraft", 1150],
	["crosswind", 1150],
	["belt", 1150],
	["lockexit", 1700],
	["lava", 1150],
	["echo", 1150],
	["bubbles", 1150],
	["garden", 1150],
	["slowmo", 2300],
	["court", 1150],
	["crowded", 1150],
	["squeeze", 1150],
	["blink", 1150],
	["hunter", 1150],
	["flip", 1150],
	["midnight", 1150],
	["sawring", 1150],
	["bats", 1150],
	["cupid", 1150],
	["fireworks", 1150],
	["crawl", 1150],
	["crabs", 1150],
	["pumpkin", 1150],
	["keepy", 1150],
	["beachball", 1150],
	["hearts", 1150],
	["isles", 1150],
	["eggs", 1150],
	["gates", 1150],
	["ghostdoors", 1150],
	["piston", 1150],
	["stalac", 1150],
	["crates", 1150],
	["gifts", 1150],
]

const PARALLEL := true
## The searches are shared out over this many parts, which can run side by side.
const PARTS := 4


func test_rooms_are_passable_in_every_variant(part: int, parts: int) -> void:
	var cases := _cases()
	for i in range(part * SAMPLE_EVERY, cases.size(), parts * SAMPLE_EVERY):
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
