extends TestCase
## Battle's screens and a whole round in the app: the list, New battle, one
## battle in each state, the menu, the rival's bird in step with your run, and
## a round from its seed to battle_submit.

const TEST_PATH := "user://test_battle_profile.json"


## The server as canned answers per operation; remembers what was sent.
class FakeServer:
	extends FlapjawClient
	var answers := {}
	var sent: Array[Array] = []

	func _init() -> void:
		super(null, "https://api.example.com")

	func call_db(function: String, body: Dictionary) -> Dictionary:
		sent.append([function, JSON.parse_string(JSON.stringify(body))])
		return answers.get(function, {"ok": false, "code": 0, "data": null})

	func ops() -> Array[String]:
		var out: Array[String] = []
		for s in sent:
			out.append(str(s[0]))
		return out


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	_tree().root.add_child(main)
	return main


func _frames(n: int = 2) -> void:
	for i in n:
		await _tree().process_frame


func _holder(c: Control) -> Control:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	_tree().root.add_child(holder)
	holder.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return holder


## A short run of seed 7, as the rival's checked run.
func _rival_run() -> Dictionary:
	var taps := PackedInt32Array([0, 20, 40, 60, 80, 100, 120])
	var sim := Replay.simulate(7, taps)
	return {
		"score": sim.state.score,
		"coins": sim.state.coins,
		"taps": Array(taps),
		"seed": 7,
		"season": Seasons.NONE,
		"end_tick": sim.state.tick,
		"loadout": {"flyer": "buzz"},
	}


func _view(changes: Dictionary = {}) -> BattleView:
	var d := {
		"battle": 12,
		"status": "open",
		"first_to": 6,
		"starter": true,
		"wins_me": 2,
		"wins_them": 2,
		"turn": "me",
		"opponent": {"name": "Mira", "flyer": "buzz", "bot": false},
		"last_move_s": 100,
		"rounds":
		[
			{"number": 1, "winner": "me"},
			{"number": 2, "winner": "them"},
			{"number": 3, "winner": "me"},
			{"number": 4, "winner": "them"},
		],
		"play": {"round": 5, "role": "answer", "blind": false, "rival": _rival_run()},
	}
	d.merge(changes, true)
	return BattleView.parse(d)


func test_the_list_groups_battles_by_whose_turn() -> void:
	var screen := BattleListScreen.new()
	var holder := _holder(screen)
	var mine := _view()
	var theirs := _view({"battle": 13, "turn": "them", "play": null})
	var bot := _view(
		{"battle": 14, "opponent": {"name": "Pip", "flyer": "buzz", "bot": true}, "turn": "them"}
	)
	bot.play_round = 0
	var done := _view(
		{
			"battle": 15,
			"status": "finished",
			"winner": "me",
			"wins_me": 6,
			"turn": null,
			"play": null
		}
	)
	var all: Array[BattleView] = [mine, theirs, bot, done]
	screen.show_battles(all)
	var rows := screen.rows()
	assert_eq(rows.size(), 4)
	assert_eq(str(rows[0].name), "Battle12", "your turn first")
	assert_true(rows[2].find_child("BotPill", true, false) != null, "a bot always says so")
	assert_true(rows[0].find_child("BotPill", true, false) == null, "a person doesn't")
	assert_eq(BattleListScreen.turns_waiting(all), 1)
	var picked: Array[int] = []
	screen.battle_picked.connect(func(id: int) -> void: picked.append(id))
	rows[1].pressed.emit()
	assert_eq(picked, [13])
	var empty: Array[BattleView] = []
	screen.show_battles(empty)
	assert_eq(screen.note_text(), BattleListScreen.EMPTY)
	holder.free()


func test_a_battle_says_what_happens_now() -> void:
	var screen := BattleScreen.new(_view())
	var holder := _holder(screen)
	assert_eq(screen.title_text(), "Round 5 · Mira scored")
	assert_eq(screen.big_text(), str(_rival_run().score), "the score to beat")
	assert_true(screen.body_text().contains("One try"))
	var played: Array[int] = []
	screen.play_pressed.connect(func(n: int) -> void: played.append(n))
	screen.primary().pressed.emit()
	assert_eq(played, [5], "Play starts round 5")
	screen.show_view(_view({"play": {"round": 11, "role": "answer", "blind": true}}))
	assert_eq(screen.title_text(), "Round 11 decides it")
	assert_eq(screen.big_text(), "", "no score in a blind round")
	screen.show_view(_view({"play": {"round": 5, "role": "answer", "rival_pending": true}}))
	assert_true(screen.primary().disabled, "the rival's run is still being checked")
	screen.show_view(_view({"play": {"round": 6, "role": "open"}}))
	assert_eq(screen.title_text(), "Round 6 · you go first")
	screen.show_view(_view({"turn": "them", "play": null, "can_nudge": true}))
	assert_false(screen.primary().visible, "nothing to play on their turn")
	assert_eq(screen.extra().text, "Nudge Mira")
	var nudged: Array[bool] = []
	screen.nudge_pressed.connect(func() -> void: nudged.append(true))
	screen.extra().pressed.emit()
	assert_eq(nudged.size(), 1)
	screen.show_view(_view({"status": "finished", "winner": "me", "wins_me": 6, "play": null}))
	assert_eq(screen.title_text(), "You win")
	assert_eq(screen.primary().text, "Rematch")
	screen.set_notice("You win round 11 · 40–31")
	assert_eq(screen.notice_text(), "You win round 11 · 40–31")
	holder.free()


func test_an_invite_shows_its_code_to_copy() -> void:
	var waiting := _view({"status": "waiting", "turn": null, "opponent": null, "play": null})
	var screen := BattleScreen.new(waiting, "KD7WQ3")
	var holder := _holder(screen)
	assert_eq(screen.big_text(), "KD7·WQ3")
	var copied: Array[String] = []
	screen.copy_pressed.connect(func(t: String) -> void: copied.append(t))
	screen.extra().pressed.emit()
	assert_true(copied[0].contains("KD7WQ3") and copied[0].contains("/battle/KD7WQ3"))
	holder.free()


func test_new_battle_reads_a_typed_code() -> void:
	var sheet := NewBattleSheet.new(4)
	var holder := _holder(sheet)
	assert_eq(NewBattleSheet.clean(" kd7-wq3 "), "KD7WQ3")
	var joined: Array[String] = []
	sheet.join_pressed.connect(func(c: String) -> void: joined.append(c))
	sheet.field().text = "kd7"
	sheet.field().text_submitted.emit(sheet.field().text)
	assert_eq(joined.size(), 0, "too short")
	sheet.field().text = "kd7 wq3"
	sheet.field().text_submitted.emit(sheet.field().text)
	assert_eq(joined, ["KD7WQ3"])
	holder.free()


func test_the_menu_asks_before_resigning() -> void:
	var sheet := BattleMenuSheet.new(_view({"turn": "them", "can_close": false}))
	var holder := _holder(sheet)
	assert_true(sheet.close_button().disabled, "not before 7 days waiting")
	var resigned: Array[bool] = []
	sheet.resign_pressed.connect(func() -> void: resigned.append(true))
	sheet.resign_button().pressed.emit()
	assert_eq(resigned.size(), 0, "the first press asks")
	assert_true(sheet.resign_button().text.contains("Mira wins"))
	sheet.resign_button().pressed.emit()
	assert_eq(resigned.size(), 1)
	var bot := BattleMenuSheet.new(
		_view({"opponent": {"name": "Pip", "bot": true}, "can_close": true})
	)
	assert_false(bot.nudge_button().visible, "nobody to nudge")
	assert_false(bot.close_button().disabled, "a bot battle closes any time")
	bot.free()
	holder.free()


func test_the_rival_flies_in_step_with_your_run() -> void:
	var player := RunController.new()
	player.new_run(7)
	var ghost := RivalGhost.new(_rival_run(), Catalog.flyers()[0], "Mira")
	_tree().root.add_child(ghost)
	ghost.follow(player)
	assert_eq(ghost.pill_text(), "Beat %d" % _rival_run().score)
	for i in 50:
		if i % 20 == 0:
			player.request_tap()
		player.advance()
		ghost._physics_process(1.0 / 60.0)
		assert_eq(ghost.rival_sim().state.tick, player.sim.state.tick, "the same tick")
	assert_true(ghost.same_room())
	assert_eq(player.sim.seed_value, ghost.rival_sim().seed_value, "the same map")
	player.sim.state.score = _rival_run().score + 1
	assert_eq(ghost.pill_text(), "Round won!")
	ghost.free()
	player.free()


func test_a_round_in_the_app_from_its_seed_to_the_server() -> void:
	var main := _main()
	await _frames()
	var server := FakeServer.new()
	var view := _view()
	var data := {"battle": 12, "round": 5, "seed": 7, "season": Seasons.NONE, "blind": false}
	server.answers["battle_start_run"] = {"ok": true, "code": 200, "data": data}
	var after := {
		"battle": 12,
		"status": "open",
		"wins_me": 3,
		"wins_them": 2,
		"turn": "me",
		"opponent": {"name": "Mira", "flyer": "buzz", "bot": false},
		"rounds": [{"number": 5, "my_score": 9, "their_score": 1, "winner": "me"}],
		"play": {"round": 6, "role": "open"},
	}
	server.answers["battle_submit"] = {"ok": true, "code": 200, "data": after}
	server.answers["battle_get"] = {"ok": true, "code": 200, "data": after}
	var flow: BattleFlow = main._battle
	flow.service.client = server
	flow.start_round(view, 5)
	await _frames()
	assert_true(flow.playing != null, "the round's run started")
	assert_eq(main._run.sim.seed_value, 7, "it plays the round's seed")
	assert_true(flow.ghost() != null, "with the rival's bird beside it")
	main._run.request_tap()
	main._run.advance()
	main._run.sim.state.score = 8
	while not main._run.sim.is_over():
		main._run.advance()
	await _frames()
	assert_false(main._hud.revive_offer.visible, "no revive in a battle")
	assert_true(
		server.ops().has("battle_submit"), "the run goes to the battle: %s" % [server.ops()]
	)
	var body: Dictionary = server.sent[server.ops().find("battle_submit")][1]
	assert_eq(int(body.p_round), 5)
	assert_eq(int(body.p_seed), 7)
	assert_eq(int(body.p_score), main._run.sim.state.score)
	flow.back_to_battle()
	await _frames()
	var screen := main._menus.current() as BattleScreen
	assert_true(screen != null, "the battle shows again")
	assert_true(flow.ghost() == null, "the rival's bird is gone")
	main.free()
	SafeFile.remove(TEST_PATH)


## Main with a battle round played to its crash on the fake server.
## `answer`: the server's answer to the run (default: the round is decided).
func _crashed_round(answer: Dictionary = {}) -> Node:
	var main := _main()
	await _frames()
	var server := FakeServer.new()
	var data := {"battle": 12, "round": 5, "seed": 7, "season": Seasons.NONE, "blind": false}
	server.answers["battle_start_run"] = {"ok": true, "code": 200, "data": data}
	var after := {
		"battle": 12,
		"status": "open",
		"wins_me": 3,
		"wins_them": 2,
		"turn": "them",
		"opponent": {"name": "Mira", "flyer": "buzz", "bot": false},
		"rounds": [{"number": 5, "my_score": 9, "their_score": 1, "winner": "me"}],
		"play": {"round": 6, "role": "open"},
	}
	if not answer.is_empty():
		after = answer
	server.answers["battle_submit"] = {"ok": true, "code": 200, "data": after}
	server.answers["battle_get"] = {"ok": true, "code": 200, "data": after}
	var flow: BattleFlow = main._battle
	flow.service.client = server
	flow.start_round(_view(), 5)
	await _frames()
	main._run.request_tap()
	main._run.advance()
	while not main._run.sim.is_over():
		main._run.advance()
	await _frames()
	return main


## A tap that falls through the screen to the room, as the mouse sends it.
func _tap(main: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)


func test_after_a_round_only_the_battle_is_live() -> void:
	var main: Node = await _crashed_round()
	var flow: BattleFlow = main._battle
	flow.back_to_battle()
	await _frames()
	assert_true(main._menus.current() is BattleScreen, "the battle shows")
	# A tap through the battle screen, and Game over's Again under it.
	_tap(main)
	main._hud.play_again_pressed.emit()
	_tap(main)
	main._run.advance()
	assert_false(main._run.is_running(), "no new run starts beneath the battle")
	assert_false(main._hud.game_over.visible, "Game over is gone under the battle")
	# Again already went back: the crash's timer doesn't open the battle twice.
	var shown: Control = main._menus.current()
	await _tree().create_timer(BattleFlow.AFTER_CRASH_S + 0.2).timeout
	assert_true(main._menus.current() == shown, "the same battle screen, not a second one")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_the_notice_says_how_the_round_went_once_the_run_is_checked() -> void:
	# The server still checks the run: the round has no result yet.
	var checking := {
		"battle": 12,
		"status": "open",
		"turn": "me",
		"opponent": {"name": "Mira", "flyer": "buzz", "bot": false},
		"rounds": [{"number": 5, "my_score": 9, "their_score": 1}],
		"play": {"round": 5, "role": "answer"},
	}
	var main: Node = await _crashed_round(checking)
	var flow: BattleFlow = main._battle
	flow.back_to_battle()
	await _frames()
	var screen := main._menus.current() as BattleScreen
	var notice := screen.find_child("Notice", true, false) as Label
	assert_eq(notice.text, BattleFlow.CHECKING)
	var done := checking.duplicate(true)
	done.rounds = [{"number": 5, "my_score": 9, "their_score": 1, "winner": "me"}]
	done.play = {"round": 6, "role": "open"}
	var server := flow.service.client as FakeServer
	server.answers["battle_get"] = {"ok": true, "code": 200, "data": done}
	flow.service.request_battle(12)
	await _frames()
	assert_eq(notice.text, "You win round 5 · 9–1", "the checked round's result replaces Checking")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_home_right_after_a_crash_stays_home() -> void:
	var main: Node = await _crashed_round()
	main.show_home()
	await _tree().create_timer(BattleFlow.AFTER_CRASH_S + 0.2).timeout
	assert_true(main._menus.current() is HomeScreen, "Home stays; the battle doesn't jump over it")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_the_battle_after_the_crash_timer_is_out_of_play() -> void:
	var main: Node = await _crashed_round()
	await _tree().create_timer(BattleFlow.AFTER_CRASH_S + 0.2).timeout
	assert_true(main._menus.current() is BattleScreen, "the battle shows by itself")
	_tap(main)
	main._hud.play_again_pressed.emit()
	_tap(main)
	main._run.advance()
	assert_false(main._run.is_running(), "a tap on it plays nothing")
	main.free()
	SafeFile.remove(TEST_PATH)


func _board() -> Dictionary:
	return {
		"entries":
		[
			{"rank": 1, "name": "Mira", "wins": 17, "losses": 6, "rate": 74, "who": "abc"},
			{"rank": 2, "name": "Jun", "wins": 14, "losses": 9, "rate": null, "who": "def"},
		],
		"me": {"rank": 23, "wins": 4, "losses": 2, "rate": null},
		"players": 412,
		"resets_in_s": 3 * 86400,
	}


func test_the_wins_board_ranks_and_opens_a_record() -> void:
	var screen := WinsScreen.new()
	var asked: Array[Array] = []
	screen.board_requested.connect(func(m: String, p: String) -> void: asked.append([m, p]))
	var holder := _holder(screen)
	assert_eq(asked, [["battle", "week"]], "Battle this week first")
	screen.show_board("battle", "week", _board())
	assert_eq(screen.rows().size(), 2)
	assert_true(screen.caption_text().contains("412 players"))
	assert_eq(screen.pinned_text(), "#23  You  4–2", "your own row, no rate yet")
	assert_eq(WinsScreen.record_line({"wins": 17, "losses": 6, "rate": 74}), "17–6 · 74%")
	var wanted: Array[String] = []
	screen.record_requested.connect(
		func(_m: String, _p: String, who: String) -> void: wanted.append(who)
	)
	screen.rows()[0].pressed.emit()
	assert_eq(wanted, ["abc"])
	var record := {
		"name": "Mira",
		"wins": 17,
		"losses": 6,
		"draws": 1,
		"rate": 74,
		"best_streak": 7,
		"last":
		[{"opponent": "Jun", "result": "won", "score": "6-3", "how": "random", "counted": true}],
	}
	screen.show_record(record)
	assert_true(screen.record() != null)
	assert_eq(WinsScreen.match_line(record.last[0]), "Won 6–3 vs Jun · random")
	screen.close_record()
	assert_true(screen.record() == null)
	screen.show_board("battle", "all", _board())
	assert_eq(screen.rows().size(), 2, "an answer for another board is ignored")
	holder.free()


func test_the_score_boards_switch_to_wins() -> void:
	var p := Profile.new()
	p.leaderboard_name = "Ada"
	var screen := LeaderboardScreen.new(p, SampleLeaderboard.new(p))
	var holder := _holder(screen)
	var switched: Array[bool] = []
	screen.wins_pressed.connect(func() -> void: switched.append(true))
	var sw := screen.find_child("BoardSwitch", true, false) as BoardSwitch
	assert_true(sw != null, "Scores | Wins in the header")
	sw.button(BoardSwitch.SCORES).pressed.emit()
	assert_eq(switched.size(), 0, "Scores is the board in view")
	sw.button(BoardSwitch.WINS).pressed.emit()
	assert_eq(switched.size(), 1)
	holder.free()


func test_a_tapped_battle_push_opens_its_battle() -> void:
	var main := _main()
	await _frames()
	var flow: BattleFlow = main._battle
	var intents := flow.intents
	assert_true(intents != null, "the app looks at what the phone opened it with")
	# Android hands the push's data on as strings.
	intents.deliver({"push": {"kind": "battle_alert", "battle": "12"}})
	var screen := main._menus.current() as BattleScreen
	assert_true(screen != null and screen.view.id == 12, "battle 12 opens")
	intents.deliver({"push": {"kind": "battle_alert"}})
	assert_true(main._menus.current() is BattleListScreen, "no id: the battle list")
	intents.deliver({"push": {"kind": "board_alert"}})
	assert_true(main._menus.current() is BattleListScreen, "a board alert opens nothing new")
	intents.deliver({"push": {"kind": "duel_alert"}})
	assert_true(main._menus.current() is DuelScreen, "a Duel push: the Duel screen")
	intents.deliver("nonsense")
	main.free()
	SafeFile.remove(TEST_PATH)
