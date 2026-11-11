extends TestCase
## The portal reaction benchmark is defined once, in ArrivalBench
## (tests/support/arrival_bench.gd), and run on FastSim (tools/fastsim
## Reaction.cs, `fastsim check arrival` and `-Mode reaction`). This pins the
## C# copies of its thresholds to the GDScript ones.

const REACTION := "res://tools/fastsim/Reaction.cs"


func test_fastsim_uses_the_arrival_benchmark_thresholds() -> void:
	var rc := FileAccess.get_file_as_string(REACTION)
	assert_eq(_const(rc, "EARLY_DELAY"), ArrivalBench.EARLY_DELAY, "Reaction.EARLY_DELAY")
	assert_eq(_const(rc, "MAX_EXTRA_PCT"), ArrivalBench.MAX_EXTRA_PCT, "Reaction.MAX_EXTRA_PCT")


## The value of `const long NAME = n;` in `text` (-1 when missing).
func _const(text: String, name: String) -> int:
	var m := RegEx.create_from_string("const long %s = (\\d+);" % name).search(text)
	assert_true(m != null, "const %s found" % name)
	return -1 if m == null else int(m.get_string(1))
