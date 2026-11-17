extends TestCase
## Home's mode picker: the mode list, the carousel, the All modes sheet and
## what Play does for each mode.

const TEST_PATH := "user://test_game_modes_profile.json"


func _home(p: Profile = null) -> HomeScreen:
	var prof := p if p != null else Profile.new()
	var home := HomeScreen.new(prof, AppServices.offline(prof))
	home.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(home)
	home.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	return home


func test_every_mode_has_a_card_and_classic_comes_first() -> void:
	var ids := GameModes.ids()
	assert_eq(ids, [GameModes.CLASSIC, GameModes.DAILY, GameModes.BATTLE, GameModes.DUEL])
	for m in GameModes.all():
		assert_false(m.title.is_empty(), "%s has a name" % m.id)
		assert_false(m.rule.is_empty(), "%s has its rules in one line" % m.id)
		assert_true(m.icon != null, "%s has an icon" % m.id)
		assert_false(m.play_label.is_empty(), "%s names its Play" % m.id)
	assert_eq(GameModes.find("gone").id, GameModes.CLASSIC, "an unknown mode is Classic")
	assert_true(GameModes.find(GameModes.CLASSIC).ready)
	assert_true(GameModes.find(GameModes.DAILY).ready)
	assert_true(GameModes.find(GameModes.BATTLE).ready)
	assert_true(GameModes.find(GameModes.DUEL).ready)
	assert_eq(GameModes.badge(GameModes.CLASSIC), "", "Classic has no badge")


func test_the_carousel_swipes_and_taps() -> void:
	var c := ModeCarousel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(c)
	var picked: Array[String] = []
	var started: Array[String] = []
	c.selected.connect(func(id: String) -> void: picked.append(id))
	c.activated.connect(func(id: String) -> void: started.append(id))
	assert_eq(c.chosen(), GameModes.CLASSIC, "Classic by default")
	c.swipe(-80.0)
	assert_eq(c.chosen(), GameModes.DAILY, "a swipe to the left shows the next mode")
	c.swipe(80.0)
	assert_eq(c.chosen(), GameModes.CLASSIC, "a swipe to the right goes back")
	c.swipe(80.0)
	assert_eq(c.chosen(), GameModes.CLASSIC, "nothing before the first mode")
	c.tap_at(UiTokens.SIZE_VIEWPORT_W - 10.0)
	assert_eq(c.chosen(), GameModes.DAILY, "a tap on the right card chooses it")
	c.tap_at(UiTokens.SIZE_VIEWPORT_W / 2.0)
	assert_eq(started, [GameModes.DAILY], "a tap on the middle card starts it")
	c.tap_at(10.0)
	assert_eq(c.chosen(), GameModes.CLASSIC, "a tap on the left card chooses it")
	assert_eq(picked, [GameModes.DAILY, GameModes.CLASSIC, GameModes.DAILY, GameModes.CLASSIC])
	c.choose(99)
	assert_eq(c.chosen(), GameModes.DUEL, "kept to the last mode")
	c.free()


func test_the_middle_card_is_on_screen_and_its_neighbours_peek_in() -> void:
	var c := ModeCarousel.new(GameModes.DAILY)
	var mid := c.card(GameModes.DAILY)
	assert_eq(mid.position.x, (UiTokens.SIZE_VIEWPORT_W - ModeCarousel.CARD_W) / 2.0)
	var left := c.card(GameModes.CLASSIC)
	var right := c.card(GameModes.BATTLE)
	assert_true(left.position.x + ModeCarousel.CARD_W > 0.0, "the card before peeks in")
	assert_true(left.position.x < 0.0, "but most of it is off screen")
	assert_true(right.position.x < UiTokens.SIZE_VIEWPORT_W, "the card after peeks in")
	assert_true(right.position.x > mid.position.x + ModeCarousel.CARD_W, "beside the middle one")
	c.free()


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
	home.modes().choose_id(GameModes.DAILY)
	assert_eq(play.text, "Daily", "Play names the Daily Run")
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


func test_the_daily_card_shows_todays_tries() -> void:
	var home := _home()
	var info := DailyRunInfo.new()
	info.tries_used = 1
	info.resets_in_s = 3600
	home.set_daily_info(info)
	var modes := home.modes()
	assert_true(modes.rule_text(GameModes.DAILY).begins_with("2 tries left"))
	assert_eq(modes.badge_text(GameModes.DAILY), "2")
	assert_eq(modes.badge_text(GameModes.DUEL), "", "Duel has no badge")
	home.set_daily_info(DailyRunInfo.offline())
	assert_eq(modes.rule_text(GameModes.DAILY), GameModes.find(GameModes.DAILY).rule)
	assert_eq(modes.badge_text(GameModes.DAILY), "", "no badge while offline")
	home.free()


func test_all_modes_lists_every_mode_and_picks_one() -> void:
	var p := Profile.new()
	var home := _home(p)
	var link := home.find_child("AllModes", true, false) as Button
	link.pressed.emit()
	var sheet := home.find_child("ModesSheet", true, false) as ModesSheet
	assert_true(sheet != null, "All modes opens the sheet")
	assert_eq(home.open_all_modes(), sheet, "one sheet at a time")
	assert_eq(sheet.tile_ids(), GameModes.ids(), "every mode, in order")
	var on := sheet.tile(GameModes.CLASSIC).get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(on.border_width_left > 0, "the chosen mode is outlined")
	var off := sheet.tile(GameModes.DAILY).get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(off.border_width_left, 0)
	assert_true(sheet.tile(GameModes.DUEL).find_child("Badge", true, false) == null, "no badge")
	sheet.tile(GameModes.DAILY).pressed.emit()
	assert_eq(home.modes().chosen(), GameModes.DAILY, "a tile chooses its mode")
	assert_eq(p.home_mode, GameModes.DAILY)
	assert_true(sheet.is_queued_for_deletion(), "and closes the sheet")
	home.free()


## The carousel, the All modes link and the lost-spot line sit between the
## stats line and the flyer, and fit the narrowest phone.
func test_the_sky_line_clears_the_stats_and_the_flyer() -> void:
	var home := _home()
	var modes := home.modes()
	assert_true(HomeScreen.STATS_TOP + 24.0 <= modes.offset_top, "under the stats line")
	var link := home.find_child("AllModes", true, false) as Button
	assert_true(link.position.y >= modes.offset_top + ModeCarousel.DOTS_TOP, "under the cards")
	assert_true(link.size.y >= HomeScreen.ALL_MODES_H, "the link keeps its height")
	var flyer := home.flyer()
	var art := flyer.art_size()
	var flyer_top := flyer.position.y + flyer.size.y / 2.0 - art / 2.0 - flyer.bob_height
	home.show_notice("Someone took your #3 spot")
	assert_true(HomeScreen.NOTICE_TOP + 18.0 <= flyer_top, "the lost-spot line clears the flyer")
	for c in modes.get_children():
		var w := (c as Control).get_combined_minimum_size().x
		assert_true(w <= ModeCarousel.CARD_W, "%s keeps to its card's width" % c.name)
	home.free()


## Battle and Duel run only on the server's gameplay version: an older app shows
## "Update to play" on their cards and Play opens the store; Classic and the
## Daily Run go on.
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
	assert_eq(home.modes().rule_text(GameModes.BATTLE), GameModes.UPDATE_LINE, "the card says so")
	assert_eq(home.modes().badge_text(GameModes.DUEL), "UPDATE")
	var got: Array[String] = []
	home.update_pressed.connect(func() -> void: got.append("store"))
	home.battle_pressed.connect(func() -> void: got.append("battle"))
	home.modes().choose_id(GameModes.BATTLE)
	assert_eq(home.dock().primary().text, GameModes.UPDATE)
	home.dock().primary().pressed.emit()
	assert_eq(got, ["store"], "Play opens the store, not Battle")
	var sheet := home.open_all_modes()
	var tile := sheet.tile(GameModes.DUEL)
	assert_true(tile.find_child("Badge", true, false) != null, "the All modes tile too")
	assert_true(StoreLink.url("Android").contains("com.mxndarijn.spikey"))
	assert_true(StoreLink.url("iOS").begins_with("https://apps.apple.com/"))
	GameModes.set_server_version(0)
	home.free()
