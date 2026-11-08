extends TestCase


func test_dates_map_to_seasons() -> void:
	assert_eq(SeasonCalendar.for_date(10, 31), Seasons.HALLOWEEN)
	assert_eq(SeasonCalendar.for_date(12, 24), Seasons.WINTER)
	assert_eq(SeasonCalendar.for_date(1, 1), Seasons.NEW_YEAR)
	assert_eq(SeasonCalendar.for_date(1, 20), Seasons.NONE)
	assert_eq(SeasonCalendar.for_date(2, 14), Seasons.VALENTINE)
	assert_eq(SeasonCalendar.for_date(4, 2), Seasons.SPRING)
	assert_eq(SeasonCalendar.for_date(8, 15), Seasons.SUMMER)
	assert_eq(SeasonCalendar.for_date(6, 1), Seasons.NONE)


func test_every_season_has_a_name() -> void:
	for s in Seasons.COUNT:
		assert_false(SeasonCalendar.display_name(s).is_empty(), "season %d named" % s)


func test_a_run_records_its_season() -> void:
	var run := RunController.new()
	run.new_run(5, Seasons.SUMMER)
	assert_eq(run.sim.season, Seasons.SUMMER)
	assert_eq(Replay.from_sim(run.sim, PackedInt32Array()).season, Seasons.SUMMER)
	run.free()
