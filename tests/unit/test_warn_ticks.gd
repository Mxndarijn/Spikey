extends TestCase
## Every beam and boss tell warns SimConfig.WARN_TICKS (2 s): Beam Gates, every
## room variant with a beam, the Watcher's rows, the Crusher's and Saw King's tells.
## (The Watcher's gaze dart has its own mark, GAZE_TELL: tests/unit/test_room_fixes.gd.)

const RoomsTest := preload("res://tests/unit/test_rooms.gd")
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
	# Beam Gates is generated: its beams are built when the room starts.
	for s in 5:
		for h: Hazard in RoomsTest.sim_in_room("beams", s).room.hazards:
			if h is Beam:
				seen += 1
				assert_eq((h as Beam).warn_ticks, SimConfig.WARN_TICKS, "beams")
	assert_true(seen >= 6, "Beam Gates and the Watcher")


func test_the_watcher_warns_two_seconds_before_its_beams() -> void:
	assert_eq(BossWatcher.BEAM_TELL, SimConfig.WARN_TICKS)
	assert_eq(BossWatcher.GAZE_TELL, SimConfig.WARN_TICKS, "the gaze dart's mark")
	assert_true(BossWatcher.BEAM_TELL + BossWatcher.BEAM_ON < BossWatcher.CYCLE)
	# A dart is across before the next mark: phase 2 at every tier, phase 3
	# inside its cycle.
	var across: int = (SimConfig.WORLD_W + BossWatcher.DART_LEN) / BossWatcher.DART_SPEED + 1
	assert_true(BossWatcher.GAZE_TELL + across <= BossWatcher.GAZE_FAST)
	assert_true(BossWatcher.GAZE_TELL + across <= BossWatcher.GAZE)
	assert_true(BossWatcher.GAZE_AT + BossWatcher.GAZE_TELL + across <= BossWatcher.CYCLE)


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


## The longer tells keep each attack's rhythm: the Crusher's slam holds 110
## steps and is back up, and its crates have landed, before the next cycle; the
## Saw King's blades stay out 90 steps and are back in before its next ring.
func test_boss_attacks_finish_inside_their_cycle() -> void:
	assert_eq(BossCrusher.LIFT_AT - BossCrusher.SLAM_AT, 110, "slam hold")
	var lowest: int = BossCrusher.SLAMS[BossCrusher.SLAMS.size() - 1] + BossCrusher.SLAM_TIER
	var lift: int = (lowest - BossCrusher.PRESS_REST) / BossCrusher.LIFT + 1
	assert_true(BossCrusher.LIFT_AT + lift <= BossCrusher.CYCLE, "back up before the next slam")
	var fall: int = (2 * BossCrusher.LANE_HALF[0]) / BossCrusher.CRATE_SPEED + 2
	assert_true(BossCrusher.CRATE_FALL + fall <= BossCrusher.CYCLE, "crates land inside the cycle")
	assert_eq(BossSaw.RING_IN - BossSaw.RING_OUT, 90, "ring out")
	var back: int = BossSaw.RING_MAX_TIER3 / BossSaw.RING_SPEED + 1
	assert_true(BossSaw.RING_IN + back <= BossSaw.RING_CYCLE, "blades in before the next ring")
