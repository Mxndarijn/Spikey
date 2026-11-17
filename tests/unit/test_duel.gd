extends TestCase
## Duel's client side: the Duel screen in each state, the live rival bird a
## little behind your own, and a round in the app from the server's countdown
## to the result, with the ticks this phone sends.

const TEST_PATH := "user://test_duel_profile.json"


## The socket, keeping what would go out.
class FakeLink:
	extends DuelLink
	var sent: Array[Dictionary] = []

	func _init() -> void:
		super(null)

	func send(msg: Dictionary) -> void:
		sent.append(msg)

	func open(_player_name: String, _flyer: String) -> void:
		pass

	func kinds() -> Array[String]:
		var out: Array[String] = []
		for m in sent:
			out.append(str(m.get("t", "")))
		return out


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


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


func test_the_duel_screen_in_each_state() -> void:
	var screen := DuelScreen.new()
	var holder := _holder(screen)
	assert_eq(screen.state, DuelScreen.State.START)
	var got: Array[String] = []
	screen.find_pressed.connect(func() -> void: got.append("find"))
	screen.invite_pressed.connect(func() -> void: got.append("invite"))
	screen.join_pressed.connect(func(c: String) -> void: got.append("join " + c))
	screen.battle_pressed.connect(func() -> void: got.append("battle"))
	screen.primary().pressed.emit()
	screen.a_button().pressed.emit()
	screen.field().text = "kd7-wq3"
	screen.field().text_submitted.emit(screen.field().text)
	assert_eq(got, ["find", "invite", "join KD7WQ3"])
	screen.show_finding()
	assert_false(screen.b_button().visible, "no Battle offer at first")
	screen._process(31.0)
	assert_true(screen.b_button().visible, "after 30 s alone: a Battle instead")
	screen.b_button().pressed.emit()
	assert_eq(got.back(), "battle")
	screen.show_invite("KD7WQ3")
	assert_eq(screen.big_text(), "KD7·WQ3")
	screen.show_countdown(2, "Mira", 1, 0, 3)
	assert_eq(screen.title_text(), "Round 2")
	assert_eq(screen.big_text(), "3")
	screen.show_between("You win round 2", 31, 20, "Mira")
	assert_eq(screen.big_text(), "31 – 20")
	screen.show_result("them", 1, 2, "Mira", true)
	assert_eq(screen.title_text(), "Mira wins")
	assert_true(screen.body_text().begins_with("You left the duel"))
	assert_eq(screen.primary().text, "Rematch")
	holder.free()


func test_the_live_rival_flies_a_little_behind_and_never_past_its_news() -> void:
	var player := RunController.new()
	player.new_run(7)
	var ghost := RivalGhost.live_on(7, Seasons.NONE, Catalog.flyers()[0], "Mira")
	_tree().root.add_child(ghost)
	ghost.follow(player)
	assert_eq(ghost.pill_text(), "", "nothing to beat while the rival flies")
	for i in 60:
		player.advance()
	ghost._physics_process(1.0 / 60.0)
	assert_eq(ghost.rival_sim().state.tick, 0, "no news from the rival yet: it holds")
	ghost.feed(48, [0, 20, 40])
	ghost._physics_process(1.0 / 60.0)
	assert_true(ghost.rival_sim().state.tick <= 48, "never past the last tick it confirmed")
	assert_true(
		ghost.delay_ticks >= RivalGhost.DELAY_MIN and ghost.delay_ticks <= RivalGhost.DELAY_MAX
	)
	for i in 20:
		player.advance()
		ghost.feed(player.sim.state.tick, [])
		ghost._physics_process(1.0 / 60.0)
	var behind := player.sim.state.tick - ghost.rival_sim().state.tick
	assert_eq(behind, ghost.delay_ticks, "a jitter buffer behind your own bird")
	assert_true(ghost.delay_ticks <= 12, "news on time: about 100 to 200 ms")
	ghost.set_down(14)
	assert_eq(ghost.pill_text(), "Beat 14")
	ghost.free()
	player.free()


func test_a_round_in_the_app_from_countdown_to_result() -> void:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	_tree().root.add_child(main)
	await _frames()
	var link := FakeLink.new()
	main.add_child(link)
	var flow := DuelFlow.new(link, main._battle, main._menus, main._hud, main._profile)
	flow.open()
	flow.on_message({"t": "matched", "match": 1, "rival": {"name": "Mira", "flyer": "buzz"}})
	flow.on_message(
		{"t": "countdown", "round": 1, "seed": 7, "season": -1, "start_in_ms": 0, "wins": [0, 0]}
	)
	await _frames()
	assert_true(flow.playing() != null, "the round's run started")
	assert_eq(main._run.sim.seed_value, 7, "on the server's seed")
	assert_true(main._battle.ghost() == flow.ghost(), "with Mira's live bird")
	# No pause in a Duel round: not the button, not the keyboard, not leaving the app.
	assert_true(main._hud.no_pause)
	main._hud.show_running()
	var pause := main._hud.find_child("Pause", true, false) as Button
	assert_false(pause.visible, "no pause button in a Duel round")
	main._run.request_tap()
	main._run.advance()
	main._toggle_pause()
	assert_false(main._run.paused, "P or Back doesn't pause either")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(main._run.paused, "leaving the app doesn't pause: the clock goes on")
	for i in 12:
		main._run.advance()
		flow._on_ticked()
	var ticks := link.sent.filter(func(m: Dictionary) -> bool: return m.t == "ticks")
	assert_true(ticks.size() >= 1, "ticks go out every 6 ticks: %s" % [link.kinds()])
	assert_eq((ticks[0].taps as Array).size(), 1, "with the tap since the last")
	flow.on_message({"t": "rival", "tick": 10, "taps": [0, 5]})
	assert_eq(flow.ghost().confirmed, 10)
	while not main._run.sim.is_over():
		main._run.advance()
	await _frames()
	assert_false(main._hud.revive_offer.visible, "no revive in a duel")
	flow.on_message(
		{
			"t": "round_over",
			"round": 1,
			"winner": "them",
			"my_score": 0,
			"their_score": 3,
			"wins": [0, 1]
		}
	)
	var screen := main._menus.current() as DuelScreen
	assert_true(screen != null and screen.state == DuelScreen.State.BETWEEN, "between rounds")
	assert_eq(screen.title_text(), "Mira wins round 1")
	assert_true(main._battle.playing == null, "no round in play")
	assert_false(main._hud.no_pause, "pause is back outside a Duel round")
	flow.on_message({"t": "match_over", "winner": "them", "ended_by": "played", "wins": [0, 2]})
	screen = main._menus.current() as DuelScreen
	assert_eq(screen.state, DuelScreen.State.RESULT)
	screen.primary().pressed.emit()
	assert_eq(link.kinds().back(), "rematch")
	main.free()
	SafeFile.remove(TEST_PATH)


func test_a_phone_that_left_the_app_hears_why_it_is_down() -> void:
	var link := FakeLink.new()
	_tree().root.add_child(link)
	var screen := DuelScreen.new()
	var holder := _holder(screen)
	screen.show_waiting(4, "Mira", true)
	assert_true(screen.body_text().begins_with("You left the app"), screen.body_text())
	assert_true(screen.body_text().contains("needs 5"))
	screen.show_waiting(4, "Mira")
	assert_false(screen.body_text().contains("left the app"), "a crash says nothing of it")
	holder.free()
	link.free()
