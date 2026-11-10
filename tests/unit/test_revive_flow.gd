extends TestCase
## The revive in the app: the offer after a crash, free revives per day, the
## rewarded ad when those are used, the tap that flies on, and what the boards
## get. The sim's own revive rules are in test_revive.gd.

const TEST_PATH := "user://test_revive_flow_profile.json"
const HUD_SCENE := "res://game/ui/hud.tscn"


## Keeps what was sent to the leaderboards.
class SpyBoard:
	extends SampleLeaderboard
	var runs: Array[Dictionary] = []

	func _init() -> void:
		super(Profile.new())

	func submit_run(_score: int, replay: Dictionary = {}) -> void:
		runs.append(replay)


func _make_main(board: SpyBoard, ads: AdsService = null) -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.leaderboard = board
	main.ads = ads if ads != null else FakeAds.new()
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free(main: Node) -> void:
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## Starts a run, gives it `score` points and lets the flyer fall to its death.
static func _crash(main: Node, score: int) -> void:
	main.start_run()
	main._run.request_tap()
	main._run.advance()
	# The falling flyer still bounces once: that point brings it to `score`.
	main._run.sim.state.score = score - 1
	_fall(main)


static func _fall(main: Node) -> void:
	while not main._run.sim.is_over():
		main._run.advance()


static func _tap(main: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)


func test_free_revives_count_per_day() -> void:
	var p := Profile.new()
	assert_eq(p.free_revives_left("2026-11-10"), Profile.FREE_REVIVES_PER_DAY)
	for i in Profile.FREE_REVIVES_PER_DAY:
		assert_true(p.use_free_revive("2026-11-10"))
	assert_eq(p.free_revives_left("2026-11-10"), 0)
	assert_false(p.use_free_revive("2026-11-10"), "none left today")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.free_revives_left("2026-11-10"), 0, "saved with the profile")
	assert_eq(back.free_revives_left("2026-11-11"), Profile.FREE_REVIVES_PER_DAY, "a new day")
	assert_true(back.use_free_revive("2026-11-11"))
	assert_eq(back.free_revives_left("2026-11-11"), Profile.FREE_REVIVES_PER_DAY - 1)
	assert_eq(Profile.from_dict({}).free_revives_left("2026-11-10"), Profile.FREE_REVIVES_PER_DAY)


func test_ad_units_are_test_units_in_debug_builds() -> void:
	for platform: String in ["Android", "iOS"]:
		var real := AdsService.revive_unit(platform, false)
		var test := AdsService.revive_unit(platform, true)
		assert_true(real.begins_with("ca-app-pub-6064406000465979/"), "%s: our unit" % platform)
		assert_true(test.begins_with("ca-app-pub-3940256099942544/"), "%s: Google's" % platform)
	assert_eq(AdsService.revive_unit("Windows", false), "", "no ads on desktop")
	var none := AdsService.new()
	var got: Array[int] = []
	none.rewarded_closed.connect(func(r: int) -> void: got.append(r))
	assert_false(none.is_ready(), "the base service never has an ad")
	none.show_rewarded()
	assert_eq(got, [AdsService.Result.FAILED])


func test_offer_says_what_a_revive_costs() -> void:
	var offer := ReviveOffer.new()
	offer.show_offer(47, 2)
	assert_true(offer.visible)
	assert_eq(offer.score_text(), "47")
	assert_true(offer.is_free())
	assert_eq(offer.line_text(), "2 free revives left today")
	assert_eq(offer.revive_button().text, "Revive")
	assert_eq(offer.skip_button().text, "Skip")
	offer.show_offer(47, 1)
	assert_eq(offer.line_text(), "1 free revive left today")
	offer.show_offer(63, 0)
	assert_false(offer.is_free(), "the AD tag shows before the tap")
	assert_eq(offer.line_text(), "Watch a short ad to keep going")
	assert_eq(offer.note_text(), "3 free revives are back tomorrow")
	offer.free()


func test_game_over_says_where_the_run_was_revived() -> void:
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.show_game_over(71, 87, false, 71, 87, 7, 12, 48213, 63)
	assert_true(hud._revived_line.visible)
	assert_eq(hud._revived_text.text, "Revived at 63")
	assert_true(hud._revived_line.offset_top >= hud._best_score.offset_top + 20.0, "under Best")
	assert_true(hud._revived_line.offset_bottom <= hud._stats.offset_top, "above the stats")
	hud.show_game_over(92, 92, true, 92, 87, 9, 14, 48213, 63)
	assert_true(hud._revived_line.offset_bottom <= hud._stats.offset_top, "also on a new best")
	hud.show_game_over(64, 92, false, 64, 92, 6, 14, 4000000000)
	assert_false(hud._revived_line.visible, "a run without a revive has no such line")
	hud.free()


func test_a_crash_offers_a_free_revive_and_the_run_plays_on() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	var p: Profile = main._profile
	_crash(main, 12)
	var offer: ReviveOffer = main._hud.revive_offer
	assert_true(offer.visible, "the offer shows")
	assert_true(offer.is_free())
	assert_eq(offer.score_text(), "12")
	assert_false(main._hud._game_over.visible, "not game over yet")
	assert_eq(board.runs.size(), 0, "nothing sent yet")
	assert_eq(p.runs, 0, "the run isn't counted yet")
	# A tap beside the buttons neither restarts nor revives.
	main._game_over_at_ms = -100000
	_tap(main)
	assert_true(offer.visible and main._run.sim.is_over(), "a stray tap does nothing")
	offer.revive_button().pressed.emit()
	assert_false(offer.visible)
	assert_false(main._run.sim.is_over(), "the bird is back")
	assert_eq(main._run.sim.state.score, 12, "with its score")
	assert_eq(p.free_revives_left(Profile.today()), Profile.FREE_REVIVES_PER_DAY - 1)
	assert_eq(
		Profile.load_or_new(TEST_PATH).free_revives_left(Profile.today()),
		Profile.FREE_REVIVES_PER_DAY - 1,
		"the spent revive is saved"
	)
	assert_true(main._run.paused, "it waits for a tap")
	assert_true(main._hud._hint.visible, "Tap to flap")
	assert_true("revive" in main._audio.played, "the revive sound")
	var tick: int = main._run.sim.state.tick
	main._run._physics_process(1.0 / 60.0)
	assert_eq(main._run.sim.state.tick, tick, "nothing moves until the tap")
	_tap(main)
	assert_false(main._run.paused, "the tap flies on")
	assert_false(main._hud._hint.visible)
	assert_true(main._hud._score.visible)
	# The second crash ends the run: no second offer.
	_fall(main)
	assert_false(offer.visible, "one revive per run")
	assert_true(main._hud._game_over.visible)
	assert_eq(main._hud._revived_text.text, "Revived at 12")
	assert_true(main._hud._revived_line.visible)
	assert_eq(p.runs, 1)
	assert_eq(board.runs.size(), 1, "sent once, at the end")
	var sent := Replay.from_dict(board.runs[0])
	assert_eq(sent.revive_ticks.size(), 1, "with its revive tick")
	assert_eq(sent.end_tick, main._run.sim.state.tick)
	_free(main)


func test_skip_ends_the_run_and_keeps_the_free_revive() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	_crash(main, 9)
	var offer: ReviveOffer = main._hud.revive_offer
	assert_true(offer.visible)
	offer.skip_button().pressed.emit()
	assert_false(offer.visible)
	assert_true(main._hud._game_over.visible)
	assert_false(main._hud._revived_line.visible)
	assert_eq(main._profile.free_revives_left(Profile.today()), Profile.FREE_REVIVES_PER_DAY)
	assert_eq(board.runs.size(), 1)
	assert_eq((board.runs[0].get("revives", []) as Array).size(), 0)
	# Again starts a fresh run with its own revive.
	main._game_over_at_ms = -100000
	main._try_restart()
	assert_false(main._run.sim.is_over())
	assert_eq(main._revived_at, -1)
	_free(main)


func test_low_scores_and_practice_get_no_offer() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	_crash(main, main.REVIVE_MIN_SCORE - 1)
	assert_false(main._hud.revive_offer.visible, "a quick crash goes straight to Game over")
	assert_true(main._hud._game_over.visible)
	assert_eq(board.runs.size(), 1)
	main._profile.record_room_met(RoomCatalog.all()[RoomCatalog.first_index()].id)
	main.start_practice(RoomCatalog.all()[RoomCatalog.first_index()].id)
	assert_eq(main.mode, main.Mode.PRACTICE)
	main._run.request_tap()
	main._run.advance()
	_fall(main)
	assert_false(main._hud.revive_offer.visible, "practice has no revive")
	_free(main)


func _use_up_free_revives(main: Node) -> void:
	for i in Profile.FREE_REVIVES_PER_DAY:
		main._profile.use_free_revive(Profile.today())


func test_with_no_free_revive_left_it_costs_an_ad() -> void:
	var board := SpyBoard.new()
	var ads := FakeAds.new()
	var main := _make_main(board, ads)
	_use_up_free_revives(main)
	_crash(main, 20)
	assert_true(ads.preloads > 0, "an ad is loaded when the run starts")
	var offer: ReviveOffer = main._hud.revive_offer
	assert_true(offer.visible)
	assert_false(offer.is_free(), "the offer says it is an ad")
	offer.revive_button().pressed.emit()
	assert_eq(ads.shown, 1)
	assert_false(main._run.sim.is_over(), "watched to the end: revived")
	assert_eq(main._revived_at, 20)
	_free(main)


func test_closing_the_ad_early_ends_the_run() -> void:
	var board := SpyBoard.new()
	var ads := FakeAds.new()
	ads.next_result = AdsService.Result.DISMISSED
	var main := _make_main(board, ads)
	_use_up_free_revives(main)
	_crash(main, 20)
	main._hud.revive_offer.revive_button().pressed.emit()
	assert_true(main._run.sim.is_over(), "no reward, no revive")
	assert_true(main._hud._game_over.visible)
	assert_false(main._hud._revived_line.visible)
	assert_eq(board.runs.size(), 1)
	_free(main)


func test_a_broken_ad_revives_anyway() -> void:
	var ads := FakeAds.new()
	ads.next_result = AdsService.Result.FAILED
	var main := _make_main(SpyBoard.new(), ads)
	_use_up_free_revives(main)
	_crash(main, 20)
	main._hud.revive_offer.revive_button().pressed.emit()
	assert_false(main._run.sim.is_over(), "a broken ad is never the player's problem")
	_free(main)


func test_no_ad_and_no_free_revive_means_no_offer() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board, AdsService.new())
	_use_up_free_revives(main)
	_crash(main, 20)
	assert_false(main._hud.revive_offer.visible)
	assert_true(main._hud._game_over.visible, "straight to Game over")
	_free(main)


func test_a_revived_run_replays_with_its_revive() -> void:
	var recorded := SimBots.play_revived(5160, SimBots.gap_seeker, 4, 900, 900)
	assert_eq(recorded.revive_ticks.size(), 1)
	# As get_run answers, through JSON.
	var answer: Variant = (
		JSON
		. parse_string(
			(
				JSON
				. stringify(
					{
						"run": 9,
						"name": "Noor",
						"score": recorded.score,
						"gameplay_version": recorded.gameplay_version,
						"seed": recorded.seed_value,
						"taps": Array(recorded.taps),
						"revives": Array(recorded.revive_ticks),
						"loadout": {},
					}
				)
			)
		)
	)
	var run := SupabaseLeaderboard.parse_run(answer)
	assert_eq(run.revives, [recorded.revive_ticks[0]], "the revive tick is read as an int")
	var rc := RunController.new()
	var events: Array[String] = []
	rc.died.connect(func(_r: Replay) -> void: events.append("died"))
	rc.revived.connect(func() -> void: events.append("revived"))
	rc.new_replay(ReplayDriver.from_run(run))
	while not rc.sim.is_over() and rc.sim.state.tick < SimConfig.MAX_TICKS:
		rc.advance()
	assert_eq(events, ["revived", "died"], "it plays through the revive and ends once")
	assert_eq(rc.sim.state.score, recorded.score)
	assert_eq(rc.sim.state.tick, recorded.end_tick)
	assert_eq(rc.sim.checksum(), recorded.checksum, "the same final state")
	assert_false(rc.revive(), "a replay can't be revived by the watcher")
	rc.free()


func test_recorded_revives_verify() -> void:
	var rc := RunController.new()
	rc.new_run(77)
	rc.request_tap()
	rc.advance()
	while not rc.sim.is_over():
		rc.advance()
	assert_true(rc.can_revive())
	assert_true(rc.revive())
	assert_false(rc.revive(), "not while alive")
	while not rc.sim.is_over():
		rc.advance()
	assert_false(rc.can_revive(), "once per run")
	var replay := rc.replay()
	assert_eq(replay.revive_ticks.size(), 1)
	var result := replay.verify()
	assert_true(result.ok, result.reason)
	rc.free()


func test_only_revived_runs_send_revives() -> void:
	var p := Profile.new()
	var plain := SupabaseLeaderboard.run_body(p, 5, {"seed": 1, "taps": [], "revives": []}, 0)
	assert_false(plain.has("p_revives"), "older databases still take a plain run")
	var revived := SupabaseLeaderboard.run_body(p, 5, {"seed": 1, "taps": [], "revives": [80]}, 0)
	assert_eq(revived.p_revives, [80])


func test_boards_mark_revived_runs() -> void:
	var answer := {
		"entries":
		[
			{"rank": 1, "name": "Mossy", "flyer": "pip", "score": 74, "revived": true},
			{"rank": 2, "name": "Pip", "flyer": "pip", "score": 68},
		],
	}
	var b := SupabaseLeaderboard.parse_board(LeaderboardService.DAILY, answer)
	assert_true(b.entries[0].revived)
	assert_false(b.entries[1].revived, "missing reads as not revived")
	var marked := LeaderboardRow.new(b.entries[0])
	var plain := LeaderboardRow.new(b.entries[1])
	assert_true(marked.find_child("Revived", true, false) != null, "the small heart")
	assert_true(plain.find_child("Revived", true, false) == null)
	var podium := Podium.new(b.entries)
	var hearts := podium.find_children("Revived", "", true, false)
	assert_eq(hearts.size(), 1, "the podium marks it too")
	marked.free()
	plain.free()
	podium.free()


func test_desktop_never_loads_the_admob_plugin() -> void:
	var main := _make_main(SpyBoard.new())
	var made: AdsService = main._make_ads()
	assert_true(made is FakeAds or made.get_script() == AdsService, "a stand-in or no ads")
	assert_false(Engine.has_singleton(main.ADMOB_SINGLETON), "no native plugin on a PC")
	assert_true(ResourceLoader.exists(main.ADMOB_ADS), "the AdMob provider is there for phones")
	assert_true(AdsService.current == main.ads, "screens find the service")
	_free(main)
	assert_true(AdsService.current == null, "and it is let go with the game")


func test_the_game_is_silent_under_an_ad_and_sounds_again_after() -> void:
	var ads := SilenceSpy.new()
	var main := _make_main(SpyBoard.new(), ads)
	_use_up_free_revives(main)
	_crash(main, 20)
	main._hud.revive_offer.revive_button().pressed.emit()
	assert_true(ads.muted_while_shown, "muted while the ad shows")
	assert_false(AudioServer.is_bus_mute(0), "sound is back when it closes")
	_free(main)


## Notes whether the game was muted at the moment the ad showed.
class SilenceSpy:
	extends FakeAds
	var muted_while_shown := false

	func show_rewarded() -> void:
		muted_while_shown = AudioServer.is_bus_mute(0)
		super()


func test_settings_show_ad_choices_only_where_they_are_needed() -> void:
	var ads := FakeAds.new()
	AdsService.current = ads
	var plain := SettingsSheet.new(Profile.new())
	assert_true(plain.find_child("AdChoices", true, false) == null, "no row without a choice")
	plain.free()
	ads.privacy_required = true
	var sheet := SettingsSheet.new(Profile.new())
	var row := sheet.find_child("AdChoices", true, false) as Button
	assert_true(row != null, "Ad choices shows where the player has a choice")
	row.pressed.emit()
	assert_eq(ads.privacy_shown, 1, "it opens the privacy form")
	sheet.free()
	AdsService.current = null
