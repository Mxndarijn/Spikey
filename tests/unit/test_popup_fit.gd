extends ScreenFitCase
## Popups, game over and headers on the narrowest phone: nothing is pushed
## past a screen edge or drawn under another control, at the longest text.

const HUD_SCENE := preload("res://game/ui/hud.tscn")


## The name dialog fits for a first pick, a rename and the longest name.
func test_name_dialog_fits() -> void:
	var longest := "W".repeat(LeaderboardService.NAME_MAX)
	for current: String in ["", "Wren_07", longest]:
		_fits(NameDialog.new(current), "name dialog ('%s')" % current)


## The convert sheet fits with no, one and many diamonds.
func test_convert_sheet_fits() -> void:
	for diamonds in [0, 1, 12, 999]:
		var p := _profile()
		p.diamonds = diamonds
		_fits(
			ConvertSheet.new(p, diamonds, "You need 160 more gold for Windmill Meadow."),
			"convert sheet (%d)" % diamonds
		)


## The settings sheet still fits where the player has an ad privacy choice.
func test_settings_sheet_fits_with_ad_choices() -> void:
	var ads := FakeAds.new()
	ads.privacy_required = true
	AdsService.current = ads
	_fits(SettingsSheet.new(_profile()), "settings with ad choices")
	AdsService.current = null


## Every item's popup fits, owned ("Use <name>") and in the shop (a price).
func test_item_popups_fit() -> void:
	var owner := _profile()
	owner.coins = 0
	for kind: String in Catalog.KINDS:
		for id: String in Catalog.ids(kind):
			owner.grant(kind, id)
	for p: Profile in [owner, _profile()]:
		for kind: String in Catalog.KINDS:
			for id: String in Catalog.ids(kind):
				var shop := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, kind)
				_fits(shop, "item popup (%s %s)" % [kind, id], shop._tap.bind(id))


## The prize popup fits whatever it headlines.
func test_prize_popup_fits() -> void:
	for prize: Dictionary in [
		{"kind": WalletService.DAILY, "day": "2026-09-30", "rank": 10, "diamonds": 1},
		{"kind": WalletService.MILESTONE, "ref": "1000", "diamonds": 3},
		{"kind": WalletService.STREAK, "ref": "2026-11-09", "diamonds": 1},
	]:
		_fits(DailyPrizePopup.new([prize]), "prize popup (%s)" % prize["kind"])


## Game over: a long final score and big stats stay on the screen.
func test_game_over_fits_a_long_score() -> void:
	for score in [7, 87, 1024, 99999]:
		var size := Hud.final_score_size(score)
		var w := (
			GameFonts.display().get_string_size(str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		)
		assert_true(w <= Hud.FINAL_SCORE_W, "%d is %d px wide at %d" % [score, w, size])
	assert_eq(Hud.final_score_size(87), UiTheme.BIG_SCORE_SIZE, "a short score stays big")
	var hud: Hud = HUD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.show_game_over(1024, 1024, true, 1240, 87, 312, 1234)
	var row := hud._stats.get_combined_minimum_size().x
	assert_true(
		row <= UiTokens.SIZE_VIEWPORT_W - Hud.WALL_CLEAR * 2,
		"the stats row is %d px, clear of the walls" % row
	)
	for col in hud._stats.get_children():
		var need := (col as Control).get_combined_minimum_size().x
		assert_true(need <= Hud.STAT_W, "a stat column is %d px" % need)
	for id in ["home", "rooms", "rank", "style"]:
		var b := hud._dock.button(id)
		assert_true(b.get_combined_minimum_size().x <= Dock.ITEM.x, "dock %s fits" % id)
	hud.free()


## A header title never runs under the back button or the wallet.
func test_header_titles_keep_clear() -> void:
	var p := _profile()
	p.coins = 999999
	p.diamonds = 999
	var screens: Array[Control] = [
		LookScreen.new(p), StoreScreen.new(p, StoreService.new()), RoomsScreen.new(p)
	]
	for kind: String in Catalog.KINDS:
		screens.append(CollectionScreen.new(p, CollectionScreen.Mode.SHOP, kind))
	for g: String in RoomInfo.GROUPS:
		for def: RoomDef in RoomInfo.rooms_in(g):
			screens.append(RoomDetailScreen.new(p, def.id))
	for screen in screens:
		_fits(screen, "header (%s)" % screen.get_class(), _check_header.bind(screen))


## Both the title and the right side hang from the row's right edge, so their
## offsets show the overlap before the row has a width.
func _check_header(screen: Control) -> void:
	var title := screen.find_child("Title", true, false) as Label
	assert_true(title != null, "has a title")
	if title == null:
		return
	var row := title.get_parent() as Control
	var back := UiKit.back_of(row)
	assert_true(title.offset_left >= back.offset_right, "'%s' clears the back" % title.text)
	assert_true(title.clip_text, "'%s' trims rather than overflow" % title.text)
	# Lay the screen out now (containers sort on the next frame otherwise).
	screen.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	var font := title.get_theme_font("font")
	var size := title.get_theme_font_size("font_size")
	var need := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	assert_true(
		need <= title.size.x + 0.5,
		"'%s' is %d px at %d, has %d: it would be cut" % [title.text, need, size, title.size.x]
	)
	for c in row.get_children():
		if c != title and c != back and c is Control:
			var other := c as Control
			assert_true(
				title.offset_right <= other.offset_left,
				(
					"'%s' ends at %d, the right side starts at %d"
					% [title.text, title.offset_right, other.offset_left]
				)
			)


## The replay and practice chips trim a long name instead of reaching the
## corner buttons.
func test_chips_stay_between_the_corner_buttons() -> void:
	var replay := ReplayHud.new()
	_in_tree(replay)
	replay.set_run("TapTapLeo_1234", 1024)
	var w := replay._banner.get_combined_minimum_size().x
	assert_true(w <= ReplayHud.CHIP_MAX, "replay chip is %d px" % w)
	replay.set_run("Wren", 31)
	assert_true(replay._banner.get_combined_minimum_size().x < w, "a short one stays snug")
	replay.free()
	var practice := PracticeHud.new()
	_in_tree(practice)
	practice.set_room("A Very Long Room Name Indeed")
	w = practice._banner.get_combined_minimum_size().x
	assert_true(w <= PracticeHud.CHIP_MAX, "practice chip is %d px" % w)
	practice.free()


func _in_tree(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


func test_big_amounts_read_short() -> void:
	assert_eq(UiKit.short_amount(9999), "9,999")
	assert_eq(UiKit.short_amount(12345), "12.3k")
	assert_eq(UiKit.short_amount(250000), "250k")
	assert_eq(UiKit.short_amount(999999), "999k")
	assert_eq(UiKit.short_amount(1234567), "1.2M")
