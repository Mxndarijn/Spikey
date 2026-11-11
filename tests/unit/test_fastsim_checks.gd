extends TestCase
## The portal reaction benchmark is defined once, in ArrivalBench
## (tests/support/arrival_bench.gd), and run on FastSim (tools/fastsim
## Reaction.cs, `fastsim check arrival` and `-Mode reaction`). This pins the
## C# copies of its thresholds to the GDScript ones.

const REACTION := "res://tools/fastsim/Reaction.cs"
const SIM_CONFIG := "res://tools/fastsim/Sim/SimConfig.cs"
const RUN_FILE := "res://tools/fastsim/Bots/RunFile.cs"


func test_fastsim_uses_the_arrival_benchmark_thresholds() -> void:
	var rc := FileAccess.get_file_as_string(REACTION)
	assert_eq(_const(rc, "EARLY_DELAY"), ArrivalBench.EARLY_DELAY, "Reaction.EARLY_DELAY")
	assert_eq(_const(rc, "MAX_EXTRA_PCT"), ArrivalBench.MAX_EXTRA_PCT, "Reaction.MAX_EXTRA_PCT")


## FastSim run files (Bots/RunFile.cs) carry FastSim's gameplay version, and
## tools/render_run.ps1 refuses one that differs from the game's.
func test_fastsim_gameplay_version_and_run_file_format() -> void:
	var cfg := FileAccess.get_file_as_string(SIM_CONFIG)
	assert_eq(_const(cfg, "GAMEPLAY_VERSION"), SimConfig.GAMEPLAY_VERSION, "SimConfig.cs")
	var rf := FileAccess.get_file_as_string(RUN_FILE)
	assert_eq(_const(rf, "FORMAT_VERSION"), RunFile.FORMAT_VERSION, "RunFile.cs FORMAT_VERSION")
	assert_true(rf.contains('FORMAT = "%s"' % RunFile.FORMAT), "RunFile.cs FORMAT")
	for key: String in RunFile.from_replay(Replay.new()).to_dict():
		assert_true(rf.contains('["%s"]' % key), "RunFile.cs writes %s" % key)


## The value of `const long NAME = n;` in `text` (-1 when missing).
func _const(text: String, name: String) -> int:
	var m := RegEx.create_from_string("const long %s = (\\d+);" % name).search(text)
	assert_true(m != null, "const %s found" % name)
	return -1 if m == null else int(m.get_string(1))
