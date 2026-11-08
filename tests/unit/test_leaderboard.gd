extends TestCase
## The leaderboard service interface, the sample boards, the screen and its
## name dialog, and the Home button that opens it.

const TEST_PATH := "user://test_leaderboard_profile.json"


func _profile(best: int = 87) -> Profile:
	var p := Profile.new()
	p.best_score = best
	p.onboarded = true
	p.leaderboard_name = "buzzybee"
	for kind in Catalog.KINDS:
		var id: String = Catalog.ids(kind)[0]
		p.grant(kind, id)
		p.equip(kind, id)
	return p


## Sample boards plus a fake run store: request_run answers with a tiny run.
class RunService:
	extends SampleLeaderboard
	var asked := 0

	func request_run(run_id: int) -> void:
		asked = run_id
		var run := {"run": run_id, "seed": 5, "taps": [3, 9], "gameplay_version": 1, "loadout": {}}
		_deliver_run.call_deferred(run_id, run)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _screen(p: Profile, service: LeaderboardService, id: String = "") -> LeaderboardScreen:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	_tree().root.add_child(holder)
	var screen := LeaderboardScreen.new(p, service, id)
	holder.add_child(screen)
	return screen


func _free(screen: LeaderboardScreen) -> void:
	screen.get_parent().free()


func test_names_follow_the_rules() -> void:
	for ok in ["abc", "buzzy.bee", "Tap_Tap_Leo_12", "ZippyFlap42"]:
		assert_true(LeaderboardService.is_valid_name(ok), "%s is fine" % ok)
	for bad in ["", "ab", "has space", "emoji❤", "fifteen_letters", "dash-name"]:
		assert_false(LeaderboardService.is_valid_name(bad), "%s is refused" % bad)
	assert_eq(LeaderboardService.name_problem("ab"), "Use at least 3 characters.")
	var rng := RandomNumberGenerator.new()
	for i in 50:
		rng.seed = i
		var n := LeaderboardService.suggest_name(rng)
		assert_true(LeaderboardService.is_valid_name(n), "suggestion %s is valid" % n)


func test_name_is_saved_and_bad_saved_names_are_dropped() -> void:
	var p := _profile()
	var back := Profile.from_dict(p.to_dict())
	assert_eq(back.leaderboard_name, "buzzybee")
	var d := p.to_dict()
	d["leaderboard_name"] = "no spaces allowed"
	assert_eq(Profile.from_dict(d).leaderboard_name, "", "an invalid saved name is ignored")


## The base service has no server: every board comes back offline, next frame.
func test_base_service_is_offline_and_answers_next_frame() -> void:
	var service := LeaderboardService.new()
	var got: Array[LeaderboardBoard] = []
	service.board_loaded.connect(func(b: LeaderboardBoard) -> void: got.append(b))
	service.request_board(LeaderboardService.DAILY)
	assert_eq(got.size(), 0, "never inside request_board()")
	await _tree().process_frame
	assert_eq(got.size(), 1, "arrives on the next frame")
	if got.size() == 1:
		assert_eq(got[0].id, LeaderboardService.DAILY)
		assert_eq(got[0].status, LeaderboardBoard.Status.OFFLINE)
	assert_eq(service.cached_rank(LeaderboardService.DAILY), 0)


func test_sample_boards_are_sorted_and_verified() -> void:
	var service := SampleLeaderboard.new(_profile())
	service.signed_in = true
	service.submit_run(150)
	for id in LeaderboardService.BOARDS:
		var b := service.build_board(id)
		assert_eq(b.status, LeaderboardBoard.Status.OK, "%s loads" % id)
		assert_true(b.entries.size() >= 3, "%s has a podium" % id)
		for i in b.entries.size():
			var e := b.entries[i]
			assert_eq(e.rank, i + 1, "%s ranks count up" % id)
			assert_true(e.verified, "%s rows are verified" % id)
			assert_true(Catalog.flyer(e.flyer_id) != null, "%s uses real flyers" % id)
			if i > 0:
				assert_true(e.score <= b.entries[i - 1].score, "%s is best first" % id)
		assert_true(b.me != null, "%s has the player" % id)
		assert_true(b.players >= b.entries.size(), "%s counts everyone" % id)


func test_daily_board_counts_only_todays_runs() -> void:
	var service := SampleLeaderboard.new(_profile(300))
	assert_true(service.build_board(LeaderboardService.DAILY).me == null, "no run today yet")
	assert_eq(service.cached_rank(LeaderboardService.DAILY), 0)
	service.submit_run(64)
	var low := service.cached_rank(LeaderboardService.DAILY)
	assert_true(low > 12, "a low score sits below the listed rows (#%d)" % low)
	service.submit_run(171)
	var b := service.build_board(LeaderboardService.DAILY)
	assert_eq(b.me.rank, 3, "171 beats the third place's 170")
	assert_true(b.entries[2].is_me, "the player stands on the podium")
	assert_eq(b.entries[2].player_name, "buzzybee")
	assert_true(b.resets_in_s > 0 and b.resets_in_s <= 86400, "resets within a day")


func test_tier_board_groups_players_near_your_best() -> void:
	assert_eq(SampleLeaderboard.tier_for(0), "Bronze")
	assert_eq(SampleLeaderboard.tier_for(95), "Gold")
	assert_eq(SampleLeaderboard.tier_for(400), "Diamond")
	var b := SampleLeaderboard.new(_profile(95)).build_board(LeaderboardService.TIER)
	assert_eq(b.tier_name, "Gold")
	for e in b.entries:
		assert_between(e.score, 70, 125, "tier scores stay near 95")


func test_offline_and_signed_out_boards() -> void:
	var service := SampleLeaderboard.new(_profile())
	assert_eq(
		service.build_board(LeaderboardService.FRIENDS).status, LeaderboardBoard.Status.SIGNED_OUT
	)
	service.sign_in()
	assert_true(service.is_signed_in())
	var friends := service.build_board(LeaderboardService.FRIENDS)
	assert_eq(friends.status, LeaderboardBoard.Status.OK)
	assert_eq(friends.me.rank, 2, "87 sits between Noor's 131 and Ines's 66")
	service.online = false
	for id in LeaderboardService.BOARDS:
		assert_eq(service.build_board(id).status, LeaderboardBoard.Status.OFFLINE)


func test_captions_and_notes() -> void:
	assert_eq(LeaderboardScreen.duration(9 * 3600 + 12 * 60 + 5), "9h 12m")
	assert_eq(LeaderboardScreen.duration(23 * 60 + 41), "23m 41s")
	assert_eq(LeaderboardScreen.thousands(8930), "8,930")
	assert_eq(LeaderboardScreen.thousands(1234567), "1,234,567")
	assert_eq(LeaderboardScreen.thousands(12), "12")
	var service := SampleLeaderboard.new(_profile())
	service.clock_s = 86400 - (9 * 3600 + 12 * 60)
	service.submit_run(87)
	var daily := service.build_board(LeaderboardService.DAILY)
	assert_eq(LeaderboardScreen.caption_left(daily), "Resets in 9h 12m")
	assert_eq(
		LeaderboardScreen.caption_right(daily),
		"%s players" % LeaderboardScreen.thousands(daily.players)
	)
	assert_eq(
		LeaderboardScreen.pinned_note(daily),
		"of %s today" % LeaderboardScreen.thousands(daily.players)
	)
	var all_time := service.build_board(LeaderboardService.ALL_TIME)
	assert_true(LeaderboardScreen.pinned_note(all_time).begins_with("Top "), "all-time says top %")
	var nobody := LeaderboardBoard.make(LeaderboardService.DAILY)
	assert_eq(LeaderboardScreen.pinned_note(nobody), "No run today yet")
	assert_eq(LeaderboardScreen.caption_right(nobody), "No players yet")


func test_screen_loads_then_shows_podium_list_and_your_row() -> void:
	var p := _profile()
	var service := SampleLeaderboard.new(p)
	service.submit_run(87)
	var screen := _screen(p, service)
	assert_eq(screen.tab_names(), ["Daily", "All-time"])
	assert_eq(screen.board_id(), LeaderboardService.DAILY, "opens on Daily")
	assert_eq(screen.view, LeaderboardScreen.View.LOADING, "loading first")
	await _tree().process_frame
	assert_eq(screen.view, LeaderboardScreen.View.BOARD)
	var b := screen.board()
	assert_eq(screen.rows().size(), b.entries.size() - 3, "rows start at 4th place")
	var spots := screen.podium().spots()
	assert_eq(spots[1], b.entries[0], "first stands in the middle")
	assert_eq(screen.pinned_rank_text(), "#%s" % LeaderboardScreen.thousands(b.me.rank))
	assert_true(screen.name_dialog() == null, "a player with a name is not asked again")
	_free(screen)


func test_tabs_switch_boards() -> void:
	var p := _profile()
	var service := SampleLeaderboard.new(p)
	var screen := _screen(p, service)
	await _tree().process_frame
	screen.select_board(LeaderboardService.ALL_TIME)
	assert_eq(screen.view, LeaderboardScreen.View.LOADING)
	await _tree().process_frame
	assert_eq(screen.board().id, LeaderboardService.ALL_TIME)
	assert_true(screen.caption_text().begins_with("Best run per player"), screen.caption_text())
	screen.select_board(LeaderboardService.TIER)
	assert_eq(screen.board_id(), LeaderboardService.ALL_TIME, "tier is not a tab for now")
	service.online = false
	screen.select_board(LeaderboardService.DAILY)
	await _tree().process_frame
	assert_eq(screen.view, LeaderboardScreen.View.OFFLINE)
	_free(screen)


## The signed-out card still works for when Friends comes back.
func test_signed_out_card_signs_in() -> void:
	var p := _profile()
	var service := SampleLeaderboard.new(p)
	var screen := _screen(p, service)
	await _tree().process_frame
	screen.show_board(service.build_board(LeaderboardService.FRIENDS))
	assert_eq(screen.view, LeaderboardScreen.View.SIGNED_OUT)
	screen._sign_in()
	assert_true(service.is_signed_in())
	_free(screen)


func test_daily_without_a_run_and_right_after_reset() -> void:
	var p := _profile()
	var service := SampleLeaderboard.new(p)
	var screen := _screen(p, service)
	await _tree().process_frame
	assert_eq(screen.pinned_rank_text(), "#–", "no rank before a run today")
	assert_eq(screen.pinned_note_text(), "No run today yet")
	var empty := LeaderboardBoard.make(LeaderboardService.DAILY)
	screen.show_board(empty)
	assert_eq(screen.view, LeaderboardScreen.View.EMPTY)
	var waiting := 0
	for s: Variant in screen.podium().spots():
		if s == null:
			waiting += 1
	assert_eq(waiting, 3, "three empty podium places")
	_free(screen)


func test_first_visit_asks_for_a_name() -> void:
	var p := _profile()
	p.leaderboard_name = ""
	var service := SampleLeaderboard.new(p)
	var screen := _screen(p, service)
	var dialog := screen.name_dialog()
	assert_true(dialog != null, "the name dialog opens")
	if dialog == null:
		_free(screen)
		return
	assert_true(LeaderboardService.is_valid_name(dialog.draft()), "a valid name is suggested")
	dialog.set_draft("no")
	assert_false(dialog.can_save(), "too short")
	assert_eq(dialog.hint_text(), "Use at least 3 characters.")
	dialog.set_draft("bad name")
	assert_false(dialog.can_save(), "spaces are refused")
	dialog.shuffle()
	assert_true(dialog.can_save(), "the dice always give a valid name")
	var names: Array[String] = []
	screen.name_changed.connect(func(n: String) -> void: names.append(n))
	dialog.set_draft("Leo.flaps")
	dialog._on_submit()
	assert_eq(p.leaderboard_name, "Leo.flaps", "saved in the profile")
	assert_eq(names, ["Leo.flaps"], "the screen says so")
	assert_true(screen.name_dialog() == null, "the dialog closes")
	_free(screen)


func test_home_button_shows_best_and_rank_and_opens_leaderboards() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	var p := _profile()
	p.save(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	# Sample boards, whatever services/supabase_config.json says on this machine.
	main.leaderboard = SampleLeaderboard.new(p)
	_tree().root.add_child(main)
	var home := main._menus.current() as HomeScreen
	assert_true(home != null, "starts on home")
	if home == null:
		main.free()
		return
	assert_eq(home.stats_line(), "Best 87", "no run today yet")
	var button := home.dock().button("rank")
	assert_eq(button.text, "Ranks", "the dock's leaderboard item")
	assert_true(button.get_combined_minimum_size().y >= UiTokens.SIZE_TAP_MIN, "big enough to tap")
	main.leaderboard.submit_run(87)
	home.leaderboard_pressed.emit()
	var screen := main._menus.current() as LeaderboardScreen
	assert_true(screen != null, "the button opens the leaderboards")
	if screen != null:
		screen.closed.emit()
	home = main._menus.current() as HomeScreen
	assert_true(home != null, "back goes home")
	if home != null:
		var want := main.leaderboard.cached_rank(LeaderboardService.DAILY) as int
		var shown := "#%d" % want if want > 0 else "Ranks"
		assert_eq(home.dock().button("rank").text, shown, "today's rank on home")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_tapping_a_score_with_a_replay_opens_the_sheet_and_hands_over_the_run() -> void:
	var p := _profile()
	var service := RunService.new(p)
	service.submit_run(87)
	var screen := _screen(p, service)
	await _tree().process_frame
	var b := service.build_board(LeaderboardService.DAILY)
	b.entries[4].run_id = 41
	screen.show_board(b)
	screen.open_replay(b.entries[5])
	assert_true(screen.replay_sheet() == null, "a run without a stored replay opens nothing")
	screen.open_replay(b.entries[4])
	assert_true(screen.replay_sheet() != null, "the sheet opens")
	var got: Array[Dictionary] = []
	screen.replay_requested.connect(func(run: Dictionary) -> void: got.append(run))
	var watch := Button.new()
	screen._watch(watch)
	watch.free()
	assert_eq(service.asked, 41, "asks the service for that run")
	await _tree().process_frame
	assert_eq(got.size(), 1, "the run is handed over for playback")
	if got.size() == 1:
		assert_eq(got[0].get("seed"), 5)
	assert_true(screen.replay_sheet() == null, "the sheet closes")
	_free(screen)
