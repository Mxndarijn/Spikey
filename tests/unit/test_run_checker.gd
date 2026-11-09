extends TestCase
## The leaderboard checker (server/run_checker.gd): stored runs that replay to
## their claimed result are ok, anything else is rejected, older gameplay
## versions are outdated and newer ones wait for a newer checker.


## A run as worker_pending_runs returns it (JSON numbers are floats there).
func _row(replay: Replay, id: int = 7, day: String = "2026-11-09") -> Dictionary:
	var taps: Array = []
	for t in replay.taps:
		taps.append(float(t))
	return {
		"id": float(id),
		"gameplay_version": float(replay.gameplay_version),
		"seed": float(replay.seed_value),
		"season": float(replay.season),
		"taps": taps,
		"score": float(replay.score),
		"coins": float(replay.coins),
		"end_tick": float(replay.end_tick),
		"day": day,
	}


func _honest() -> Replay:
	return SimBots.play(4242, SimBots.gap_seeker, 2, 3000)


func test_an_honest_run_is_ok() -> void:
	var result := RunChecker.check(_row(_honest()))
	assert_eq(result, {"id": 7, "status": RunChecker.OK, "reason": ""})


func test_a_faked_score_is_rejected() -> void:
	var row := _row(_honest())
	row.score += 50
	var result := RunChecker.check(row)
	assert_eq(result.status, RunChecker.REJECTED)
	assert_true(str(result.reason).begins_with("score mismatch"), result.reason)


func test_faked_coins_are_rejected() -> void:
	var row := _row(_honest())
	row.coins += 20
	var result := RunChecker.check(row)
	assert_eq(result.status, RunChecker.REJECTED)
	assert_true(str(result.reason).begins_with("coins mismatch"), result.reason)


func test_a_wrong_end_tick_is_rejected() -> void:
	var row := _row(_honest())
	row.end_tick += 1
	assert_eq(RunChecker.check(row).status, RunChecker.REJECTED)


func test_runs_from_before_coins_were_stored_check_the_score_only() -> void:
	var row := _row(_honest())
	row.coins = null
	row.end_tick = null
	row.season = null
	assert_eq(RunChecker.check(row).status, RunChecker.OK, "an old honest run")
	row.score += 1
	assert_eq(RunChecker.check(row).status, RunChecker.REJECTED, "an old fake run")


func test_a_season_that_is_not_in_play_is_rejected() -> void:
	var row := _row(_honest())
	row.season = float(Seasons.WINTER)
	var result := RunChecker.check(row)
	assert_eq(result.status, RunChecker.REJECTED, "no winter rooms in early November")
	assert_true(str(result.reason).contains("not in play"), result.reason)


func test_seasons_allow_a_day_either_side() -> void:
	assert_eq(RunChecker.seasons_around("2026-11-09"), [Seasons.NONE])
	var edge := RunChecker.seasons_around("2026-11-30")
	assert_true(
		Seasons.NONE in edge and Seasons.WINTER in edge, "a phone may already be in December"
	)
	assert_eq(RunChecker.seasons_around("yesterday"), [], "a day that can't be read")
	var row := _row(_honest())
	row.day = "?"
	assert_eq(RunChecker.check(row).status, RunChecker.REJECTED)


func test_other_gameplay_versions() -> void:
	var row := _row(_honest())
	row.gameplay_version = float(SimConfig.GAMEPLAY_VERSION - 1)
	assert_eq(RunChecker.check(row).status, RunChecker.OUTDATED, "an old app")
	row.gameplay_version = float(SimConfig.GAMEPLAY_VERSION + 1)
	assert_eq(RunChecker.check(row), {}, "newer than the checker: stays pending")


func test_broken_rows_are_rejected_without_errors() -> void:
	var row := _row(_honest())
	row.taps = [1, {"x": 2}]
	assert_eq(RunChecker.check(row).status, RunChecker.REJECTED, "taps that aren't numbers")
	row.taps = "1,2,3"
	assert_eq(RunChecker.check(row).status, RunChecker.REJECTED, "taps that aren't a list")
	row.taps = [50, 10]
	assert_eq(RunChecker.check(row).status, RunChecker.REJECTED, "taps out of order")
	var empty := RunChecker.check({})
	assert_eq(empty.status, RunChecker.OUTDATED, "no version reads as an old one")
