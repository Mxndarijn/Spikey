extends ScreenFitCase
## The score ladder past the first four milestones: 3 diamonds for each 50 from
## 150 to 1000, once, above the player's ladder mark (EarnRules). Its window on
## Earn free, the Game over pill and the prize popup's step chips.


func _status(best: int, milestones: Array, mark: int = 0) -> EarnStatus:
	return EarnStatus.parse(
		{"best": best, "milestones": milestones, "ladder_mark": mark, "streak": 2}
	)


func _upto(best: int) -> Array[int]:
	return EarnRules.reached(best)


func _screen(p: Profile) -> EarnScreen:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var screen := EarnScreen.new(p)
	holder.add_child(screen)
	return screen


func test_ladder_matches_the_server() -> void:
	# backend/migrations/20261114120000_score_ladder.sql: 150 to 1000 by 50, 3 each.
	var steps := EarnRules.ladder_scores()
	assert_eq(steps.size(), 18)
	assert_eq([steps[0], steps[1], steps[-1]], [150, 200, 1000])
	for score in steps:
		assert_eq(EarnRules.milestone_prize(score), 3, "%d pays 3" % score)
	for score in [125, 175, 1050, 2000]:
		assert_eq(EarnRules.milestone_prize(score), 0, "%d is no step" % score)
	assert_eq(EarnRules.prizes_total(EarnRules.ladder_scores()), 54, "54 at most")
	assert_eq(EarnRules.prizes_total(EarnRules.milestone_scores()), 61, "with the first four")


func test_mark_stops_back_pay() -> void:
	var four: Array[int] = [25, 50, 75, 100]
	assert_eq(EarnRules.next_milestone(four, 420), 450, "steps up to an old best never pay")
	assert_eq(EarnRules.reached(470, 420), [25, 50, 75, 100, 450])
	assert_false(EarnRules.payable(400, 420))
	assert_false(EarnRules.payable(420, 420) or EarnRules.payable(425, 420), "420 is no step")
	assert_true(EarnRules.payable(450, 420))
	assert_true(EarnRules.payable(25, 999), "the first four always pay")
	assert_eq(EarnRules.next_milestone(four, 1000), 0, "a mark of 1000 leaves nothing")
	assert_eq(EarnRules.progress(430, four, 420), 0.6, "from 400 to 450")


func test_new_prizes_of_a_run() -> void:
	var none: Array[int] = []
	assert_eq(EarnRules.new_prizes(141, 163), [150], "one step")
	assert_eq(EarnRules.new_prizes(141, 212), [150, 200], "two steps in one run pay both")
	assert_eq(EarnRules.new_prizes(212, 240), none, "nothing new")
	assert_eq(EarnRules.new_prizes(150, 199), none, "150 counts once")
	assert_eq(EarnRules.new_prizes(90, 160), [100, 150], "a first-four milestone too")
	assert_eq(EarnRules.new_prizes(980, 1400), [1000], "nothing past 1000")
	var won: Array[int] = [25, 50, 75, 100, 150]
	assert_eq(EarnRules.new_prizes(0, 210, won), [200], "won ones are left out")
	assert_eq(EarnRules.new_prizes(0, 470, _upto(100), 420), [450], "and those under the mark")


func test_ladder_window() -> void:
	var none: Array[int] = []
	assert_eq(
		EarnRules.ladder_window(none), {"steps": [150, 200, 250], "more": 300}, "a new player"
	)
	assert_eq(
		EarnRules.ladder_window(_upto(162)),
		{"steps": [150, 200, 250], "more": 300},
		"the last won, the next, one more and the rest"
	)
	assert_eq(EarnRules.ladder_window(_upto(420)), {"steps": [400, 450, 500], "more": 550})
	assert_eq(
		EarnRules.ladder_window(_upto(860)), {"steps": [850, 900, 950, 1000], "more": 0}, "the top"
	)
	assert_eq(
		EarnRules.ladder_window(_upto(1500)),
		{"steps": [850, 900, 950, 1000], "more": 0},
		"all won: the last four"
	)
	assert_eq(
		EarnRules.ladder_window(_upto(100), 420),
		{"steps": [450, 500, 550], "more": 600},
		"an old player starts above the mark"
	)
	assert_eq(EarnRules.ladder_window(_upto(100), 960), {"steps": [1000], "more": 0})
	assert_eq(EarnRules.ladder_window(_upto(100), 1000), {"steps": [], "more": 0})


func test_status_reads_the_mark() -> void:
	var s := EarnStatus.parse(
		{"best": 470, "milestones": [25, 450, 125, 1050, 150], "ladder_mark": 420}
	)
	assert_eq(s.milestones, [25, 150, 450], "ladder steps count, odd scores don't")
	assert_eq(s.ladder_mark, 420)
	assert_eq(s.stale().ladder_mark, 420, "kept while offline")
	assert_eq(EarnStatus.parse({"best": 3}).ladder_mark, 0, "an old server: no mark")


func test_earn_free_ladder_cards() -> void:
	var p := Profile.new()
	var screen := _screen(p)
	screen.show_status(_status(0, []))
	assert_eq(screen.ladder_chips(), ["150 +3", "200 +3", "250 +3", "300 ... +3 each"])
	assert_eq(screen.next_ladder_chip(), "", "25 is next, not a step")
	screen.show_status(_status(162, _upto(162)))
	assert_eq(screen.milestone_labels(), ["Won", "Won", "Won", "Won"])
	assert_eq(screen.ladder_chips(), ["150 Won", "200 +3", "250 +3", "300 ... +3 each"])
	assert_eq(screen.next_ladder_chip(), "200")
	assert_eq(screen.best_text(), "Best 162. 38 more for 3 diamonds.")
	assert_eq(screen.bar_ratio(), 0.24)
	screen.show_status(_status(430, _upto(100), 420))
	assert_eq(screen.ladder_chips(), ["450 +3", "500 +3", "550 +3", "600 ... +3 each"])
	assert_eq(screen.best_text(), "Best 430. 20 more for 3 diamonds.")
	screen.show_status(_status(1190, _upto(1190)))
	assert_eq(screen.ladder_chips(), ["850 Won", "900 Won", "950 Won", "1,000 Won"])
	assert_eq(screen.best_text(), "All won. Your best is 1190.")
	assert_eq(screen.bar_ratio(), 1.0)
	screen.show_status(_status(1200, _upto(100), 1100))
	assert_eq(screen.ladder_chips(), [], "a mark past 1000 hides the ladder")
	assert_eq(screen.best_text(), "All won. Your best is 1200.")
	screen.get_parent().free()


func test_earn_free_fits_with_the_ladder() -> void:
	var p := Profile.new()
	p.diamonds = 999
	for status: EarnStatus in [
		_status(162, _upto(162)), _status(1190, _upto(1190)), _status(430, _upto(100), 420)
	]:
		var screen := EarnScreen.new(p)
		_fits(
			screen, "earn free (best %d)" % status.best, func() -> void: screen.show_status(status)
		)


func test_game_over_pill_text() -> void:
	var one: Array[int] = [150]
	var two: Array[int] = [150, 200]
	var three: Array[int] = [150, 200, 250]
	var mixed: Array[int] = [100, 150]
	assert_eq(GameOverScreen.prize_text(one), "+3 for Best 150 · yours once checked")
	assert_eq(GameOverScreen.prize_text(two), "+6 for Best 150 and 200 · yours once checked")
	assert_eq(GameOverScreen.prize_text(three), "+9 for Best 150 to 250 · yours once checked")
	assert_eq(GameOverScreen.prize_text(mixed), "+6 for Best 100 and 150 · yours once checked")


func _game_over(revived_at: int) -> GameOverScreen:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var screen := GameOverScreen.new()
	holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.show_result(1000, 1000, true, 1240, 141, 31, 1234, "Seed ABC123", revived_at, true)
	return screen


## The pill takes the seed's place: under the flyer and the stats, above the
## dock, inside the screen; the longest text fits too.
func test_game_over_pill_place() -> void:
	var dock_top := UiTokens.SIZE_VIEWPORT_H - Dock.HEIGHT
	var flyer_bottom := GameOverScreen.FLYER_Y + UiTokens.SIZE_BIRD / 2.0 * BirdView.SHOW_SCALE
	var many := EarnRules.new_prizes(141, 1000)
	for revived_at in [-1, 63]:
		var screen := _game_over(revived_at)
		assert_true(screen.seed_line() != "", "the seed shows without a prize")
		screen.show_prize(many)
		assert_eq(screen.prize_line(), "+54 for Best 150 to 1,000 · yours once checked")
		assert_eq(screen.seed_line(), "", "the pill takes the seed's place")
		var r := screen.prize_rect()
		assert_true(r.position.y >= flyer_bottom, "below the flyer (%d)" % r.position.y)
		assert_true(r.end.y <= dock_top, "ends at %d, above the dock at %d" % [r.end.y, dock_top])
		assert_true(r.position.x >= 8.0, "inside the screen: %s" % r)
		var none: Array[int] = []
		screen.show_prize(none)
		assert_eq(screen.prize_line(), "", "no prize, no pill")
		screen.show_prize(many)
		screen.show_result(42, 1000, false, 3, 1000, 2, 9, "Seed X", -1, true)
		assert_eq(screen.prize_line(), "", "the next game over starts without it")
		screen.show_prize(many)
		screen.show_daily(6, "1 try left", "Try 3")
		assert_eq(screen.prize_line(), "", "a Daily Run keeps its tries line")
		screen.get_parent().free()


func test_popup_shows_each_step() -> void:
	var one := DailyPrizePopup.new([{"kind": WalletService.MILESTONE, "ref": "150", "diamonds": 3}])
	assert_eq(one.rank_text(), "Best 150")
	assert_eq(one.step_texts(), [], "one step: no chips")
	assert_eq(one.claim_text(), "Claim 3")
	one.free()
	var two := (
		DailyPrizePopup
		. new(
			[
				{"kind": WalletService.MILESTONE, "ref": "200", "diamonds": 3},
				{"kind": WalletService.MILESTONE, "ref": "150", "diamonds": 3},
			]
		)
	)
	assert_eq(two.rank_text(), "Best 200", "the highest step is the headline")
	assert_eq(two.step_texts(), ["150", "200"])
	assert_eq(two.claim_text(), "Claim 6")
	two.free()
	var prizes: Array = []
	for score in EarnRules.milestone_scores():
		prizes.append(
			{
				"kind": WalletService.MILESTONE,
				"ref": str(score),
				"diamonds": EarnRules.milestone_prize(score)
			}
		)
	prizes.append({"kind": WalletService.STREAK, "ref": "2026-11-14", "diamonds": 1})
	var all := DailyPrizePopup.new(prizes)
	assert_eq(all.rank_text(), "Best 1000")
	assert_eq(all.step_texts(), ["25 to 1,000"], "many steps read as one range")
	assert_eq(all.claim_text(), "Claim 62")
	all.free()
	var daily := (
		DailyPrizePopup
		. new(
			[
				{"kind": WalletService.MILESTONE, "ref": "150", "diamonds": 3},
				{"kind": WalletService.MILESTONE, "ref": "200", "diamonds": 3},
				{"kind": WalletService.DAILY, "day": "2026-11-13", "rank": 2, "diamonds": 2},
			]
		)
	)
	assert_eq(daily.rank_text(), "#2", "a daily place still comes first")
	assert_eq(daily.step_texts(), [])
	daily.free()


func test_popup_with_steps_fits() -> void:
	var prizes: Array = []
	for score in [100, 150, 200, 250, 300, 350]:
		prizes.append({"kind": WalletService.MILESTONE, "ref": str(score), "diamonds": 3})
	_fits(DailyPrizePopup.new(prizes), "prize popup (six steps)")
