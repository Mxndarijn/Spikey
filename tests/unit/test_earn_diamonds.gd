extends ScreenFitCase
## Earn diamonds: the rules (EarnRules, the daily tiers), the status the
## server sends (EarnStatus), the offline fallback, the screen's cards in each
## state and the ways in (the wallet, the prize popup's link).

const TEST_PATH := "user://test_earn_diamonds_profile.json"


## A server that never answers.
class DeadClient:
	extends SupabaseClient

	func _init() -> void:
		super(null, "", "")

	func call_db(_function: String, _body: Dictionary) -> Dictionary:
		return {"ok": false, "code": 0, "data": null}


## A server that answers get_earn_status with `answer`.
class FixedClient:
	extends SupabaseClient
	var answer: Variant = null

	func _init(p_answer: Variant) -> void:
		super(null, "", "")
		answer = p_answer

	func call_db(function: String, _body: Dictionary) -> Dictionary:
		if function == "get_earn_status" and answer != null:
			return {"ok": true, "code": 200, "data": answer}
		return {"ok": false, "code": 0, "data": null}


func _status(
	best: int, milestones: Array, streak: int, today: bool = true, won: int = 0
) -> EarnStatus:
	return (
		EarnStatus
		. parse(
			{
				"best": best,
				"milestones": milestones,
				"streak": streak,
				"played_today": today,
				"streak_won": won,
			}
		)
	)


## A Daily board with the player at `rank` (0: no run today) and someone on
## the 10th place with `tenth` (-1: fewer than ten players).
func _board(rank: int, tenth: int = -1) -> LeaderboardBoard:
	var b := LeaderboardBoard.make(LeaderboardService.DAILY)
	b.resets_in_s = 9 * 3600 + 12 * 60
	if tenth >= 0:
		b.entries.append(LeaderboardBoard.Entry.new(10, "tenth", "buzz", tenth))
	if rank > 0:
		b.me = LeaderboardBoard.Entry.new(rank, "me", "buzz", 50)
		b.me.is_me = true
		b.entries.append(b.me)
	b.players = maxi(rank, 10)
	return b


func _screen(p: Profile) -> EarnScreen:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var screen := EarnScreen.new(p)
	holder.add_child(screen)
	return screen


func _free(screen: EarnScreen) -> void:
	screen.get_parent().free()


func test_rules_match_the_server() -> void:
	# supabase/migrations/20261110100000_diamonds.sql: (25, 1), (50, 1), (75, 2), (100, 3).
	assert_eq(EarnRules.milestone_scores(), [25, 50, 75, 100])
	var prizes: Array[int] = []
	for score in EarnRules.milestone_scores():
		prizes.append(EarnRules.milestone_prize(score))
	assert_eq(prizes, [1, 1, 2, 3])
	assert_eq(EarnRules.milestone_prize(60), 0, "60 is not a milestone")
	assert_eq([EarnRules.STREAK_DAYS, EarnRules.STREAK_PRIZE], [7, 1])


func test_milestones_in_order() -> void:
	var none: Array[int] = []
	assert_eq(EarnRules.next_milestone(none), 25, "a new player aims for 25")
	var some: Array[int] = [25, 50, 75]
	assert_eq(EarnRules.next_milestone(some), 100)
	var all: Array[int] = [25, 50, 75, 100]
	assert_eq(EarnRules.next_milestone(all), 0, "nothing left")
	assert_eq(EarnRules.reached(0), [])
	assert_eq(EarnRules.reached(74), [25, 50])
	assert_eq(EarnRules.reached(250), [25, 50, 75, 100])
	assert_eq(EarnRules.progress(0), 0.0)
	assert_eq(EarnRules.progress(87), 0.87)
	assert_eq(EarnRules.progress(500), 1.0, "the bar stops full")


func test_streak_counting() -> void:
	# [days in a row, dots this week, days to the next diamond, diamonds won]
	for row: Array in [
		[0, 0, 7, 0],
		[1, 1, 6, 0],
		[4, 4, 3, 0],
		[6, 6, 1, 0],
		[7, 7, 7, 1],
		[8, 1, 6, 1],
		[14, 7, 7, 2],
		[15, 1, 6, 2],
	]:
		var days: int = row[0]
		assert_eq(EarnRules.week_days(days), row[1], "%d days: dots" % days)
		assert_eq(EarnRules.days_to_prize(days), row[2], "%d days: to go" % days)
		assert_eq(EarnRules.streak_prizes(days), row[3], "%d days: won" % days)


func test_daily_prize_tiers() -> void:
	assert_eq(EarnScreen.tier_index(null), 0, "no board: the top tier is lit")
	assert_eq(EarnScreen.tier_index(_board(0)), 0, "no run today")
	for row: Array in [[1, 0], [2, 1], [3, 1], [4, 2], [10, 2], [11, 0], [500, 0]]:
		assert_eq(EarnScreen.tier_index(_board(row[0])), row[1], "#%d" % row[0])
	assert_eq(EarnScreen.daily_line(_board(1)), "You're #1 today. Stay on top to win 3.")
	assert_eq(EarnScreen.daily_line(_board(3)), "You're #3 today. Stay in the top 3 to win 2.")
	assert_eq(EarnScreen.daily_line(_board(10)), "You're #10 today. Stay in the top 10 to win 1.")
	assert_eq(
		EarnScreen.daily_line(_board(1203, 63)), "You're #1,203 today. Beat 63 to reach the top 10."
	)
	assert_eq(
		EarnScreen.daily_line(_board(0)),
		"Play a run to get on today's board. The top 10 win when the day ends."
	)
	assert_eq(EarnScreen.reset_text(_board(4)), "Resets in 9h 12m")


func test_status_from_the_server() -> void:
	var s := (
		EarnStatus
		. parse(
			{
				"best": 87,
				"milestones": [50, 25, 75, 75, 60, "x"],
				"streak": 4,
				"played_today": true,
				"streak_won": 0,
			}
		)
	)
	assert_true(s.known, "fresh from the server")
	assert_eq(s.best, 87)
	assert_eq(s.milestones, [25, 50, 75], "sorted, once each, only real milestones")
	assert_eq([s.streak, s.played_today, s.streak_won], [4, true, 0])
	var broken := _status(10, [], 0, true)
	assert_false(broken.played_today, "no streak means no run today counts")
	assert_eq(EarnStatus.parse(null), null)
	assert_eq(EarnStatus.parse({"diamonds": 3}), null, "not a status")
	var p := Profile.new()
	p.best_score = 60
	var guess := EarnStatus.from_profile(p)
	assert_false(guess.known, "a guess from the save")
	assert_eq(guess.milestones, [25, 50])
	assert_eq(guess.streak, -1, "the streak is unknown")


func test_offline_falls_back_to_the_last_answer() -> void:
	var p := Profile.new()
	p.best_score = 30
	var local := WalletService.new(p)
	var own := await local.earn_status()
	assert_false(own.known, "the local wallet only guesses")
	assert_eq(own.best, 30)
	var dead := SupabaseWallet.new(p, DeadClient.new())
	var first := await dead.earn_status()
	assert_false(first.known, "no answer: a guess")
	assert_eq([first.best, first.streak], [30, -1])
	var answer := {"best": 87, "milestones": [25, 50, 75], "streak": 4, "played_today": true}
	var live := SupabaseWallet.new(p, FixedClient.new(answer))
	var fresh := await live.earn_status()
	assert_true(fresh.known)
	assert_eq(fresh.best, 87)
	(live._api as FixedClient).answer = null
	var again := await live.earn_status()
	assert_false(again.known, "offline now")
	assert_eq([again.best, again.streak, again.milestones], [87, 4, [25, 50, 75]], "last answer")


func test_new_player_cards() -> void:
	var p := Profile.new()
	var screen := _screen(p)
	screen.show_status(_status(0, [], 0, false))
	screen.show_board(_board(0))
	assert_eq(screen.balance_text(), "0")
	assert_false(screen.banner_visible(), "online")
	assert_eq(screen.milestone_labels(), ["+1", "+1", "+2", "+3"])
	assert_eq(screen.best_text(), "Score 25 in one run for your first diamond.")
	assert_eq(screen.bar_ratio(), 0.0)
	assert_eq(screen.streak_dots_filled(), 0)
	assert_eq(screen.streak_text(), "Play one run a day. 7 days in a row win 1 diamond.")
	assert_eq(screen.lit_tier(), 0)
	assert_true(screen.daily_text().begins_with("Play a run"), screen.daily_text())
	_free(screen)


func test_mid_progress_cards() -> void:
	var p := Profile.new()
	p.diamonds = 3
	var screen := _screen(p)
	screen.show_status(_status(87, [25, 50, 75], 4))
	screen.show_board(_board(14, 63))
	assert_eq(screen.balance_text(), "3")
	assert_eq(screen.milestone_labels(), ["Won", "Won", "Won", "+3"])
	assert_eq(screen.best_text(), "Best 87. 13 more for 3 diamonds.")
	assert_eq(screen.bar_ratio(), 0.87)
	assert_eq(screen.streak_dots_filled(), 4)
	assert_eq(screen.streak_text(), "4 days in a row. 3 more days for 1 diamond.")
	assert_eq(screen.daily_text(), "You're #14 today. Beat 63 to reach the top 10.")
	assert_eq(screen.reset_label(), "Resets in 9h 12m")
	screen.show_status(_status(87, [25, 50, 75], 6, false))
	assert_eq(
		screen.streak_text(), "6 days in a row. 1 more day for 1 diamond. Play today to keep it."
	)
	_free(screen)


func test_everything_earned_cards() -> void:
	var p := Profile.new()
	p.diamonds = 12
	var screen := _screen(p)
	screen.show_status(_status(112, [25, 50, 75, 100], 15, true, 2))
	screen.show_board(_board(2))
	assert_eq(screen.milestone_labels(), ["Won", "Won", "Won", "Won"])
	assert_eq(screen.best_text(), "All four won. Your best is 112.")
	assert_eq(screen.bar_ratio(), 1.0)
	assert_eq(screen.streak_dots_filled(), 1, "day 15 is the first of the third week")
	assert_eq(screen.streak_text(), "15 days in a row, 2 diamonds won. Next one in 6 days.")
	assert_eq(screen.lit_tier(), 1, "#2 lights the #2 and #3 tier")
	assert_eq(screen.daily_text(), "You're #2 today. Stay in the top 3 to win 2.")
	_free(screen)


func test_offline_cards() -> void:
	var p := Profile.new()
	p.best_score = 87
	var screen := _screen(p)
	assert_false(screen.banner_visible(), "no banner while the status is on its way")
	screen.show_status(EarnStatus.from_profile(p))
	screen.show_board(
		LeaderboardBoard.make(LeaderboardService.DAILY, LeaderboardBoard.Status.OFFLINE)
	)
	assert_true(screen.banner_visible(), "offline banner")
	assert_eq(screen.milestone_labels(), ["Won", "Won", "Won", "+3"], "from the save's best")
	assert_eq(screen.streak_text(), "Your streak shows when you're back online.")
	assert_eq(screen.streak_dots_filled(), 0)
	assert_eq(screen.daily_text(), "Your place today shows when you're back online.")
	assert_eq(screen.reset_label(), "Resets at midnight")
	screen.show_board(_board(5))
	assert_eq(screen.lit_tier(), 2)
	var leaders := LeaderboardBoard.make(LeaderboardService.ALL_TIME)
	screen.show_board(leaders)
	assert_eq(screen.lit_tier(), 2, "other boards are ignored")
	_free(screen)


func test_screen_fits_in_every_state() -> void:
	var p := _profile()
	p.diamonds = 999
	for row: Array in [
		[_status(0, [], 0, false), _board(0)],
		[_status(87, [25, 50, 75], 6, false), _board(12345, 99999)],
		[_status(112, [25, 50, 75, 100], 15, true, 2), _board(2)],
		[
			EarnStatus.from_profile(p),
			LeaderboardBoard.make(LeaderboardService.DAILY, LeaderboardBoard.Status.OFFLINE)
		],
	]:
		var screen := EarnScreen.new(p)
		var status: EarnStatus = row[0]
		var board: LeaderboardBoard = row[1]
		_fits(
			screen,
			"earn diamonds (best %d)" % status.best,
			func() -> void:
				screen.show_status(status)
				screen.show_board(board)
		)


func test_prize_popup_links_to_earn_diamonds() -> void:
	var popup := DailyPrizePopup.new(
		[{"kind": WalletService.MILESTONE, "ref": "50", "diamonds": 1}]
	)
	var got := []
	popup.earn_pressed.connect(func() -> void: got.append("earn"))
	assert_eq(popup.earn_button().text, DailyPrizePopup.EARN_LINK)
	assert_true(popup.earn_button().custom_minimum_size.y >= UiTokens.SIZE_TAP_MIN, "44 px tall")
	assert_eq(popup.note_text(), "", "no note until a claim fails")
	popup.earn_button().pressed.emit()
	assert_eq(got, ["earn"])
	popup.show_failed()
	assert_eq(popup.note_text(), DailyPrizePopup.FAILED)
	popup.free()


func test_ways_in_from_main() -> void:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.board_config_path = ""
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var home := main._menus.current() as HomeScreen
	main._on_wallet_synced(0, [{"kind": WalletService.MILESTONE, "ref": "25", "diamonds": 1}])
	var popup := home.prize_popup()
	assert_true(popup != null, "the prize popup is up")
	popup.earn_button().pressed.emit()
	var earn := main._menus.current() as EarnScreen
	assert_true(earn != null, "its link opens Earn diamonds")
	earn.closed.emit()
	assert_true(main._menus.current() is HomeScreen, "back goes Home")
	main.show_look()
	var look := main._menus.current() as LookScreen
	look.earn_pressed.emit()
	var store := main._menus.current() as StoreScreen
	assert_true(store != null, "the wallet on Your look opens the Wallet")
	store.earn_tab().pressed.emit()
	earn = main._menus.current() as EarnScreen
	assert_true(earn != null, "its Earn free tab opens it too")
	earn.closed.emit()
	assert_true(main._menus.current() is LookScreen, "and back returns to Your look")
	main.free()
	SafeFile.remove(TEST_PATH)
