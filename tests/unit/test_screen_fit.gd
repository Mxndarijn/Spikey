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


## The home wordmark must end above the flyer, which bobs at the start height.
func test_home_logo_clears_the_flyer() -> void:
	var home := HomeScreen.new(_profile())
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	holder.add_child(home)
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Headless runs don't lay containers out, so add the logo's position up
	# from minimum sizes: top margin, the pill row, one gap, then the logo.
	var logo := home.logo()
	var col := logo.get_parent() as VBoxContainer
	var margin := col.get_parent() as MarginContainer
	var bottom := (
		margin.get_theme_constant("margin_top")
		+ (col.get_child(0) as Control).get_combined_minimum_size().y
		+ col.get_theme_constant("separation")
		+ logo.get_combined_minimum_size().y
	)
	var flyer_top := (
		SimConfig.BIRD_START_Y / float(SimConfig.SUB)
		- BirdView.ART_CANVAS * BirdView.ART_SCALE / 2.0
	)
	assert_true(
		bottom <= flyer_top + 8.0,
		"logo ends at %d px, the flyer starts at %d px" % [bottom, flyer_top]
	)
	holder.free()


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
