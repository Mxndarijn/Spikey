extends TestCase
## Every menu screen must fit the 360 x 640 play area with room left for the
## floor spikes, so no button ends up off screen or behind the spikes.

const FLOOR_CLEARANCE := 40.0


## setup runs once the screen is in the tree (to show a board, open a dialog).
func _fits(screen: Control, label: String, setup: Callable = Callable()) -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if setup.is_valid():
		setup.call()
	var need := 0.0
	var wide := 0.0
	for child in screen.get_children():
		if child is Control:
			need = maxf(need, (child as Control).get_combined_minimum_size().y)
			wide = maxf(wide, (child as Control).get_combined_minimum_size().x)
	# Nothing may be pushed past the side edges either (cards, tabs, pills).
	assert_true(
		wide <= UiTokens.SIZE_VIEWPORT_W,
		"%s needs %d px of width, the screen has %d" % [label, wide, UiTokens.SIZE_VIEWPORT_W]
	)
	assert_true(
		need <= UiTokens.SIZE_VIEWPORT_H,
		"%s needs %d px of height, the screen has %d" % [label, need, UiTokens.SIZE_VIEWPORT_H]
	)
	holder.free()


func _profile() -> Profile:
	var p := Profile.new()
	p.coins = 12345
	p.best_score = 87
	p.onboarded = true
	for kind in Catalog.KINDS:
		var id: String = Catalog.ids(kind)[0]
		p.grant(kind, id)
		p.equip(kind, id)
	return p


func test_shop_fits_on_every_tab() -> void:
	for kind: String in Catalog.KINDS + [CollectionScreen.HATS]:
		var shop := CollectionScreen.new(_profile(), CollectionScreen.Mode.SHOP, kind)
		_fits(shop, "shop (%s)" % kind)


func test_home_fits() -> void:
	_fits(HomeScreen.new(_profile()), "home")


## Home stacks the wordmark, the stats line, the big flyer and the dock with
## no overlaps, all above the floor spikes.
func test_home_logo_clears_the_flyer() -> void:
	var home := HomeScreen.new(_profile())
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	holder.add_child(home)
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var logo := home.logo()
	var logo_bottom := logo.offset_top + logo.get_combined_minimum_size().y
	var flyer := home.flyer()
	var art := flyer.art_size()
	var flyer_top := flyer.position.y + flyer.size.y / 2.0 - art / 2.0 - flyer.bob_height
	var flyer_bottom := flyer.position.y + flyer.size.y / 2.0 + art / 2.0 + flyer.bob_height
	assert_true(
		logo_bottom <= HomeScreen.STATS_TOP,
		"logo ends at %d px, the stats line starts at %d px" % [logo_bottom, HomeScreen.STATS_TOP]
	)
	assert_true(
		HomeScreen.STATS_TOP + 24.0 <= flyer_top,
		"the stats line ends above the flyer (%d px)" % flyer_top
	)
	var dock_top := UiTokens.SIZE_VIEWPORT_H - Dock.HEIGHT
	assert_true(flyer_bottom <= dock_top, "the flyer ends above the dock (%d px)" % flyer_bottom)
	var bar_bottom := dock_top + Dock.BAR_TOP + Dock.BAR_H
	assert_true(
		bar_bottom <= UiTokens.SIZE_VIEWPORT_H - FLOOR_CLEARANCE, "the dock clears the floor"
	)
	holder.free()


## The settings sheet (all rows) fits between its top and bottom margins, and
## every control in it is big enough to tap.
func test_settings_sheet_fits() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var sheet := SettingsSheet.new(_profile())
	holder.add_child(sheet)
	var card := sheet.find_child("Card", true, false) as Control
	var room := UiTokens.SIZE_VIEWPORT_H - SettingsSheet.MARGIN_TOP - SettingsSheet.MARGIN_BOTTOM
	var need := card.get_combined_minimum_size()
	assert_true(need.y <= room, "the sheet needs %d px, has %d" % [need.y, room])
	assert_true(need.x <= UiTokens.SIZE_VIEWPORT_W - SettingsSheet.SIDE * 2, "and fits the width")
	for b in sheet.find_children("*", "BaseButton", true, false):
		var size := (b as Control).get_combined_minimum_size()
		assert_true(size.y >= UiTokens.SIZE_TAP_MIN, "%s is tall enough to tap" % b.name)
	holder.free()


## The HUD's buttons are tap-sized, also with Large buttons on.
func test_hud_buttons_are_big_enough() -> void:
	var hud: Hud = load("res://game/ui/hud.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	assert_true(hud._pause_button.custom_minimum_size.x >= UiTokens.SIZE_TAP_MIN, "pause")
	hud.set_large_buttons(true)
	assert_eq(hud._pause_button.custom_minimum_size, Vector2(56, 56), "large pause button")
	for b in hud.find_children("*", "BaseButton", true, false):
		var size := (b as Control).get_combined_minimum_size()
		assert_true(minf(size.x, size.y) >= UiTokens.SIZE_TAP_MIN, "%s is big enough" % b.name)
	hud.free()


func test_rooms_screens_fit() -> void:
	var p := _profile()
	p.record_room_cleared("piston")
	_fits(RoomsScreen.new(p), "rooms")
	for id in ["piston", "pumpkin", "double"]:
		_fits(RoomDetailScreen.new(p, id), "room detail (%s)" % id)


## Regression: the Rooms tabs copied their style before joining the tree and got
## Godot's grey default buttons instead of the Sticker Pop ones.
func test_rooms_tabs_use_the_game_style() -> void:
	var rooms := RoomsScreen.new(_profile())
	(Engine.get_main_loop() as SceneTree).root.add_child(rooms)
	var want := UiTheme.get_theme().get_stylebox("normal", &"TabButton") as StyleBoxFlat
	var tabs := rooms.find_children("*", "Button", true, false)
	var checked := 0
	for b in tabs:
		var tab := b as Button
		if tab.theme_type_variation != &"TabButton":
			continue
		checked += 1
		var have := tab.get_theme_stylebox("normal") as StyleBoxFlat
		assert_true(have != null, "tab has a flat style")
		if have != null:
			assert_eq(have.bg_color, want.bg_color, "tab '%s' is not Godot grey" % tab.text)
	assert_true(checked >= 5, "found the five tabs (%d)" % checked)
	rooms.free()


func test_rooms_list_shows_only_the_selected_tab() -> void:
	var rooms := RoomsScreen.new(_profile())
	(Engine.get_main_loop() as SceneTree).root.add_child(rooms)
	for g in RoomInfo.GROUPS:
		rooms._select_tab(g)
		assert_eq(rooms.selected_group(), g)
		var shown := rooms.visible_cards()
		assert_eq(shown.size(), RoomInfo.rooms_in(g).size(), "only the %s rooms show" % g)
	rooms.free()


## Every leaderboard and state fits, with the name dialog open on top too.
func test_leaderboard_screens_fit() -> void:
	var p := _profile()
	p.leaderboard_name = "TapTapLeo_1234"
	var service := SampleLeaderboard.new(p)
	service.signed_in = true
	service.submit_run(87)
	for id in LeaderboardService.BOARDS:
		var screen := LeaderboardScreen.new(p, service, id)
		_fits(
			screen,
			"leaderboard (%s)" % id,
			func() -> void: screen.show_board(service.build_board(id))
		)
	var empty := LeaderboardBoard.make(LeaderboardService.DAILY)
	empty.resets_in_s = 86000
	var offline := LeaderboardBoard.make(LeaderboardService.DAILY, LeaderboardBoard.Status.OFFLINE)
	var signed_out := LeaderboardBoard.make(
		LeaderboardService.FRIENDS, LeaderboardBoard.Status.SIGNED_OUT
	)
	for b: LeaderboardBoard in [empty, offline, signed_out]:
		var screen := LeaderboardScreen.new(p, service, b.id)
		_fits(screen, "leaderboard state %d" % b.status, func() -> void: screen.show_board(b))
	var loading := LeaderboardScreen.new(p, service)
	_fits(loading, "leaderboard loading")
	var naming := LeaderboardScreen.new(p, service)
	_fits(naming, "leaderboard name dialog", naming.open_name_dialog)


## Every item name fits its tile at the narrowest step ("Jungle Canopy").
func test_item_names_fit_their_tiles() -> void:
	for kind: String in [Catalog.FLYER, Catalog.WORLD, Catalog.TRAIL, Catalog.PORTAL]:
		for id: String in Catalog.ids(kind):
			var l := Label.new()
			l.text = ItemChip.short_name(kind, id)
			ItemCard._fit_name(l, ItemCard.NAME_ROOM)
			var font: Font = l.get_theme_font("font") if l.has_theme_font_override("font") else null
			if font == null:
				font = GameFonts.ui(800)
			var size := (
				l.get_theme_font_size("font_size")
				if l.has_theme_font_size_override("font_size")
				else 14
			)
			var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			assert_true(w <= ItemCard.NAME_ROOM, "%s '%s' is %d px wide" % [kind, l.text, w])
			l.free()


## The five Customize tabs share the bar equally, so none reaches its edge.
func test_customize_tabs_share_the_bar() -> void:
	var shop := CollectionScreen.new(_profile(), CollectionScreen.Mode.SHOP, Catalog.FLYER)
	_fits(shop, "customize tabs", _check_tabs.bind(shop))


func _check_tabs(shop: CollectionScreen) -> void:
	var share := (UiTokens.SIZE_VIEWPORT_W - 28.0 - 6.0) / Catalog.KINDS.size()
	for k: String in Catalog.KINDS:
		var tab := shop._tabs[k] as Button
		assert_true(tab.clip_text, "%s tab has no text minimum" % k)
		var w := GameFonts.ui(800).get_string_size(tab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		assert_true(w + CollectionScreen.TAB_PAD * 2 + 8 <= share, "'%s' fits its tab" % tab.text)


## Game over's stats stay clear of a crashed flyer lying on either wall.
func test_game_over_stats_clear_the_walls() -> void:
	var width := Hud.STAT_W * 3 + Hud.STAT_GAP * 2
	var left := (UiTokens.SIZE_VIEWPORT_W - width) / 2.0
	assert_true(left >= Hud.WALL_CLEAR, "the stats start at %d px" % left)
	var flyer := BirdView.ART_CANVAS * BirdView.ART_SCALE
	assert_true(Hud.WALL_CLEAR >= flyer / 2.0 + 18.0, "a flyer by the wall stays clear")


## The wordmark keeps 24px of room at each side, whatever the game is called.
func test_home_wordmark_fits_the_width() -> void:
	var w := (
		GameFonts
		. display()
		. get_string_size(HomeScreen.WORDMARK, HORIZONTAL_ALIGNMENT_LEFT, -1, HomeScreen.LOGO_SIZE)
		. x
	)
	var room := UiTokens.SIZE_VIEWPORT_W - 48.0
	assert_true(w <= room, "'%s' is %d px wide, room for %d" % [HomeScreen.WORDMARK, w, room])
