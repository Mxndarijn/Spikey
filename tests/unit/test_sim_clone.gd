extends TestCase
## SimClone's fast copy must be a true deep copy: the same as the slow generic
## copy, step for step, in every room, and it must not miss a sim field.

const PLAY_TICKS := 40
const COMPARE_TICKS := 240


func test_hand_copied_field_lists_match_the_classes() -> void:
	var sim := GameSim.new(3)
	_assert_same_names(SimClone.field_names(sim), SimClone.GAME_SIM_FIELDS, "GameSim")
	_assert_same_names(SimClone.field_names(sim.room), SimClone.ROOM_FIELDS, "RoomRuntime")
	_assert_same_names(SimClone.field_names(sim._rng), SimClone.RNG_FIELDS, "SimRng")


func test_sim_state_copy_keeps_every_field() -> void:
	var s := SimState.new()
	var i := 0
	for name: StringName in SimClone.field_names(s):
		var v: Variant = s.get(name)
		if typeof(v) == TYPE_BOOL:
			s.set(name, not v)
		else:
			s.set(name, int(v) + 7 + i)
		i += 1
	var c := s.copy()
	for name: StringName in SimClone.field_names(s):
		assert_eq(c.get(name), s.get(name), "SimState.copy() misses %s" % name)


func test_copy_matches_generic_copy_in_every_room() -> void:
	var rooms := RoomCatalog.all()
	for index in rooms.size():
		var def: RoomDef = rooms[index]
		var sim := GameSim.new(2024 + index, def.season, index)
		var rng := SimRng.new(index)
		for t in PLAY_TICKS:
			sim.step(PlannerBot.aim(sim, rng))
		var fast := SimClone.copy(sim)
		var slow := SimClone.copy_generic(sim)
		var before := sim.state.checksum()
		var taps := SimRng.new(99 + index)
		for t in COMPARE_TICKS:
			var tap := taps.next_below(12) == 0
			fast.step(tap)
			slow.step(tap)
			assert_eq(fast.state.checksum(), slow.state.checksum(), "%s tick %d" % [def.id, t])
			assert_eq(fast.room.checksum(1), slow.room.checksum(1), "%s room tick %d" % [def.id, t])
			assert_eq(fast.events, slow.events, "%s events tick %d" % [def.id, t])
		# The original is untouched.
		assert_eq(sim.state.checksum(), before, "%s original changed" % def.id)


func _assert_same_names(
	actual: Array[StringName], expected: Array[StringName], what: String
) -> void:
	for n in actual:
		assert_true(n in expected, "%s.%s is not copied by SimClone.copy()" % [what, n])
	for n in expected:
		assert_true(n in actual, "SimClone lists %s.%s, which no longer exists" % [what, n])
