extends TestCase
## Daily Run: the rules, the server's answers, the migration the game's calls
## have to agree with, the screens, and a whole try in the app (the day's seed,
## no revive, its Game over, the next try, Share).

const TEST_PATH := "user://test_daily_run_profile.json"
const MIGRATION := "res://supabase/migrations/20261113130000_daily_run.sql"


## The sample boards, keeping what was sent.
class SpyBoard:
	extends SampleLeaderboard
	var runs: Array[Dictionary] = []
	var tries: Array[Dictionary] = []

	func _init() -> void:
		super(Profile.new())

	func submit_run(_score: int, replay: Dictionary = {}) -> void:
		runs.append(replay)

	func submit_daily_run(daily_try: DailyTry, score: int, replay: Dictionary = {}) -> void:
		super(daily_try, score, replay)
		tries.append({"try": daily_try.id, "score": score, "replay": replay})


func _make_main(board: SpyBoard) -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.leaderboard = board
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	_tree().root.add_child(main)
	return main


func _free(main: Node) -> void:
	main.free()
	SafeFile.remove(TEST_PATH)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frames(n: int = 2) -> void:
	for i in n:
		await _tree().process_frame


## Starts the run in play, gives it `score` points and lets the flyer fall.
static func _crash(main: Node, score: int) -> void:
	main._run.request_tap()
	main._run.advance()
	main._run.sim.state.score = score - 1
	while not main._run.sim.is_over():
		main._run.advance()


func test_tries_and_labels() -> void:
	assert_eq(DailyRunRules.TRIES_PER_DAY, 3)
	assert_eq(DailyRunRules.tries_left(0), 3)
	assert_eq(DailyRunRules.tries_left(5), 0, "never below zero")
	assert_eq(DailyRunRules.next_try_label(1), "Try 2")
	assert_eq(DailyRunRules.next_try_label(3), "", "none after the last")
	assert_eq(DailyRunRules.tries_text(1), "2 tries left")
	assert_eq(DailyRunRules.tries_text(2), "1 try left")
	assert_eq(DailyRunRules.tries_text(3), "No tries left")


func test_share_text_has_no_spoilers() -> void:
	var text := DailyRunRules.share_text(47, 31, 12, 2140, 2, 3, 3)
	assert_eq(text, "Flapjaw Daily Run No. 47 · 31 points · #12 of 2,140 · try 2 of 3\n🟩🟩🟩🟥")
	assert_eq(
		DailyRunRules.share_text(1, 4, 0, 0, 1, 3, 0),
		"Flapjaw Daily Run No. 1 · 4 points · try 1 of 3\n🟥"
	)
	assert_true(DailyRunRules.squares(40).ends_with("🟥 +29"), "a long run ends with +N")
	assert_eq(DailyRunRules.thousands(1234567), "1,234,567")


func test_prizes_match_today() -> void:
	var total := 0
	for rank in range(1, 13):
		assert_eq(Economy.daily_run_prize(rank), Economy.daily_prize(rank), "place %d" % rank)
		total += Economy.daily_run_prize(rank)
	assert_eq(total, 14, "14 more diamonds a day")
	assert_eq(LeaderboardService.prize(LeaderboardService.DAILY_RUN, 1), 3)
	assert_eq(LeaderboardService.prize(LeaderboardService.ALL_TIME, 1), 0)
	assert_true(LeaderboardService.pays(LeaderboardService.DAILY_RUN))
	assert_false(LeaderboardService.pays(LeaderboardService.ALL_TIME))


func test_boards_have_distinct_names() -> void:
	assert_eq(
		LeaderboardService.BOARDS,
		[LeaderboardService.DAILY, LeaderboardService.DAILY_RUN, LeaderboardService.ALL_TIME]
	)
	assert_eq(LeaderboardService.TITLES[LeaderboardService.DAILY], "Today")
	assert_eq(LeaderboardService.TITLES[LeaderboardService.DAILY_RUN], "Daily Run")


func test_parses_the_days_answer() -> void:
	var info := (
		DailyRunInfo
		. parse(
			{
				"day": "2026-11-20",
				"number": 7,
				"season": -1,
				"resets_in_s": 3600,
				"tries_max": 3,
				"tries_used": 1,
				"best": 31,
				"rank": 12,
				"players": 2140,
				"yesterday":
				{
					"day": "2026-11-19",
					"number": 6,
					"players": 1980,
					"settled": true,
					"me": {"rank": 4, "score": 44},
					"top": [{"rank": 1, "name": "Noor", "flyer": "pip", "score": 61, "run": 9}],
				},
			}
		)
	)
	assert_true(info.is_online())
	assert_eq(info.number, 7)
	assert_eq(info.tries_left(), 2)
	assert_eq(info.best, 31)
	assert_eq(info.yesterday.rank, 4)
	assert_eq(info.yesterday.top[0].run_id, 9)
	var fresh := DailyRunInfo.parse({"number": 1, "best": null, "rank": null, "yesterday": null})
	assert_eq(fresh.best, -1, "no best before the first try")
	assert_eq(fresh.yesterday, null)
	assert_false(DailyRunInfo.parse(null).is_online(), "anything else is offline")


func test_parses_a_try() -> void:
	var t := DailyTry.parse(
		{"try": "abc", "n": 2, "tries_max": 3, "seed": 4294967295, "season": 0, "number": 7}
	)
	assert_true(t.ok())
	assert_eq(t.seed_value, 4294967295, "a 32-bit seed stays whole")
	assert_eq(t.season, Seasons.HALLOWEEN)
	assert_false(DailyTry.parse({"n": 1}).ok(), "no seed, no try")


func test_wallet_reads_daily_run_prizes() -> void:
	var w := (
		SupabaseWallet
		. parse_wallet(
			{
				"diamonds": 5,
				"prizes":
				[
					{"day": "2026-11-19", "rank": 2, "score": 80, "diamonds": 2, "board": "daily"},
					{
						"day": "2026-11-19",
						"rank": 1,
						"score": 61,
						"diamonds": 3,
						"board": "daily_run",
						"number": 6
					},
				],
			}
		)
	)
	assert_eq(w.prizes[0].kind, WalletService.DAILY)
	assert_eq(w.prizes[1].kind, WalletService.DAILY_RUN)
	assert_eq(w.prizes[1].number, 6)
	assert_eq(DailyPrizePopup.day_line(w.prizes[1]), "Daily Run No. 6, 19 November")
	assert_true(DailyPrizePopup.is_daily(w.prizes[1]), "a place on a board")


## The game calls three new functions; the migration has to offer them to
## players, keep its own helpers shut, and agree on tries, prizes and the clock.
func test_migration_matches_the_game() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	var submit := (
		"submit_daily_run(\n  uuid, text, text, integer, integer, bigint, jsonb, jsonb, integer,"
		+ " integer, integer\n)"
	)
	for fn in ["get_daily_run()", "start_daily_try(text, text)", submit]:
		assert_true(sql.contains("grant execute on function public.%s to authenticated" % fn), fn)
		assert_true(sql.contains("revoke all on function public.%s from public, anon;" % fn), fn)
	for fn in ["spikey_daily_run_of(date)", "spikey_settle_daily_runs()", "spikey_board_zone()"]:
		assert_true(
			sql.contains("revoke all on function public.%s from public, anon, authenticated" % fn),
			"%s is not callable by the game" % fn
		)
	# Every argument the game sends is one the function takes.
	var body := SupabaseLeaderboard.daily_body(Profile.new(), DailyTry.new(), 5, {})
	var head := sql.substr(sql.find("function public.submit_daily_run("), 500)
	for key: String in body:
		if key != SupabaseLeaderboard.RPC_KEY:
			assert_true(head.contains(key + " "), "submit_daily_run takes %s" % key)
	assert_true(sql.contains("select %d\n$$" % DailyRunRules.TRIES_PER_DAY), "the same tries")
	assert_true(sql.contains("select public.spikey_daily_prize(p_rank)"), "the same tiers as Today")
	assert_true(
		sql.contains("select date '%s'" % SampleLeaderboard.DAILY_RUN_EPOCH), "the same No. 1"
	)
	assert_true(sql.contains("select 'Europe/Amsterdam'"), "one clock for both boards")
	for t in ["daily_runs", "daily_tries", "daily_run_prizes", "daily_run_settled"]:
		assert_true(sql.contains("alter table public.%s enable row level security" % t), t)


func test_migration_runs_after_the_reset() -> void:
	var names := DirAccess.get_files_at("res://supabase/migrations")
	var sorted := Array(names)
	sorted.sort()
	assert_true(
		sorted.find(MIGRATION.get_file()) > sorted.find("20261113120000_reset_boards.sql"),
		"the v23 reset never wipes Daily Run's tables"
	)


func test_sample_tries_run_out() -> void:
	var board := SampleLeaderboard.new(Profile.new())
	var got: Array[DailyTry] = []
	board.daily_try_started.connect(func(t: DailyTry) -> void: got.append(t))
	for i in DailyRunRules.TRIES_PER_DAY + 1:
		board.start_daily_try()
	await _frames()
	assert_eq(got.size(), 4)
	assert_true(got[0].ok() and got[2].ok(), "three tries")
	assert_eq(got[0].seed_value, got[2].seed_value, "one map all day")
	assert_eq(got[3].problem, DailyTry.Problem.NO_TRIES, "then none")
	board.submit_daily_run(got[0], 41)
	var info := board.daily_info()
	assert_eq(info.tries_used, 3)
	assert_eq(info.best, 41)
	var b := board.build_board(LeaderboardService.DAILY_RUN)
	assert_eq(b.me.score, 41, "the try is on the Daily Run board")
	for e in b.entries:
		assert_eq(e.locked, not e.is_me, "only my replay is open today")


func test_home_pill_says_tries_and_reset() -> void:
	assert_eq(HomeScreen.daily_pill_text(null), "Daily Run")
	var info := DailyRunInfo.new()
	info.tries_used = 1
	info.resets_in_s = 4 * 3600 + 12 * 60
	assert_eq(HomeScreen.daily_pill_text(info), "Daily Run · 2 tries left · 4h 12m")
	info.tries_used = 3
	info.rank = 12
	assert_eq(HomeScreen.daily_pill_text(info), "Daily Run · #12 · 4h 12m")
	assert_eq(HomeScreen.daily_pill_text(DailyRunInfo.offline()), "Daily Run")


func test_screen_shows_each_state() -> void:
	var screen := DailyRunScreen.new(null)
	_tree().root.add_child(screen)
	assert_false(screen.primary().visible, "loading: no main action yet")
	screen.show_info(DailyRunInfo.offline())
	assert_eq(screen.primary().text, "Retry")
	assert_eq(screen.caption(), DailyRunScreen.OFFLINE)
	var info := DailyRunInfo.new()
	info.number = 7
	info.resets_in_s = 15129
	info.tries_used = 1
	info.best = 31
	info.rank = 12
	info.players = 2140
	var past := DailyRunInfo.Yesterday.new()
	past.number = 6
	past.players = 1980
	past.rank = 4
	var winner := LeaderboardBoard.Entry.new(1, "Noor", "pip", 61)
	winner.run_id = 9
	past.top.append(winner)
	info.yesterday = past
	screen.show_info(info)
	assert_eq(screen.primary().text, "Try 2")
	assert_eq(screen.caption(), "No. 7 · one map for everyone")
	assert_eq(screen.best_line(), "Best 31 · #12 of 2,140")
	assert_eq(screen.pips().get_child_count(), 3, "a disc per try")
	assert_eq(screen.yesterday_line(), "Yesterday, No. 6: you were #4 of 1,980.")
	assert_eq(screen.watch_button().text, "Watch Noor's run")
	assert_eq(DailyRunScreen.clock_text(15129), "4:12:09")
	info.tries_used = 3
	screen.show_info(info)
	assert_eq(screen.primary().text, "Board", "after the last try")
	screen.free()


## A whole try: the day's seed, no revive offer, the try's Game over, the next
## try from Again, the board it lands on and Share.
func test_a_try_in_the_app() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	await _frames()
	var home := main._menus.current() as HomeScreen
	assert_true(home.daily_pill().text.begins_with("Daily Run · 3 tries left"), "Home's pill")
	home.daily_pill().pressed.emit()
	var screen := main._menus.current() as DailyRunScreen
	assert_true(screen != null, "the pill opens the Daily Run")
	await _frames()
	assert_eq(screen.primary().text, "Try 1")
	screen.primary().pressed.emit()
	await _frames()
	var daily_try: DailyTry = main._daily.playing
	assert_true(daily_try != null and daily_try.n == 1, "the first try started")
	assert_eq(main._run.sim.seed_value, daily_try.seed_value, "it plays the day's seed")
	_crash(main, 12)
	assert_false(main._hud.revive_offer.visible, "no revive in a Daily Run")
	assert_eq(board.runs.size(), 0, "nothing goes to Today")
	assert_eq(board.tries.size(), 1, "the try is sent")
	var over: GameOverScreen = main._hud.game_over
	assert_true(over.visible and over.is_daily(), "the try's Game over")
	assert_eq(over.caption_text(), "Daily Run")
	var line := "No. %d · 2 tries left" % daily_try.number
	assert_true(over.seed_line().begins_with(line), over.seed_line())
	assert_eq(over.dock().primary().text, "Try 2")
	await _frames()
	assert_eq(over._stat_rank.text, "#%d" % board.build_board(LeaderboardService.DAILY_RUN).me.rank)
	var text: String = main._daily.share()
	assert_true(text.begins_with("Flapjaw Daily Run No."), "Share copies the result")
	assert_eq(main._daily.board_id(), LeaderboardService.DAILY_RUN, "Ranks opens the Daily Run")
	# A tap on the room never spends a try.
	main._game_over_at_ms = -100000
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)
	await _frames()
	assert_eq(main._daily.playing.n, 1, "a stray tap is not a try")
	over.dock().primary().pressed.emit()
	await _frames()
	assert_eq(main._daily.playing.n, 2, "Try 2 starts the next try")
	assert_eq(main._run.sim.seed_value, daily_try.seed_value, "on the same map")
	# Play from Home is an endless run again.
	main.show_home()
	main.start_run()
	assert_eq(main._daily.playing, null)
	_crash(main, 3)
	assert_eq(board.runs.size(), 1, "an endless run goes to Today")
	_free(main)


func test_yesterdays_result_shows_once() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	await _frames()
	var info := DailyRunInfo.new()
	info.number = 7
	var past := DailyRunInfo.Yesterday.new()
	past.day = "2026-11-19"
	past.number = 6
	past.players = 1980
	past.rank = 23
	past.score = 30
	past.settled = true
	info.yesterday = past
	main._daily._on_loaded(info)
	var home := main._menus.current() as HomeScreen
	assert_true(home.daily_result() != null, "yesterday's result pops up")
	assert_eq(home.daily_result().rank_text(), "#23")
	assert_eq(home.daily_result().podium().get_child_count(), 3, "yesterday's podium")
	var card_w := ScreenLayout.ROOM.x - 2 * (DailyResultPopup.SIDE + 20)
	assert_true(home.daily_result().podium().get_combined_minimum_size().x <= card_w, "it fits")
	home.close_daily_result()
	main._daily._on_loaded(info)
	assert_eq(home.daily_result(), null, "once")
	past.day = "2026-11-20"
	past.rank = 4
	main._daily._on_loaded(info)
	assert_eq(home.daily_result(), null, "a prize place is told by the prize popup")
	_free(main)
