extends ScreenFitCase
## Every menu screen must fit the 360 x 640 play area with room left for the
## floor spikes, so no button ends up off screen or behind the spikes.

const FLOOR_CLEARANCE := 40.0


func test_shop_fits_on_every_tab() -> void:
	for kind: String in ItemKind.ALL + [ItemOffer.HATS]:
		var shop := CollectionScreen.new(
			Checkout.offline(_profile()), CollectionScreen.Mode.SHOP, kind
		)
		_fits(shop, "shop (%s)" % kind)


func test_home_fits() -> void:
	_fits(HomeScreen.new(_profile(), AppServices.offline(_profile())), "home")


## Home stacks the wordmark, the stats line, the big flyer and the dock with
## no overlaps, all above the floor spikes.
func test_home_logo_clears_the_flyer() -> void:
	var home := HomeScreen.new(_profile(), AppServices.offline(_profile()))
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
	var sheet := SettingsSheet.new(_profile(), AppServices.offline(_profile()))
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
	UiKit.large_buttons = true
	hud.refresh_button_size()
	UiKit.large_buttons = false
	assert_eq(hud._pause_button.custom_minimum_size, Vector2(56, 56), "large pause button")
	for b in hud.find_children("*", "BaseButton", true, false):
		var size := (b as Control).get_combined_minimum_size()
		assert_true(minf(size.x, size.y) >= UiTokens.SIZE_TAP_MIN, "%s is big enough" % b.name)
	hud.free()


func test_rooms_screens_fit() -> void:
	var p := _profile()
	p.record_room_cleared("piston")
	_fits(RoomsScreen.new(p), "rooms")
	for g in RoomInfo.GROUPS:
		_fits(RoomsScreen.new(p, g), "rooms (%s)" % g)
	for id in ["piston", "pumpkin", "beams"]:
		_fits(RoomDetailScreen.new(p, id), "room detail (%s)" % id)


## Rooms opens on a card per group; each group opens on its own rooms only.
func test_rooms_open_on_groups_then_one_group() -> void:
	var rooms := RoomsScreen.new(_profile())
	(Engine.get_main_loop() as SceneTree).root.add_child(rooms)
	assert_eq(rooms.group(), "")
	assert_eq(rooms.cards().size(), 0, "no room cards before a group is picked")
	var groups: Array[String] = []
	for card in rooms.group_cards():
		groups.append(card.group)
	assert_eq(groups, RoomInfo.GROUPS, "a card per group, in order")
	var opened: Array[String] = []
	rooms.group_opened.connect(func(g: String) -> void: opened.append(g))
	rooms.group_cards()[1].pressed.emit()
	assert_eq(opened, [RoomInfo.GROUPS[1]], "a card opens its group")
	rooms.free()
	for g in RoomInfo.GROUPS:
		var one := RoomsScreen.new(_profile(), g)
		(Engine.get_main_loop() as SceneTree).root.add_child(one)
		assert_eq(one.cards().size(), RoomInfo.rooms_in(g).size(), "only the %s rooms" % g)
		assert_eq(one.find_child("Title", true, false).text, RoomInfo.GROUP_NAMES[g])
		one.free()


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
	for kind: String in [
		ItemKind.FLYER,
		ItemKind.WORLD,
		ItemKind.TRAIL,
		ItemKind.PORTAL,
		ItemKind.CRASH,
		ItemKind.PLATE
	]:
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


## "Your look" fits with a card for every kind, each big enough to tap, whatever
## is in use (long names wrap inside their card).
func test_your_look_fits_with_every_card() -> void:
	var p := _profile()
	p.grant(ItemKind.WORLD, "jungle")
	p.equip(ItemKind.WORLD, "jungle")
	p.equip(ItemKind.MUSIC, MusicTrack.MATCH_WORLD)
	p.grant(ItemKind.CRASH, "pixel_dissolve")
	p.equip(ItemKind.CRASH, "pixel_dissolve")
	var look := LookScreen.new(p)
	_fits(look, "your look", _check_look.bind(look))


func _check_look(look: LookScreen) -> void:
	assert_eq(look.kinds().size(), ItemKind.ALL.size(), "a card for every kind")
	for k: String in ItemKind.ALL:
		var c := look.card(k)
		assert_true(c != null, "%s has a card" % k)
		if c == null:
			continue
		var need := c.get_combined_minimum_size()
		assert_true(minf(need.x, need.y) >= UiTokens.SIZE_TAP_MIN, "%s card is tap-sized" % k)
	var pair := LookCard.new(ItemKind.MUSIC, _profile(), ThemeCatalog.default_theme())
	var room := (UiTokens.SIZE_VIEWPORT_W - LookScreen.SIDE * 2 - LookScreen.GRID_GAP) / 2.0
	look.add_child(pair)
	assert_true(pair.get_combined_minimum_size().x <= room, "two cards fit side by side")
	pair.free()


## A kind's list has no tabs: its title names the kind.
func test_lists_are_titled_by_kind() -> void:
	for kind: String in ItemKind.ALL:
		var shop := CollectionScreen.new(
			Checkout.offline(_profile()), CollectionScreen.Mode.SHOP, kind
		)
		_fits(
			shop,
			"list title (%s)" % kind,
			func() -> void: assert_eq(shop.title_text(), CollectionScreen.title_for(kind))
		)
		assert_ne(CollectionScreen.title_for(kind), "Customize", "%s has its own title" % kind)


## Game over's stats stay clear of a crashed flyer lying on either wall.
func test_game_over_stats_clear_the_walls() -> void:
	var width := GameOverScreen.STAT_W * 3 + GameOverScreen.STAT_GAP * 2
	var left := (UiTokens.SIZE_VIEWPORT_W - width) / 2.0
	assert_true(left >= GameOverScreen.WALL_CLEAR, "the stats start at %d px" % left)
	var flyer := BirdView.ART_CANVAS * BirdView.ART_SCALE
	assert_true(GameOverScreen.WALL_CLEAR >= flyer / 2.0 + 18.0, "a flyer by the wall stays clear")


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
