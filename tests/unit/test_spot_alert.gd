extends TestCase
## Losing a prize spot on the daily board: the words (SpotAlert), the line on
## Home, the prizes shown on the board, and the bonus prizes in the popup.

const TEST_PATH := "user://test_spot_alert_profile.json"


func _make_main() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _in_tree(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


## A daily board of 12 players (scores 96, 91, 89, 80, 79...) with the player
## at `my_rank`.
func _board(my_rank: int) -> LeaderboardBoard:
	var b := LeaderboardBoard.make(LeaderboardService.DAILY)
	var scores := [96, 91, 89, 80, 79, 78, 70, 66, 63, 61, 55, 50]
	var names := ["Kestrel", "Pogo", "Moth", "Dune", "Ivy", "Rook"]
	for i in scores.size():
		var e := LeaderboardBoard.Entry.new(i + 1, names[i % names.size()], "buzz", scores[i])
		e.is_me = i + 1 == my_rank
		if e.is_me:
			e.player_name = "Me"
			b.me = e
		b.entries.append(e)
	b.players = scores.size()
	b.resets_in_s = 3600
	return b


func test_ordinals() -> void:
	assert_eq(SpotAlert.ordinal(1), "1st")
	assert_eq(SpotAlert.ordinal(2), "2nd")
	assert_eq(SpotAlert.ordinal(3), "3rd")
	assert_eq(SpotAlert.ordinal(4), "4th")
	assert_eq(SpotAlert.ordinal(11), "11th")
	assert_eq(SpotAlert.ordinal(12), "12th")
	assert_eq(SpotAlert.ordinal(13), "13th")
	assert_eq(SpotAlert.ordinal(22), "22nd")


func test_each_prize_line_has_its_words() -> void:
	assert_eq(
		SpotAlert.message(1, 2, _board(2).entries),
		"Kestrel took 1st with 96. You're 2nd now: 2 diamonds instead of 3."
	)
	assert_eq(
		SpotAlert.message(2, 3, _board(3).entries),
		"Pogo passed you with 91. You're 3rd now, still 2 diamonds."
	)
	assert_eq(
		SpotAlert.message(3, 4, _board(4).entries),
		"You're off the podium. 4th now: 1 diamond instead of 2."
	)
	assert_eq(
		SpotAlert.message(1, 5, _board(5).entries),
		"You're off the podium. 5th now: 1 diamond instead of 3."
	)
	assert_eq(
		SpotAlert.message(10, 11, _board(11).entries),
		"You're out of the top 10. Beat 61 to win a diamond back."
	)
	assert_eq(
		SpotAlert.message(2, 12, _board(12).entries),
		"You're out of the top 10. Beat 61 to win a diamond back."
	)


func test_no_words_without_a_lost_line() -> void:
	assert_eq(SpotAlert.message(0, 3, _board(3).entries), "", "no place before")
	assert_eq(SpotAlert.message(3, 3, _board(3).entries), "", "same place")
	assert_eq(SpotAlert.message(5, 2, _board(2).entries), "", "moved up")
	assert_eq(SpotAlert.message(4, 9, _board(9).entries), "", "inside 4th to 10th")
	assert_eq(SpotAlert.message(11, 12, _board(12).entries), "", "was already outside")
	var empty: Array[LeaderboardBoard.Entry] = []
	assert_eq(
		SpotAlert.message(1, 2, empty),
		"You lost 1st place. You're 2nd now: 2 diamonds instead of 3."
	)
	assert_eq(SpotAlert.message(9, 14, empty), "You're out of the top 10.")


func test_home_tells_a_lost_spot_once() -> void:
	var main := _make_main()
	var home := main._menus.current() as HomeScreen
	assert_eq(home.notice_text(), "", "nothing to tell at first")
	main._on_board_loaded(_board(1))
	assert_eq(main._profile.daily_spot_rank, 1, "the place is remembered")
	assert_eq(home.notice_text(), "", "first place is no loss")
	main._on_board_loaded(_board(2))
	assert_eq(
		home.notice_text(), "Kestrel took 1st with 96. You're 2nd now: 2 diamonds instead of 3."
	)
	assert_eq(Profile.load_or_new(TEST_PATH).daily_spot_rank, 2, "saved")
	main.show_home()
	assert_eq((main._menus.current() as HomeScreen).notice_text(), "", "told once")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_a_loss_during_a_run_waits_for_home() -> void:
	var main := _make_main()
	main._on_board_loaded(_board(3))
	main.start_run()
	main._on_board_loaded(_board(4))
	assert_true(main._menus.current() == null, "nothing pops up over the run")
	main.show_home()
	assert_eq(
		(main._menus.current() as HomeScreen).notice_text(),
		"You're off the podium. 4th now: 1 diamond instead of 2."
	)
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_a_new_day_and_an_offline_board_tell_nothing() -> void:
	var main := _make_main()
	main._on_board_loaded(_board(1))
	# The board that place was on has ended.
	main._profile.daily_spot_until = 1
	main._on_board_loaded(_board(8))
	assert_eq((main._menus.current() as HomeScreen).notice_text(), "", "a new day starts fresh")
	assert_eq(main._profile.daily_spot_rank, 8)
	var offline := LeaderboardBoard.make(LeaderboardService.DAILY, LeaderboardBoard.Status.OFFLINE)
	main._on_board_loaded(offline)
	assert_eq(main._profile.daily_spot_rank, 8, "offline changes nothing")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_daily_rows_show_their_prize() -> void:
	var entry := LeaderboardBoard.Entry.new(4, "Dune", "buzz", 80)
	var paid := LeaderboardRow.new(entry, Economy.daily_prize(4))
	_in_tree(paid)
	assert_eq(paid.prize, 1)
	assert_true(paid.find_child("Prize", true, false) != null, "the diamond shows")
	paid.free()
	var plain := LeaderboardRow.new(LeaderboardBoard.Entry.new(11, "Rook", "buzz", 55))
	_in_tree(plain)
	assert_true(plain.find_child("Prize", true, false) == null, "11th wins nothing")
	plain.free()


func test_your_look_shows_the_wallet_and_opens_the_shop() -> void:
	var main := _make_main()
	main._profile.diamonds = 6
	main._profile.coins = 120
	main.show_look()
	var look := main._menus.current() as LookScreen
	assert_eq([look._coins.gold_text(), look._coins.diamonds_text()], ["120", "6"])
	look._coins.pressed.emit()
	var shop := main._menus.current() as StoreScreen
	assert_true(shop != null, "the wallet opens the Shop")
	shop.closed.emit()
	assert_true(main._menus.current() is LookScreen, "back returns to Your look")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_popup_names_milestones_and_streaks() -> void:
	var milestone := {"kind": WalletService.MILESTONE, "ref": "50", "diamonds": 1}
	var streak := {"kind": WalletService.STREAK, "ref": "2026-11-09", "diamonds": 1}
	var daily := {"kind": WalletService.DAILY, "day": "2026-11-09", "rank": 3, "diamonds": 2}
	var one := DailyPrizePopup.new([milestone])
	_in_tree(one)
	assert_eq(one.rank_text(), "Best 50")
	assert_eq(DailyPrizePopup.day_line(milestone), "New best score")
	assert_eq(one.summary(), "You won 1 diamond.")
	one.free()
	assert_eq(DailyPrizePopup.headline(streak), "7 days")
	assert_eq(DailyPrizePopup.day_line(streak), "Played 7 days in a row")
	var mixed := DailyPrizePopup.new([daily, milestone, streak])
	_in_tree(mixed)
	assert_eq(mixed.rank_text(), "#3", "a daily place leads")
	assert_eq(mixed.summary(), "You won 4 diamonds from 3 prizes.")
	assert_eq(mixed.claim_text(), "Claim 4")
	mixed.free()


func test_popup_headline_fits_a_narrow_screen() -> void:
	assert_eq(DailyPrizePopup.headline_size("#2"), DailyPrizePopup.HEADLINE_SIZE, "short stays big")
	for text in ["Best 50", "Best 1000", "7 days"]:
		var size := DailyPrizePopup.headline_size(text)
		var w := GameFonts.display().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		assert_true(w <= DailyPrizePopup.HEADLINE_W, "%s fits at %d" % [text, size])
	var popup := DailyPrizePopup.new([{"kind": WalletService.MILESTONE, "ref": "1000"}])
	_in_tree(popup)
	var card := popup.get_child(1).get_child(0) as Control
	assert_true(
		card.get_combined_minimum_size().x <= UiTokens.SIZE_VIEWPORT_W - 2 * DailyPrizePopup.SIDE,
		"the card stays inside the screen"
	)
	popup.free()
