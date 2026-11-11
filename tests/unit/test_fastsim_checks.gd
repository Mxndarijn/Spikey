extends TestCase
## The FastSim bot checks (tools/fastsim/Checks.cs, run by tools/check.ps1)
## are ports of GDScript tests that now keep only a sample. This pins the C#
## copies of their rules to the GDScript ones: same cases, same thresholds,
## and at least as many seeds or arrivals as the GD sample plays.

const Passable := preload("res://tests/sim/test_variants_passable.gd")
const Reaction := preload("res://tests/sim/test_arrival_reaction.gd")
const Points := preload("res://tests/sim/test_room_points_cap.gd")
const ReviveTest := preload("res://tests/sim/test_revive_survivable.gd")
const Pairs := preload("res://tests/sim/test_double_trouble.gd")

const CHECKS := "res://tools/fastsim/Checks.cs"
const REACTION := "res://tools/fastsim/Reaction.cs"


func test_passable_plays_the_same_rooms_for_as_long() -> void:
	var cs := _class("Passable")
	var listed: Array = []
	var re := RegEx.create_from_string('\\("(\\w+)", (\\d+)\\)')
	for m in re.search_all(cs):
		listed.append([m.get_string(1), int(m.get_string(2))])
	assert_eq(listed, Passable.CASES, "Checks.cs Passable.CASES = test_variants_passable CASES")
	assert_true(_const(cs, "SEEDS_EACH") >= Passable.SEEDS_EACH, "passable: as many seeds")


func test_arrival_uses_the_same_benchmark() -> void:
	var cs := _class("Arrival")
	assert_eq(_const(cs, "AFTER"), Reaction.AFTER, "arrival AFTER")
	assert_eq(_const(cs, "HORIZON"), Reaction.HORIZON, "arrival HORIZON")
	assert_eq(_const(cs, "ROLLOUTS"), Reaction.ROLLOUTS, "arrival ROLLOUTS")
	assert_true(_const(cs, "COUNT") >= Reaction.COUNT, "arrival: as many arrivals")
	var rc := _source(REACTION)
	assert_eq(_const(rc, "EARLY_DELAY"), ArrivalBench.EARLY_DELAY, "Reaction.EARLY_DELAY")
	assert_eq(_const(rc, "MAX_EXTRA_PCT"), ArrivalBench.MAX_EXTRA_PCT, "Reaction.MAX_EXTRA_PCT")


func test_points_plays_as_long() -> void:
	var cs := _class("Points")
	assert_eq(_const(cs, "MAX_TICKS"), Points.MAX_TICKS, "points MAX_TICKS")
	assert_true(_const(cs, "SEEDS_PER_VARIANT") >= Points.SEEDS_PER_VARIANT, "points: seeds")
	assert_true(_const(cs, "REVIVE_RUNS") >= Points.REVIVE_RUNS, "points: revive runs")


func test_revive_searches_as_long_in_every_case() -> void:
	var cs := _class("Revive")
	var hold := "SimConfig.ARRIVAL_HOLD + %d" % (ReviveTest.TICKS - SimConfig.ARRIVAL_HOLD)
	assert_true(cs.contains("TICKS = %s;" % hold), "revive TICKS = %s" % hold)
	var cases := ", ".join(ReviveTest.CASES.map(func(c: String) -> String: return '"%s"' % c))
	assert_true(cs.contains("CASES = { %s };" % cases), "revive CASES = %s" % cases)


func test_pairs_search_as_long() -> void:
	var cs := _class("Pairs")
	assert_eq(_const(cs, "SEARCH_TICKS"), Pairs.SEARCH_TICKS, "pairs SEARCH_TICKS")
	assert_true(_const(cs, "SEARCH_SEEDS") >= Pairs.SEARCH_SEEDS, "pairs: seeds")


static func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The text of `class <name>` in Checks.cs, up to the next check class.
func _class(name: String) -> String:
	var text := _source(CHECKS)
	var head := "class %s : Check" % name
	var at := text.find(head)
	assert_true(at >= 0, "Checks.cs has %s" % name)
	var end := text.find(" : Check", at + head.length())
	return text.substr(at, -1 if end < 0 else end - at)


## The value of `const long NAME = n;` in `text` (-1 when missing).
func _const(text: String, name: String) -> int:
	var m := RegEx.create_from_string("const long %s = (\\d+);" % name).search(text)
	assert_true(m != null, "const %s found" % name)
	return -1 if m == null else int(m.get_string(1))
