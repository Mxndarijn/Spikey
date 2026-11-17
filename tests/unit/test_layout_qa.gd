extends ScreenFitCase
## Every menu screen, laid out in the room: nothing past the room's sides or in
## the ceiling and floor spike rows, no text cut off or trimmed, no two
## hand-placed siblings on top of each other (LayoutQa). And on the three phone
## shapes we check by eye (360x640, 390x844, 430x932 with their notches), the
## room the menus live in sits inside the safe area.

## Phones in points: size, then the safe insets top and bottom.
const PHONES := [
	[Vector2(360, 640), 0.0, 0.0],
	[Vector2(390, 844), 47.0, 34.0],
	[Vector2(430, 932), 59.0, 34.0],
]
const RIVAL := "Maximilianus12"
const ROOM_SIZE := Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _check(screen: Control, label: String, setup: Callable = Callable()) -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = ROOM_SIZE
	_tree().root.add_child(holder)
	holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if setup.is_valid():
		setup.call()
	for i in 4:
		await _tree().process_frame
	var found := LayoutQa.problems(screen)
	assert_true(found.is_empty(), "%s:\n  %s" % [label, "\n  ".join(found)])
	holder.free()


func test_the_room_sits_inside_the_safe_area_on_every_phone() -> void:
	for phone: Array in PHONES:
		var pts: Vector2 = phone[0]
		var k := float(UiTokens.SIZE_VIEWPORT_W) / pts.x
		var visible := Vector2(UiTokens.SIZE_VIEWPORT_W, pts.y * k)
		var safe := Rect2(0, phone[1] * k, visible.x, visible.y - (phone[1] + phone[2]) * k)
		var room := ScreenLayout.room_rect(visible, safe)
		assert_true(safe.encloses(room), "%s: room %s inside safe %s" % [pts, room, safe])
		assert_eq(room.size, ROOM_SIZE, "%s: the menus keep the 360 x 640 room" % pts)


func test_home_is_clean() -> void:
	for layout: int in [HomeScreen.Layout.BAR, HomeScreen.Layout.ROUND]:
		HomeScreen.layout = layout
		await _home_is_clean()
	HomeScreen.layout = HomeScreen.Layout.BAR


func _home_is_clean() -> void:
	var p := _profile()
	await _check(HomeScreen.new(p, AppServices.offline(p), 14), "home")
	var full := HomeScreen.new(p, AppServices.offline(p), 12345)
	var fill := func() -> void:
		var info := DailyRunInfo.new()
		info.resets_in_s = 86399
		full.set_daily_info(info)
		full.set_battle_turns(12)
		full.show_notice("Kofi took your #3 spot on today's board")
	await _check(full, "home, every badge and the notice", fill)
	var sheet := HomeScreen.new(p, AppServices.offline(p))
	await _check(sheet, "home, settings open", func() -> void: sheet.open_settings())
	var modes := HomeScreen.new(p, AppServices.offline(p))
	await _check(modes, "home, mode sheet open", func() -> void: modes.open_modes())
	var daily := HomeScreen.new(p, AppServices.offline(p))
	var pick := func() -> void:
		var info := DailyRunInfo.new()
		info.resets_in_s = 86399
		daily.set_daily_info(info)
		daily.choose_mode(GameModes.DAILY)
	await _check(daily, "home, Daily Run chosen", pick)


func test_boards_are_clean() -> void:
	var p := _profile()
	p.leaderboard_name = "Merry"
	var service := SampleLeaderboard.new(p)
	for id in LeaderboardService.BOARDS:
		await _check(LeaderboardScreen.new(p, service, id), "board %s" % id)
	var wins := WinsScreen.new()
	await _check(wins, "wins", func() -> void: wins.show_board("battle", "week", _wins_board()))
	var rec := WinsScreen.new()
	await _check(rec, "record", func() -> void: rec.show_record(_record()))


func test_battle_and_duel_screens_are_clean() -> void:
	var list := BattleListScreen.new()
	await _check(list, "battle list", func() -> void: list.show_battles(_battles()))
	await _check(BattleScreen.new(_view()), "round intro")
	await _check(BattleScreen.new(_view({"turn": "them", "play": null})), "their turn")
	await _check(
		BattleScreen.new(_view({"status": "finished", "winner": "me", "play": null})), "result"
	)
	await _check(BattleScreen.new(_view({"status": "waiting", "play": null}), "KD7WQ3"), "invite")
	var states: Array[Callable] = [
		func(s: DuelScreen) -> void: s.show_start(),
		func(s: DuelScreen) -> void: s.show_finding(),
		func(s: DuelScreen) -> void: s.show_invite("KD7WQ3"),
		func(s: DuelScreen) -> void: s.show_countdown(3, RIVAL, 1, 1, 3),
		func(s: DuelScreen) -> void: s.show_between("%s wins round 2" % RIVAL, 31, 40, RIVAL),
		func(s: DuelScreen) -> void: s.show_waiting(87, RIVAL),
		func(s: DuelScreen) -> void: s.show_result("me", 2, 1, RIVAL, false),
	]
	for i in states.size():
		var duel := DuelScreen.new()
		await _check(duel, "duel state %d" % i, states[i].bind(duel))


func test_the_other_screens_are_clean() -> void:
	var p := _profile()
	var daily := DailyRunScreen.new()
	await _check(daily, "daily run", func() -> void: daily.show_info(_daily_info()))
	await _check(RoomsScreen.new(p), "rooms")
	await _check(RoomDetailScreen.new(p, RoomCatalog.all()[3].id), "room detail")
	await _check(LookScreen.new(p), "style")
	await _check(
		CollectionScreen.new(Checkout.offline(p), CollectionScreen.Mode.SHOP, ItemKind.FLYER),
		"customize"
	)
	await _check(RunsScreen.new(RunStore.new("user://test_layout_qa_runs.json")), "runs")
	DirAccess.remove_absolute("user://test_layout_qa_runs.json")


func _wins_board() -> Dictionary:
	var entries := []
	for i in 8:
		(
			entries
			. append(
				{
					"rank": i + 1,
					"name": RIVAL if i == 1 else "Player%d" % i,
					"wins": 30 - i,
					"losses": i,
					"rate": 80 - i,
				}
			)
		)
	return {
		"entries": entries,
		"players": 214,
		"resets_in_s": 200000,
		"me": {"rank": 5, "wins": 18, "losses": 9, "rate": 66}
	}


func _record() -> Dictionary:
	return {
		"name": RIVAL,
		"wins": 27,
		"losses": 6,
		"draws": 1,
		"rate": 81,
		"best_streak": 9,
		"last": [{"opponent": "Jun", "result": "lost", "score": "3-6", "how": "resigned"}],
	}


func _view(changes: Dictionary = {}) -> BattleView:
	var d := {
		"battle": 12,
		"status": "open",
		"wins_me": 2,
		"wins_them": 2,
		"turn": "me",
		"opponent": {"name": RIVAL, "flyer": "buzz"},
		"last_move_s": 4000,
		"rounds":
		[
			{"number": 1, "winner": "me"},
			{"number": 2, "winner": "them"},
			{"number": 3},
			{"number": 4}
		],
		"play": {"round": 5, "role": "answer", "rival": {"score": 42}},
	}
	d.merge(changes, true)
	return BattleView.parse(d)


func _battles() -> Array[BattleView]:
	var out: Array[BattleView] = []
	out.append(_view())
	out.append(_view({"battle": 13, "turn": "them", "play": null}))
	out.append(_view({"battle": 14, "status": "finished", "winner": "me", "play": null}))
	return out


func _daily_info() -> DailyRunInfo:
	return DailyRunInfo.parse(
		{
			"number": 12,
			"resets_in_s": 15120,
			"tries_used": 1,
			"best": 64,
			"rank": 14,
			"players": 1210
		}
	)


## The run's overlays in the HUD: Game over (plain, a new best, a Daily Run
## try), Paused and the revive offer.
func test_the_run_overlays_are_clean() -> void:
	var hud: Hud = load("res://game/ui/hud.tscn").instantiate()
	_tree().root.add_child(hud)
	var root := hud.get_node("Root") as Control
	var looks: Array[Array] = [
		[
			"game over",
			func() -> void: hud.show_game_over(64, 92, false, 64, 92, 6, 3750, 4000000000)
		],
		[
			"new best",
			func() -> void: hud.show_game_over(9999, 9999, true, 999, 87, 99, 1, 4000000000)
		],
		["paused", func() -> void: hud.show_paused(true)],
		["revive", func() -> void: hud.revive_offer.show_offer(42, 1)],
	]
	for look: Array in looks:
		hud.show_running()
		(look[1] as Callable).call()
		for i in 4:
			await _tree().process_frame
		var found: Array[String] = []
		for c in root.get_children():
			if c is Control and (c as Control).is_visible_in_tree():
				found.append_array(LayoutQa.problems(c as Control))
		assert_true(found.is_empty(), "%s:\n  %s" % [look[0], "\n  ".join(found)])
	hud.free()
