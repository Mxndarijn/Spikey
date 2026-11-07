extends TestCase


func test_every_wall_keeps_its_guaranteed_gap() -> void:
	var rng := SimRng.new(2024)
	for score in range(0, 200):
		for kind in RoomRules.kind_count():
			var mask := RoomRules.generate_wall(rng, score, kind)
			assert_true(
				RoomRules.longest_gap(mask) >= RoomRules.gap_size(kind),
				"score %d kind %d mask %d" % [score, kind, mask]
			)


func test_spike_count_matches_rules() -> void:
	var rng := SimRng.new(5)
	for score in [1, 10, 30, 100]:
		var mask := RoomRules.generate_wall(rng, score, 0)
		var bits := 0
		for slot in SimConfig.SLOT_COUNT:
			if RoomRules.has_slot(mask, slot):
				bits += 1
		assert_eq(bits, RoomRules.spike_count(score, 0), "score %d" % score)


func test_spike_count_grows_and_caps() -> void:
	assert_eq(RoomRules.spike_count(1, 0), SimConfig.BASE_SPIKES)
	assert_true(RoomRules.spike_count(30, 0) > RoomRules.spike_count(1, 0))
	assert_eq(RoomRules.spike_count(10000, 0), SimConfig.MAX_SPIKES)


func test_next_kind_never_repeats() -> void:
	var rng := SimRng.new(99)
	var kind := 0
	for i in 200:
		var next := RoomRules.next_kind(rng, kind)
		assert_ne(next, kind)
		assert_between(next, 0, RoomRules.kind_count() - 1)
		kind = next
