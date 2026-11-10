extends TestCase


func test_honest_run_verifies() -> void:
	var replay := SimBots.play(4242, SimBots.gap_seeker, 2)
	var result := replay.verify()
	assert_true(result.ok, result.reason)


func test_round_trip_through_json() -> void:
	var replay := SimBots.play(4243, SimBots.gap_seeker, 3)
	var json := JSON.stringify(replay.to_dict())
	var back := Replay.from_dict(JSON.parse_string(json))
	assert_eq(back.taps, replay.taps)
	assert_eq(back.seed_value, replay.seed_value)
	assert_true(back.verify().ok)


func test_inflated_score_rejected() -> void:
	var replay := SimBots.play(4244, SimBots.gap_seeker, 4)
	replay.score += 5
	var result := replay.verify()
	assert_false(result.ok)
	assert_true(result.reason.begins_with("score mismatch"), result.reason)


func test_wrong_seed_rejected() -> void:
	var replay := SimBots.play(4245, SimBots.gap_seeker, 5)
	replay.seed_value += 1
	assert_false(replay.verify().ok)


func test_unknown_version_rejected() -> void:
	var replay := SimBots.play(4246, SimBots.gap_seeker, 6)
	replay.gameplay_version = 999
	assert_false(replay.verify().ok)


func _revived() -> Replay:
	return SimBots.play_revived(4247, SimBots.gap_seeker, 7, 1200, 900)


func test_revived_run_verifies() -> void:
	var replay := _revived()
	assert_eq(replay.revive_ticks.size(), 1, "the run was revived")
	var result := replay.verify()
	assert_true(result.ok, result.reason)


func test_revive_round_trip_through_json() -> void:
	var replay := _revived()
	var back := Replay.from_dict(JSON.parse_string(JSON.stringify(replay.to_dict())))
	assert_eq(back.revive_ticks, replay.revive_ticks)
	assert_true(back.verify().ok)


func test_revived_run_without_its_revive_rejected() -> void:
	var replay := _revived()
	replay.revive_ticks = PackedInt32Array()
	assert_false(replay.verify().ok)


func test_revive_at_the_wrong_tick_rejected() -> void:
	for shift: int in [-1, 1]:
		var replay := _revived()
		replay.revive_ticks[0] += shift
		var result := replay.verify()
		assert_false(result.ok)
		assert_eq(result.reason, "revive without a death")


func test_revive_added_to_a_finished_run_rejected() -> void:
	var replay := SimBots.play(4242, SimBots.gap_seeker, 2)
	replay.revive_ticks = PackedInt32Array([replay.end_tick])
	assert_false(replay.verify().ok, "the run would have gone on")


func test_too_many_revives_rejected() -> void:
	var replay := _revived()
	replay.revive_ticks.append(replay.end_tick)
	var result := replay.verify()
	assert_false(result.ok)
	assert_eq(result.reason, "too many revives")


func test_unsorted_taps_rejected() -> void:
	var replay := Replay.new()
	replay.taps = PackedInt32Array([10, 5])
	assert_false(replay.verify().ok)
