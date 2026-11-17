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


## Home stacks the wordmark, the flyer, the Play bar, the battles pill and the
## bottom bar top to bottom with no overlaps, all clear of the spike rows.
func test_home_stacks_without_overlaps() -> void:
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
	assert_true(logo_bottom <= flyer_top, "the wordmark ends above the flyer (%d px)" % flyer_top)
	assert_true(
		flyer_bottom <= HomeScreen.PLAY_BAR_TOP, "the flyer ends above Play (%d)" % flyer_bottom
	)
	assert_true(HomeScreen.PLAY_BAR_TOP + HomeScreen.PLAY_BAR_H <= HomeScreen.BAR_PILL_TOP)
	assert_true(
		HomeScreen.BAR_PILL_TOP + BattlesPill.HEIGHT <= HomeScreen.BAR_TOP, "pill above the bar"
	)
	var floor_top := float(SimConfig.KILL_BOTTOM) / SimConfig.SUB
	assert_true(HomeScreen.BAR_TOP + HomeBar.HEIGHT + 16.0 <= floor_top, "the bar clears the floor")
	assert_true(
		HomeScreen.CORNER_TOP >= float(SimConfig.KILL_TOP) / SimConfig.SUB + 16.0,
		"the corners clear the ceiling"
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


## Home with everything at its biggest: a six-figure wallet, a long lost-spot
## line, every battle waiting, Battle and Duel waiting for an update, and Large
## buttons on. It still fits the narrowest phone (LayoutQa checks the rest).
func test_home_fits_at_its_fullest() -> void:
	GameModes.battle_enabled = true
	var p := _profile()
	p.coins = 987654
	p.diamonds = 99999
	p.best_score = 9999
	UiKit.large_buttons = true
	GameModes.set_server_version(SimConfig.GAMEPLAY_VERSION + 1)
	var home := HomeScreen.new(p, AppServices.offline(p), 12345)
	var info := DailyRunInfo.new()
	info.resets_in_s = 86399
	var fill := func(h: HomeScreen) -> void:
		h.set_daily_info(info)
		h.set_battle_turns(12)
		h.show_notice("Kofi_the_great took your #3 spot on today's board")
	_fits(home, "home at its fullest", fill.bind(home))
	GameModes.set_server_version(0)
	UiKit.large_buttons = false


## The Battle, Duel and Wins screens' cards keep only the room their content
## needs: a short message leaves no empty paper under it.
func test_cards_shrink_to_their_content() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var duel := DuelScreen.new()
	holder.add_child(duel)
	duel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	duel.show_start()
	for i in 3:
		await (Engine.get_main_loop() as SceneTree).process_frame
	var card := duel.find_child("Card", true, false) as Control
	var tall := card.size.y
	duel.show_countdown(2, "Mira", 1, 0, 3)
	for i in 3:
		await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(card.size.y < tall, "the countdown card is shorter than the start's")
	var need := card.get_combined_minimum_size().y
	assert_true(card.size.y <= need + 1.0, "no empty paper (%d of %d px)" % [card.size.y, need])
	holder.free()
