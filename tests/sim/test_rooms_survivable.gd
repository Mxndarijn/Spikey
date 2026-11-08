extends TestCase
## Rooms that SurvivalSearch once proved impossible (every possible way of
## tapping died). Each case replays that practice seed past the tick where the
## search used to die out, so the fix stays fixed.

## [room id, seed, ticks it must survive]
const CASES := [
	# Gravity Flip (the search itself used to mix up flipped speeds).
	["flip", 1000, 300],
	# Saw Ring: wide rings left no way to the wall gap.
	["sawring", 1000, 600],
	["sawring", 1154, 900],
	# Double Trouble: four full-width beams plus the bouncing ball.
	["double", 1077, 520],
]


func test_once_impossible_rooms_are_survivable() -> void:
	for c: Array in CASES:
		var index := RoomCatalog.index_of(c[0])
		var def: RoomDef = RoomCatalog.all()[index]
		var sim := GameSim.new(c[1], def.season, index)
		var search := SurvivalSearch.new()
		var ok := search.run(sim, c[2])
		assert_true(ok, "%s seed %d: all died at tick %d" % [c[0], c[1], search.ticks_survived])


func test_search_finds_no_way_when_there_is_none() -> void:
	# A sim that is already over has no way to survive.
	var sim := GameSim.new(1)
	sim.step(true)
	sim.kill(SimState.DeathCause.CEILING)
	var search := SurvivalSearch.new()
	assert_false(search.run(sim, 10), "a dead bird cannot survive")
