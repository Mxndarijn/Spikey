extends TestCase
## Every beam and boss tell warns SimConfig.WARN_TICKS (2 s): Beam Gates, every
## room variant with a beam, the Watcher's rows, the Crusher's and Saw King's tells.

const Beam := preload("res://sim/hazards/beam.gd")
const BossWatcher := preload("res://sim/hazards/boss_watcher.gd")
const BossCrusher := preload("res://sim/hazards/boss_crusher.gd")
const BossSaw := preload("res://sim/hazards/boss_saw.gd")


func test_the_beam_warning_is_two_seconds() -> void:
	assert_eq(SimConfig.WARN_TICKS, 2 * SimConfig.TICKS_PER_SECOND)


func test_every_beam_in_the_catalog_warns_two_seconds() -> void:
	var seen := 0
	for def: RoomDef in RoomCatalog.all():
		var factories: Array = def.hazards.duplicate()
		for v: RoomVariant in def.variants:
			factories.append_array(v.hazards)
		for f: Callable in factories:
			var h: Hazard = f.call()
			if h is Beam:
				seen += 1
				assert_eq((h as Beam).warn_ticks, SimConfig.WARN_TICKS, def.id)
			if h is BossWatcher:
				seen += 1
	assert_true(seen >= 3, "Beam Gates, Bramble Beams and the Watcher")


func test_the_watcher_warns_two_seconds_before_its_beams() -> void:
	assert_eq(BossWatcher.BEAM_TELL, SimConfig.WARN_TICKS)
	# The phase-3 gaze still marks and flies inside one cycle.
	assert_true(BossWatcher.GAZE_AT + BossWatcher.GAZE_TELL < BossWatcher.CYCLE)
	assert_true(BossWatcher.BEAM_TELL + BossWatcher.BEAM_ON < BossWatcher.CYCLE)


func test_a_beam_gates_row_warns_for_the_whole_two_seconds() -> void:
	var b := Beam.new()
	b.delays.fill(0)
	var warn := 0
	for tick in Beam.PERIOD:
		b.t = tick
		if b.state(0) == Beam.State.WARN:
			warn += 1
	assert_eq(warn, SimConfig.WARN_TICKS)


func test_every_boss_tell_is_two_seconds() -> void:
	assert_eq(BossCrusher.TELL, SimConfig.WARN_TICKS, "slam and jaw")
	assert_eq(BossCrusher.CRATE_FALL - BossCrusher.CRATE_AT, SimConfig.WARN_TICKS, "crate mark")
	assert_eq(BossSaw.TELL, SimConfig.WARN_TICKS, "hops")
	assert_eq(BossSaw.RING_OUT - BossSaw.JUMP, SimConfig.WARN_TICKS, "ring")
