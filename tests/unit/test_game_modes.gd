extends TestCase
## Home's mode picker: the mode list, the mode tabs with their badges, and
## what Play does for each mode.

const TEST_PATH := "user://test_game_modes_profile.json"


func _home(p: Profile = null) -> HomeScreen:
	var prof := p if p != null else Profile.new()
	var home := HomeScreen.new(prof, AppServices.offline(prof))
	home.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(home)
	home.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	return home


func test_every_mode_has_a_tab_and_classic_comes_first() -> void:
	var ids := GameModes.ids()
	assert_eq(ids, [GameModes.CLASSIC, GameModes.DAILY, GameModes.BATTLE, GameModes.DUEL])
	for m in GameModes.all():
		assert_false(m.title.is_empty(), "%s has a name" % m.id)
		assert_false(m.tab_title.is_empty(), "%s has a name for its tab" % m.id)
		assert_false(m.rule.is_empty(), "%s has its rules in one line" % m.id)
		assert_true(m.icon != null, "%s has an icon" % m.id)
		assert_false(m.play_label.is_empty(), "%s names its Play" % m.id)
	assert_eq(GameModes.find("gone").id, GameModes.CLASSIC, "an unknown mode is Classic")
	assert_true(GameModes.find(GameModes.CLASSIC).ready)
	assert_true(GameModes.find(GameModes.DAILY).ready)
	assert_true(GameModes.find(GameModes.BATTLE).ready)
	assert_true(GameModes.find(GameModes.DUEL).ready)
	assert_eq(GameModes.badge(GameModes.CLASSIC), "", "Classic has no badge")


func test_the_tabs_choose_a_mode() -> void:
	var c := ModeTabs.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(c)
	var picked: Array[String] = []
	c.selected.connect(func(id: String) -> void: picked.append(id))
	assert_eq(c.chosen(), GameModes.CLASSIC, "Classic by default")
	assert_eq(c.tab_ids(), GameModes.ids(), "a tab per mode, in order")
	assert_true(c.tab(GameModes.CLASSIC).button_pressed, "the chosen tab is filled")
	c.tab(GameModes.DAILY).pressed.emit()
	assert_eq(c.chosen(), GameModes.DAILY, "a tap on a tab chooses it")
	assert_true(c.tab(GameModes.DAILY).button_pressed)
	assert_false(c.tab(GameModes.CLASSIC).button_pressed, "one tab at a time")
	assert_eq(c.line_text(), GameModes.find(GameModes.DAILY).rule, "its rules under the bar")
	c.tab(GameModes.DAILY).pressed.emit()
	assert_eq(picked, [GameModes.DAILY], "a tap on the chosen tab changes nothing")
	c.tab(GameModes.DUEL).pressed.emit()
	assert_eq(picked, [GameModes.DAILY, GameModes.DUEL])
	c.choose(99)
	assert_eq(c.chosen(), GameModes.DUEL, "kept to the last mode")
	c.free()


## Each tab shows its short name in full, with room for its badge, on the
## narrowest phone.
func test_the_tab_names_fit() -> void:
	var home := _home()
	for i in 3:
		await (Engine.get_main_loop() as SceneTree).process_frame
	var tabs := home.modes()
	assert_eq(tabs.size.x, UiTokens.SIZE_VIEWPORT_W - HomeScreen.TABS_SIDE * 2)
	for id in tabs.tab_ids():
		var t := tabs.tab(id)
		var font := t.get_theme_font("font")
		var need := font.get_string_size(
			t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.get_theme_font_size("font_size")
		)
		assert_true(
			need.x + 16.0 <= t.size.x, "%s fits its tab (%d of %d px)" % [id, need.x, t.size.x]
		)
		assert_true(t.size.y >= UiTokens.SIZE_TAP_MIN, "%s is big enough to tap" % id)
	home.free()


func test_play_starts_the_chosen_mode() -> void:
	var p := Profile.new()
	var home := _home(p)
	var got: Array[String] = []
	home.play_pressed.connect(func() -> void: got.append("classic"))
	home.daily_run_pressed.connect(func() -> void: got.append("daily"))
	home.battle_pressed.connect(func() -> void: got.append("battle"))
	home.duel_pressed.connect(func() -> void: got.append("duel"))
	var saved: Array[String] = []
	home.settings_changed.connect(func() -> void: saved.append(p.home_mode))
	var play := home.dock().primary()
	assert_eq(play.text, "Play")
	play.pressed.emit()
	home.modes().tab(GameModes.DAILY).pressed.emit()
	assert_eq(play.text, "Daily", "Play follows the tab: the Daily Run")
	assert_false(play.disabled)
	play.pressed.emit()
	assert_eq(got, ["classic", "daily"], "Play starts the chosen mode")
	assert_eq(p.home_mode, GameModes.DAILY, "the chosen mode is kept in the profile")
	assert_eq(saved, [GameModes.DAILY], "and main is told to save it")
	home.modes().choose_id(GameModes.BATTLE)
	assert_eq(play.text, "Battles")
	play.pressed.emit()
	assert_eq(got, ["classic", "daily", "battle"], "Battle opens Battles")
	home.modes().choose_id(GameModes.DUEL)
	assert_eq(play.text, "Duel")
	play.pressed.emit()
	assert_eq(got, ["classic", "daily", "battle", "duel"], "Duel opens Duel")
	home.free()


func test_home_opens_on_the_last_mode_chosen() -> void:
	var p := Profile.new()
	p.home_mode = GameModes.DAILY
	var home := _home(p)
	assert_eq(home.modes().chosen(), GameModes.DAILY)
	assert_eq(home.dock().primary().text, "Daily")
	home.free()
	p.home_mode = "a mode taken out"
	home = _home(p)
	assert_eq(home.modes().chosen(), GameModes.CLASSIC, "an unknown mode opens on Classic")
	home.free()


func test_the_home_mode_is_kept_on_this_phone_only() -> void:
	var p := Profile.new()
	p.home_mode = GameModes.DAILY
	var back := Profile.from_dict(p.to_dict())
	assert_eq(back.home_mode, GameModes.DAILY, "saved and loaded")
	assert_true("home_mode" in Profile.LOCAL_KEYS, "never sent to the server")


func test_the_daily_tab_shows_todays_tries() -> void:
	var home := _home()
	var info := DailyRunInfo.new()
	info.tries_used = 1
	info.resets_in_s = 3600
	home.set_daily_info(info)
	var modes := home.modes()
	assert_true(modes.rule_text(GameModes.DAILY).begins_with("2 tries left"))
	assert_eq(modes.badge_text(GameModes.DAILY), "2", "the tries left on the tab's badge")
	assert_eq(modes.line_text(), GameModes.find(GameModes.CLASSIC).rule, "Classic's line shows")
	modes.choose_id(GameModes.DAILY)
	assert_true(modes.line_text().ends_with("1h 0m"), "the chosen tab's line: " + modes.line_text())
	assert_eq(modes.badge_text(GameModes.DUEL), "", "Duel has no badge")
	home.set_daily_info(DailyRunInfo.offline())
	assert_eq(modes.rule_text(GameModes.DAILY), GameModes.find(GameModes.DAILY).rule)
	assert_eq(modes.badge_text(GameModes.DAILY), "", "no badge while offline")
	home.free()


## The battles waiting for your turn show on the Battle tab, and go when
## there are none.
func test_the_battle_tab_counts_your_turns() -> void:
	var home := _home()
	var modes := home.modes()
	home.set_battle_turns(2)
	assert_eq(modes.badge_text(GameModes.BATTLE), "2")
	assert_eq(modes.rule_text(GameModes.BATTLE), "2 battles wait for your turn")
	home.set_battle_turns(1)
	assert_eq(modes.rule_text(GameModes.BATTLE), "1 battle waits for your turn")
	home.set_daily_info(DailyRunInfo.offline())
	assert_eq(modes.badge_text(GameModes.BATTLE), "1", "the Daily Run's news keeps it")
	home.set_battle_turns(0)
	assert_eq(modes.badge_text(GameModes.BATTLE), "", "no badge with no turn waiting")
	assert_eq(modes.rule_text(GameModes.BATTLE), GameModes.find(GameModes.BATTLE).rule)
	home.free()


## The tabs, their rules line and the lost-spot line sit between the stats
## line and the flyer, and fit the narrowest phone.
func test_the_sky_line_clears_the_stats_and_the_flyer() -> void:
	var home := _home()
	var modes := home.modes()
	assert_true(HomeScreen.STATS_TOP + 24.0 <= modes.offset_top, "under the stats line")
	var flyer := home.flyer()
	var art := flyer.art_size()
	var flyer_top := flyer.position.y + flyer.size.y / 2.0 - art / 2.0 - flyer.bob_height
	assert_true(modes.offset_bottom <= HomeScreen.NOTICE_TOP, "the tabs end above the notice")
	home.show_notice("Someone took your #3 spot")
	assert_true(HomeScreen.NOTICE_TOP + 18.0 <= flyer_top, "the lost-spot line clears the flyer")
	assert_true(
		modes.get_combined_minimum_size().x <= UiTokens.SIZE_VIEWPORT_W - HomeScreen.TABS_SIDE * 2,
		"the tabs keep to the screen's gutters"
	)
	home.free()


## Battle and Duel run only on the server's gameplay version: an older app shows
## "Update to play" under their tabs, an UPDATE badge, and Play opens the store;
## Classic and the Daily Run go on.
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
	assert_eq(home.modes().rule_text(GameModes.BATTLE), GameModes.UPDATE_LINE, "the tab says so")
	assert_eq(home.modes().badge_text(GameModes.DUEL), "UPDATE")
	home.set_battle_turns(3)
	assert_eq(home.modes().badge_text(GameModes.BATTLE), "UPDATE", "turns never hide the update")
	var got: Array[String] = []
	home.update_pressed.connect(func() -> void: got.append("store"))
	home.battle_pressed.connect(func() -> void: got.append("battle"))
	home.modes().choose_id(GameModes.BATTLE)
	assert_eq(home.dock().primary().text, GameModes.UPDATE)
	home.dock().primary().pressed.emit()
	assert_eq(got, ["store"], "Play opens the store, not Battle")
	assert_true(StoreLink.url("Android").contains("com.mxndarijn.spikey"))
	assert_true(StoreLink.url("iOS").begins_with("https://apps.apple.com/"))
	GameModes.set_server_version(0)
	home.free()
