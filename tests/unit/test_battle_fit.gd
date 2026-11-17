extends ScreenFitCase
## Battle's screens and the wins boards fit the narrowest phone (360 x 640).


## Battle is paused in the app; these tests turn it on.
func _init() -> void:
	GameModes.battle_enabled = true


func _view(status: String, turn: String) -> BattleView:
	return (
		BattleView
		. parse(
			{
				"battle": 3,
				"status": status,
				"wins_me": 5,
				"wins_them": 5,
				"turn": turn,
				"opponent": {"name": "Maximilianus12", "bot": true},
				"rounds":
				[{"winner": "me"}, {"winner": "them"}, {"winner": "draw"}, {}, {}, {}, {}],
				"play": {"round": 11, "role": "answer", "blind": true},
			}
		)
	)


func test_battle_screens_fit() -> void:
	_fits(BattleScreen.new(_view("open", "me")), "battle, your turn")
	_fits(BattleScreen.new(_view("open", "them")), "battle, their turn")
	_fits(BattleScreen.new(_view("waiting", ""), "KD7WQ3"), "battle, invite")
	_fits(BattleScreen.new(_view("finished", "")), "battle, finished")
	_fits(BattleListScreen.new(), "battle list")
	_fits(WinsScreen.new(), "wins boards")


func test_battle_sheets_fit() -> void:
	_fits(NewBattleSheet.new(19), "new battle")
	_fits(BattleMenuSheet.new(_view("open", "them")), "battle menu")
	var wins := WinsScreen.new()
	_fits(
		wins,
		"a player's record",
		func() -> void:
			(
				wins
				. show_record(
					{
						"name": "Maximilianus12",
						"wins": 100,
						"losses": 99,
						"draws": 3,
						"rate": 50,
						"best_streak": 12,
						"last":
						[
							{
								"opponent": "Maximilianus12",
								"result": "won",
								"score": "6-5",
								"how": "friend"
							},
							{
								"opponent": "Jun",
								"result": "lost",
								"score": "3-6",
								"how": "resigned"
							},
						],
					}
				)
			)
	)


func test_the_duel_screen_fits_in_every_state() -> void:
	var states: Array[Callable] = [
		func(s: DuelScreen) -> void: s.show_start(),
		func(s: DuelScreen) -> void: s.show_finding(),
		func(s: DuelScreen) -> void: s.show_invite("KD7WQ3"),
		func(s: DuelScreen) -> void: s.show_countdown(5, "Maximilianus12", 2, 2, 3),
		func(s: DuelScreen) -> void:
			s.show_between("Maximilianus12 wins round 5", 150, 149, "Maximilianus12"),
		func(s: DuelScreen) -> void: s.show_waiting(87, "Maximilianus12"),
		func(s: DuelScreen) -> void: s.show_result("them", 1, 2, "Maximilianus12", true),
	]
	for show in states:
		var screen := DuelScreen.new()
		_fits(screen, "duel", func() -> void: show.call(screen))
