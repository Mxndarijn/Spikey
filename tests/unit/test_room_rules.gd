extends TestCase


func test_every_wall_keeps_its_guaranteed_gap() -> void:
	var rng := SimRng.new(2024)
	for def in RoomCatalog.all():
		for score in range(0, 200, 7):
			var mask := RoomRules.generate_wall(rng, score, def)
			assert_true(
				RoomRules.longest_gap(mask) >= def.gap,
				"%s score %d mask %d" % [def.id, score, mask]
			)


func test_spike_count_matches_rules() -> void:
	var rng := SimRng.new(5)
	var open := RoomCatalog.find("open")
	for score in [1, 10, 30, 100]:
		var mask := RoomRules.generate_wall(rng, score, open)
		var bits := 0
		for slot in SimConfig.SLOT_COUNT:
			if RoomRules.has_slot(mask, slot):
				bits += 1
		assert_eq(bits, RoomRules.spike_count(score, open), "score %d" % score)


func test_spike_count_grows_and_caps() -> void:
	var open := RoomCatalog.find("open")
	assert_eq(RoomRules.spike_count(1, open), SimConfig.BASE_SPIKES)
	assert_true(RoomRules.spike_count(30, open) > RoomRules.spike_count(1, open))
	assert_eq(RoomRules.spike_count(10000, open), SimConfig.MAX_SPIKES)
	assert_eq(RoomRules.spike_count(10000, RoomCatalog.find("garden")), 3, "bonus room cap")
