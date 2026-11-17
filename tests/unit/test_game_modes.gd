extends TestCase
## Home's mode picker: the mode list, the Play bar that plays the chosen mode,
## the mode sheet behind the Mode button, and the battles pill.

const TEST_PATH := "user://test_game_modes_profile.json"


func _home(p: Profile = null) -> HomeScreen:
	var prof := p if p != null else Profile.new()
	var home := HomeScreen.new(prof, AppServices.offline(prof))
	home.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(home)
	home.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	return home


## The Play bar's two lines: "Play" (or "Update") and the mode's line.
func _play_lines(home: HomeScreen) -> Array[String]:
	var out: Array[String] = []
	for l in home.play_button().find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


func test_every_mode_has_a_name_and_classic_comes_first() -> void:
	var ids := GameModes.ids()
	assert_eq(ids, [GameModes.CLASSIC, GameModes.DAILY, GameModes.DUEL], "Battle is paused")
	assert_false(GameModes.battle_enabled, "Battle stays hidden until it is picked up again")
	assert_false(GameModes.shown(GameModes.BATTLE))
	assert_eq(GameModes.find(GameModes.BATTLE).id, GameModes.CLASSIC, "a saved Battle is Classic")
	for m in GameModes.all():
		assert_false(m.title.is_empty(), "%s has a name" % m.id)
		assert_false(m.tab_title.is_empty(), "%s has a short name" % m.id)
		assert_false(m.rule.is_empty(), "%s has its rules in one line" % m.id)
		assert_true(m.icon != null, "%s has an icon" % m.id)
		assert_true(m.ready, "%s is built" % m.id)
	assert_eq(GameModes.find("gone").id, GameModes.CLASSIC, "an unknown mode is Classic")
	assert_eq(GameModes.badge(GameModes.CLASSIC), "", "Classic has no badge")


func test_one_tap_on_play_starts_the_chosen_mode() -> void:
	var p := Profile.new()
	p.best_score = 87
	var home := _home(p)
	var got: Array[String] = []
	home.play_pressed.connect(func() -> void: got.append("classic"))
	home.daily_run_pressed.connect(func() -> void: got.append("daily"))
	home.battle_pressed.connect(func() -> void: got.append("battle"))
	home.duel_pressed.connect(func() -> void: got.append("duel"))
	var saved: Array[String] = []
	home.settings_changed.connect(func() -> void: saved.append(p.home_mode))
	assert_eq(_play_lines(home), ["Play", "Classic · Best 87"], "Classic by default")
	home.play_button().pressed.emit()
	home.choose_mode(GameModes.DAILY)
	assert_eq(_play_lines(home)[1], "Daily · One map a day", "Play follows the chosen mode")
	home.play_button().pressed.emit()
	assert_eq(got, ["classic", "daily"], "Play starts the chosen mode")
	assert_eq(p.home_mode, GameModes.DAILY, "the chosen mode is kept in the profile")
	assert_eq(saved, [GameModes.DAILY], "and main is told to save it")
	home.choose_mode(GameModes.DUEL)
	assert_eq(_play_lines(home)[1], "Duel · Live 1v1")
	home.play_button().pressed.emit()
	assert_eq(got, ["classic", "daily", "duel"], "Duel opens Duel")
	home.free()


func test_the_mode_sheet_lists_every_mode_and_picks_one() -> void:
	var p := Profile.new()
	var home := _home(p)
	var mode := home.find_child("Mode", true, false) as Button
	mode.pressed.emit()
	var sheet := home.find_child("ModeSheet", true, false) as ModeSheet
	assert_true(sheet != null, "the Mode button opens the sheet")
	assert_eq(home.open_modes(), sheet, "one sheet at a time")
	assert_eq(sheet.row_ids(), GameModes.ids(), "every mode, in order")
	assert_true(sheet.row(GameModes.CLASSIC).find_child("Tick", true, false) != null, "chosen")
	assert_true(sheet.row(GameModes.DAILY).find_child("Tick", true, false) == null)
	sheet.row(GameModes.DAILY).pressed.emit()
	assert_eq(p.home_mode, GameModes.DAILY, "a row chooses its mode")
	assert_true(sheet.is_queued_for_deletion(), "and closes the sheet")
	home.free()


func test_home_opens_on_the_last_mode_chosen() -> void:
	var p := Profile.new()
	p.home_mode = GameModes.DAILY
	var home := _home(p)
	assert_true(_play_lines(home)[1].begins_with("Daily"))
	home.free()
	p.home_mode = "a mode taken out"
	home = _home(p)
	assert_true(_play_lines(home)[1].begins_with("Classic"), "an unknown mode opens on Classic")
	home.free()


func test_the_home_mode_is_kept_on_this_phone_only() -> void:
	var p := Profile.new()
	p.home_mode = GameModes.DAILY
	var back := Profile.from_dict(p.to_dict())
	assert_eq(back.home_mode, GameModes.DAILY, "saved and loaded")
	assert_true("home_mode" in Profile.LOCAL_KEYS, "never sent to the server")


func test_the_daily_run_shows_todays_tries() -> void:
	var p := Profile.new()
	p.home_mode = GameModes.DAILY
	var home := _home(p)
	var info := DailyRunInfo.new()
	info.tries_used = 1
	info.resets_in_s = 3600
	home.set_daily_info(info)
	assert_eq(_play_lines(home)[1], "Daily · 2 tries left")
	var sheet := home.open_modes()
	var line := sheet.row(GameModes.DAILY).find_child("Line", true, false) as Label
	assert_eq(line.text, "2 tries left · 1h 0m", "the sheet has the clock too")
	assert_true(sheet.row(GameModes.DAILY).find_child("Badge", true, false) == null, "no badge")
	home.set_daily_info(DailyRunInfo.offline())
	assert_eq(_play_lines(home)[1], "Daily · One map a day", "offline: the rules")
	home.free()


## Battle is paused: Home has no battles pill and the sheet no Battle row. The
## pill itself still says the turns in words, for when Battle comes back.
func test_battle_is_hidden_from_home() -> void:
	var home := _home()
	assert_true(home.find_child("Battles", true, false) == null, "no battles pill")
	home.set_battle_turns(2)
	var sheet := home.open_modes()
	assert_true(sheet.row(GameModes.BATTLE) == null, "no Battle row in the mode sheet")
	home.free()
	var pill := BattlesPill.new()
	assert_eq(pill.line_text(), "Battle a friend", "none waiting: start one")
	pill.set_turns(2)
	assert_eq(pill.line_text(), "Your turn in 2 battles")
	pill.set_turns(1)
	assert_eq(pill.line_text(), "Your turn in 1 battle")
	pill.free()


## With Battle back on (battle_enabled), Home gets its battles pill and the
## sheet its Battle row again, saying the turns in words.
func test_battle_comes_back_with_its_flag() -> void:
	GameModes.battle_enabled = true
	var home := _home()
	var pill := home.find_child("Battles", true, false) as BattlesPill
	assert_true(pill != null, "the battles pill is back")
	home.set_battle_turns(2)
	assert_eq(pill.line_text(), "Your turn in 2 battles")
	var line := home.open_modes().row(GameModes.BATTLE).find_child("Line", true, false) as Label
	assert_eq(line.text, "Your turn in 2 battles", "and the sheet's Battle row")
	var got: Array[String] = []
	home.battle_pressed.connect(func() -> void: got.append("battle"))
	pill.pressed.emit()
	assert_eq(got, ["battle"], "the pill opens Battles")
	home.free()
	GameModes.battle_enabled = false


## Duel (and Battle, when it is back) runs only on the server's gameplay
## version: an older app says Update on Play and in the sheet, and Play opens
## the store; Classic and the Daily Run go on.
func test_battle_and_duel_wait_for_an_update() -> void:
	var p := Profile.new()
	var home := _home(p)
	GameModes.set_server_version(SimConfig.GAMEPLAY_VERSION)
	assert_false(GameModes.needs_update(GameModes.BATTLE), "the same version plays")
	GameModes.set_server_version(SimConfig.GAMEPLAY_VERSION + 1)
	for id in [GameModes.BATTLE, GameModes.DUEL]:
		assert_true(GameModes.needs_update(id))
		assert_eq(GameModes.rule_line(id), GameModes.UPDATE_LINE)
		assert_eq(GameModes.play_label(id), GameModes.UPDATE)
	assert_false(GameModes.needs_update(GameModes.CLASSIC), "Classic goes on")
	assert_false(GameModes.needs_update(GameModes.DAILY), "and the Daily Run")
	home._process(0.0)
	var got: Array[String] = []
	home.update_pressed.connect(func() -> void: got.append("store"))
	home.duel_pressed.connect(func() -> void: got.append("duel"))
	home.choose_mode(GameModes.DUEL)
	assert_eq(_play_lines(home), ["Update", "Duel · Update to play"])
	home.play_button().pressed.emit()
	assert_eq(got, ["store"], "Play opens the store, not Duel")
	var sheet := home.open_modes()
	var badge := sheet.row(GameModes.DUEL).find_child("Badge", true, false) as Label
	assert_true(badge != null and badge.text == "UPDATE", "the sheet's Duel row says UPDATE")
	assert_true(StoreLink.url("Android").contains("com.mxndarijn.spikey"))
	assert_true(StoreLink.url("iOS").begins_with("https://apps.apple.com/"))
	GameModes.set_server_version(0)
	home.free()


## On a night world Play turns paper with ink text: ink on the dark sky would
## vanish (UiTheme.solid's rule).
func test_play_turns_paper_on_night_worlds() -> void:
	var home := HomeScreen.new(Profile.new(), AppServices.offline(Profile.new()))
	var dark := UiTheme.get_theme().duplicate() as Theme
	dark.set_color("font_color", "SkyLabel", UiTokens.ON_SCRIM)
	home.theme = dark
	(Engine.get_main_loop() as SceneTree).root.add_child(home)
	var box := home.play_button().get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(box.bg_color, UiTokens.PANEL, "paper Play at night")
	assert_eq(box.border_color, UiTokens.INK_LINE, "with an ink ring")
	home.free()
	var day := _home()
	box = day.play_button().get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(box.bg_color, UiTokens.PRIMARY, "ink Play by day")
	assert_eq(box.border_color, UiTokens.PANEL, "with a paper ring")
	day.free()
