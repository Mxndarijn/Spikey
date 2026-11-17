extends ScreenFitCase
## Battle's screens and the wins boards fit the narrowest phone (360 x 640).


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
