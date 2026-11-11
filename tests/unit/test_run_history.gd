extends TestCase
## Your runs: the last 100 runs and up to 20 saved ones stay on the phone, the
## oldest unsaved run goes first, a saved run never goes, runs from an older
## gameplay version can't be watched, and a stored run replays as played.

const STORE_PATH := "user://test_run_history_runs.json"
const PROFILE_PATH := "user://test_run_history_profile.json"


static func _record(score: int = 5, played_at: int = 1000) -> RunRecord:
	var replay := Replay.new()
	replay.seed_value = score * 7
	replay.score = score
	return RunRecord.make(replay, {ItemKind.WORLD: ThemeCatalog.DEFAULT_ID}, played_at, 3)


static func _history(count: int) -> RunHistory:
	var h := RunHistory.new()
	for i in count:
		h.add(_record(i))
	return h


static func _ids(list: Array[RunRecord]) -> Array[int]:
	var out: Array[int] = []
	for r in list:
		out.append(r.id)
	return out


func _make_main() -> Node:
	SafeFile.remove(PROFILE_PATH)
	SafeFile.remove(STORE_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = PROFILE_PATH
	main.runs_path = STORE_PATH
	main.leaderboard = SampleLeaderboard.new(Profile.new())
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free_main(main: Node) -> void:
	main.free()
	SafeFile.remove(PROFILE_PATH)
	SafeFile.remove(STORE_PATH)


static func _play_out(run: RunController) -> void:
	while run.sim != null and not run.sim.is_over() and run.sim.state.tick < SimConfig.MAX_TICKS:
		run.advance()


func test_keeps_the_last_100_and_drops_the_oldest_first() -> void:
	var h := _history(130)
	assert_eq(h.records.size(), RunHistory.LATEST_MAX, "100 runs kept")
	assert_eq(h.latest().size(), 100)
	assert_eq(h.last().id, 130, "newest first")
	assert_eq(h.records[99].id, 31, "the 30 oldest went")
	assert_true(h.find(30) == null, "run 30 dropped")
	h.add(_record())
	assert_true(h.find(31) == null, "the next run pushes the oldest out")
	assert_eq(h.records.size(), 100)


func test_saved_runs_are_never_dropped() -> void:
	var h := _history(5)
	assert_true(h.save_run(1))
	assert_true(h.save_run(2))
	for i in 200:
		h.add(_record(i))
	assert_true(h.find(1) != null and h.find(2) != null, "saved runs stay")
	assert_eq(h.records.size(), 102, "100 latest plus the 2 saved")
	assert_eq(h.latest().size(), 100)
	assert_false(1 in _ids(h.latest()), "an old saved run is only in Saved")
	assert_eq(_ids(h.saved()), [2, 1] as Array[int], "Saved, newest first")


func test_saved_holds_20_and_removing_makes_room() -> void:
	var h := _history(30)
	for id in range(1, 21):
		assert_true(h.save_run(id), "save %d" % id)
	assert_true(h.is_saved_full())
	assert_false(h.save_run(25), "a 21st run can't be saved")
	assert_false(h.find(25).saved)
	assert_true(h.save_run(20), "saving a saved run again is fine")
	assert_true(h.unsave_run(20))
	assert_eq(h.saved_count(), 19)
	assert_true(h.save_run(25), "room again")
	assert_false(h.save_run(999), "no such run")
	assert_false(h.unsave_run(26), "not saved")


func test_removing_an_old_saved_run_drops_it() -> void:
	var h := _history(3)
	h.save_run(1)
	h.save_run(3)
	for i in 100:
		h.add(_record(i))
	assert_true(h.unsave_run(1))
	assert_true(h.find(1) == null, "older than the last 100: gone once unsaved")
	h.save_run(103)
	assert_true(h.unsave_run(103))
	assert_true(h.find(103) != null, "a recent run stays in Latest")


func test_store_writes_every_change_and_reads_it_back() -> void:
	SafeFile.remove(STORE_PATH)
	var store := RunStore.new(STORE_PATH)
	assert_true(store.history.records.is_empty(), "nothing yet")
	var replay := SimBots.play(4410, SimBots.gap_seeker, 2, 300)
	var look := {ItemKind.WORLD: "ice", ItemKind.FLYER: "dash"}
	var r := store.add(RunRecord.make(replay, look, 1_700_000_000, 4, 12, true))
	store.add(_record(3))
	assert_true(store.set_saved(r.id, true))
	var again := RunStore.new(STORE_PATH)
	assert_eq(again.history.records.size(), 2)
	var back := again.history.find(r.id)
	assert_true(back.saved, "saved")
	assert_eq(back.score(), replay.score)
	assert_eq(back.run.replay.taps, replay.taps, "the taps")
	assert_eq(back.run.replay.checksum, replay.checksum)
	assert_eq(back.run.replay.gameplay_version, SimConfig.GAMEPLAY_VERSION)
	assert_eq(back.run.loadout.get(ItemKind.FLYER, ""), "dash", "its look")
	assert_eq(back.world, "ice")
	assert_eq(back.rooms, 4)
	assert_eq(back.revived_at, 12)
	assert_true(back.revived())
	assert_true(back.best)
	assert_eq(back.played_at, 1_700_000_000)
	# New runs keep counting up after a reload.
	assert_eq(again.add(_record()).id, 3)
	assert_true(again.set_saved(r.id, false))
	assert_false(RunStore.new(STORE_PATH).history.find(r.id).saved, "removed from Saved")
	SafeFile.remove(STORE_PATH)


func test_older_version_runs_cant_be_watched() -> void:
	var r := _record(9)
	assert_true(r.watchable())
	r.run.replay.gameplay_version = SimConfig.GAMEPLAY_VERSION - 1
	assert_false(r.watchable(), "older version")
	var row := RunRow.new(r, 2000)
	assert_false(row.watch_button().visible, "no Watch button")
	assert_eq(row.detail_line(), RunRow.NO_REPLAY, "says the replay is gone")
	row.free()
	var main := _make_main()
	main.watch_run(r)
	assert_eq(main.mode, main.Mode.REPLAY)
	assert_eq(main._hud.replay_hud().title_text(), ReplayDriver.OLD_VERSION_MESSAGE)
	assert_true(main._run.driver == null, "nothing plays")
	main._leave_replay()
	assert_true(main._menus.current() is RunsScreen, "back on Your runs")
	_free_main(main)


func test_a_stored_run_replays_as_played() -> void:
	var main := _make_main()
	var recorded := SimBots.play_revived(4420, SimBots.gap_seeker, 3, 200, 300)
	assert_eq(recorded.revive_ticks.size(), 1, "a revived run")
	var look := LeaderboardService.loadout_of(main._profile)
	main.runs().add(RunRecord.make(recorded, look, 1000, 2, 4))
	# Through the file, as after a restart.
	var stored: RunRecord = RunStore.new(STORE_PATH).history.last()
	main.show_runs()
	var screen := main._menus.current() as RunsScreen
	assert_eq(screen.rows().size(), 1)
	main.watch_run(stored, main.show_runs.bind(RunsScreen.SAVED))
	assert_eq(main.mode, main.Mode.REPLAY)
	assert_eq(main._hud.replay_hud().chip_text(), "Replay: You, %d" % recorded.score)
	var best_before: int = main._profile.best_score
	_play_out(main._run)
	assert_eq(main._run.sim.state.score, recorded.score, "the recorded score")
	assert_eq(main._run.sim.state.tick, recorded.end_tick, "the recorded end")
	assert_eq(main._run.sim.checksum(), recorded.checksum, "the same final state")
	assert_eq(main._profile.best_score, best_before, "a replay changes nothing")
	assert_eq(main.runs().history.records.size(), 1, "and adds no run")
	main._leave_replay()
	var back := main._menus.current() as RunsScreen
	assert_true(back != null, "back on Your runs")
	assert_eq(back.tab(), RunsScreen.SAVED, "on the tab it came from")
	_free_main(main)


func test_a_finished_run_is_kept_and_shows_on_home() -> void:
	var main := _make_main()
	var recorded := SimBots.play(4430, SimBots.gap_seeker, 5, 300)
	main.mode = main.Mode.RUN
	main._rooms_cleared = 2
	main._finish_run(recorded)
	var last: RunRecord = main.runs().history.last()
	assert_true(last != null, "the run is kept")
	assert_eq(last.score(), recorded.score)
	assert_eq(last.rooms, 3, "rooms reached: cleared plus the last one")
	assert_eq(last.best, recorded.score > 0, "a first scoring run is a best")
	assert_eq(last.world, main._profile.equipped_id(ItemKind.WORLD))
	assert_false(last.revived())
	assert_true(FileAccess.file_exists(STORE_PATH), "written at once")
	main.show_home()
	var home := main._menus.current() as HomeScreen
	assert_true(home.runs_line().begins_with("Last: %d in " % recorded.score), home.runs_line())
	assert_true(home.replay_button().visible, "the last run can be watched")
	home.watch_last_pressed.emit(last)
	assert_eq(main.mode, main.Mode.REPLAY)
	main._leave_replay()
	assert_true(main._menus.current() is HomeScreen, "back Home")
	home = main._menus.current() as HomeScreen
	home.runs_pressed.emit()
	assert_true(main._menus.current() is RunsScreen, "the card opens Your runs")
	_free_main(main)


func test_home_card_before_the_first_run() -> void:
	var p := Profile.new()
	var home := HomeScreen.new(p, AppServices.offline(p))
	(Engine.get_main_loop() as SceneTree).root.add_child(home)
	assert_eq(home.runs_line(), HomeScreen.NO_RUNS)
	assert_false(home.replay_button().visible, "nothing to watch yet")
	assert_true(
		home.shop_button().get_combined_minimum_size().y >= UiTokens.SIZE_TAP_MIN,
		"Shop is tall enough"
	)
	var signalled := [false]
	home.store_pressed.connect(func() -> void: signalled[0] = true)
	home.shop_button().pressed.emit()
	assert_true(signalled[0], "Shop opens the Shop")
	home.free()


func test_runs_screen_tabs_and_bookmarks() -> void:
	SafeFile.remove(STORE_PATH)
	var store := RunStore.new(STORE_PATH)
	for i in 25:
		store.add(_record(i, 1000 + i))
	var screen := RunsScreen.new(store)
	screen.now = 2000
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_eq(screen.tab_text(RunsScreen.SAVED), "Saved 0/20")
	assert_eq(screen.rows().size(), 25)
	var first := screen.rows()[0]
	first.save_pressed.emit(first.record)
	assert_true(first.record.saved)
	assert_eq(screen.tab_text(RunsScreen.SAVED), "Saved 1/20")
	assert_eq(first.save_button().icon, RunRow.BOOKMARK_ON_ICON, "a filled bookmark")
	for i in range(1, 20):
		var row := screen.rows()[i]
		row.save_pressed.emit(row.record)
	var extra := screen.rows()[20]
	extra.save_pressed.emit(extra.record)
	assert_false(extra.record.saved, "Saved is full")
	assert_eq(screen.hint_text(), RunsScreen.FULL_HINT)
	screen.show_tab(RunsScreen.SAVED)
	assert_eq(screen.rows().size(), 20)
	var gone := screen.rows()[0]
	gone.save_pressed.emit(gone.record)
	assert_eq(screen.rows().size(), 19, "removed from Saved")
	assert_eq(screen.tab_text(RunsScreen.SAVED), "Saved 19/20")
	screen.free()
	store = RunStore.new(STORE_PATH)
	store.history.records.clear()
	var empty := RunsScreen.new(store, RunsScreen.SAVED)
	(Engine.get_main_loop() as SceneTree).root.add_child(empty)
	assert_eq(empty.empty_text(), RunsScreen.SAVED_EMPTY)
	empty.free()
	SafeFile.remove(STORE_PATH)


func test_when_and_detail_lines() -> void:
	var noon := 1_762_862_400  # 11 Nov 2025, 12:00 UTC
	assert_eq(RunRow.when_text(noon - 20, noon), "Just now")
	assert_eq(RunRow.when_text(noon - 6 * 60, noon), "6 min ago")
	assert_eq(RunRow.when_text(noon - 2 * 3600 + 120, noon), "Today, 10:02")
	assert_eq(RunRow.when_text(noon - 86400, noon), "Yesterday")
	assert_eq(RunRow.when_text(noon - 8 * 86400, noon), "3 Nov")
	assert_eq(RunRow.when_text(noon - 400 * 86400, noon), "7 Oct 2024")
	assert_eq(RunRow.when_text(noon - 11 * 3600, noon), "Today, 01:00")
	assert_eq(RunRow.when_text(noon - 11 * 3600, noon, -120), "Yesterday", "two hours west")
	var r := _record(17)
	r.rooms = 4
	r.revived_at = 12
	var world := Catalog.world(ThemeCatalog.DEFAULT_ID).display_name
	assert_eq(RunRow.detail_text(r), "%s, 4 rooms, revived at 12" % world)
	r.rooms = 1
	r.revived_at = -1
	assert_eq(RunRow.detail_text(r), "%s, 1 room" % world)
	r.played_at = noon - 30
	assert_eq(HomeScreen.runs_line_text(r, noon), "Last: 17 in %s, just now" % world)
