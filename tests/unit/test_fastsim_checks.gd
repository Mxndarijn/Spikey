extends TestCase
## The portal reaction benchmark is defined once, in ArrivalBench
## (tests/support/arrival_bench.gd), and run on FastSim-RS (tools/fastsim-rs,
## `fastsim-rs check arrival`). This pins the Rust copies of its thresholds to
## the GDScript ones.

const REACTION := "res://tools/fastsim-rs/fastsim/src/checks/arrival.rs"
const SETUPS := "res://tools/fastsim-rs/fastsim/src/setups.rs"
const SIM_CONFIG := "res://tools/fastsim-rs/sim/src/sim_config.rs"
const RUN_FILE := "res://tools/fastsim-rs/fastsim/src/bots/run_file.rs"


func test_fastsim_uses_the_arrival_benchmark_thresholds() -> void:
	var rc := FileAccess.get_file_as_string(REACTION)
	assert_eq(_const(rc, "EARLY_DELAY"), ArrivalBench.EARLY_DELAY, "Reaction::EARLY_DELAY")
	assert_eq(_const(rc, "MAX_EXTRA_PCT"), ArrivalBench.MAX_EXTRA_PCT, "Reaction::MAX_EXTRA_PCT")
	assert_eq(_const(rc, "MAX_NO_WAY"), ArrivalBench.MAX_NO_WAY, "Reaction::MAX_NO_WAY")
	assert_eq(ArrivalBench.MAX_NO_WAY, 0, "a 1 s reaction always has a way to live")
	var su := FileAccess.get_file_as_string(SETUPS)
	assert_true(su.contains("OFFSETS: [i64; 5] = [0, -65, 65, -32, 32];"), "Reaction::OFFSETS")
	assert_eq(ArrivalBench.OFFSETS, [0, -65, 65, -32, 32] as Array[int])


## FastSim-RS run files (bots/run_file.rs) carry its gameplay version, and
## tools/render_run.ps1 refuses one that differs from the game's.
func test_fastsim_gameplay_version_and_run_file_format() -> void:
	var cfg := FileAccess.get_file_as_string(SIM_CONFIG)
	assert_eq(_const(cfg, "GAMEPLAY_VERSION"), SimConfig.GAMEPLAY_VERSION, "sim_config.rs")
	var rf := FileAccess.get_file_as_string(RUN_FILE)
	assert_eq(_const(rf, "FORMAT_VERSION"), RunFile.FORMAT_VERSION, "run_file.rs FORMAT_VERSION")
	assert_true(rf.contains("FORMAT: &'static str = \"%s\"" % RunFile.FORMAT), "run_file.rs FORMAT")
	for key: String in RunFile.from_replay(Replay.new()).to_dict():
		assert_true(rf.contains('"%s":' % key), "run_file.rs writes %s" % key)


## The value of `const NAME: i64 = n;` in `text` (-1 when missing).
func _const(text: String, name: String) -> int:
	var m := RegEx.create_from_string("const %s: i64 = (\\d+);" % name).search(text)
	assert_true(m != null, "const %s found" % name)
	return -1 if m == null else int(m.get_string(1))
