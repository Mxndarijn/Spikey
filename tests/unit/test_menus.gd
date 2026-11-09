extends TestCase
## Drives the real app scene headless: first start, home, shop and a run.

const TEST_PATH := "user://test_menus_profile.json"
const HUD_SCENE := "res://game/ui/hud.tscn"


func _make_main() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func test_first_start_goes_straight_home() -> void:
	var main := _make_main()
	assert_true(main._menus.current() is HomeScreen, "no pickers: Home right away")
	var saved := Profile.load_or_new(TEST_PATH)
	assert_true(saved.onboarded, "first start is saved")
	var flyer := Shop.starters(Catalog.FLYER)[0]
	assert_eq(saved.equipped_id(Catalog.FLYER), flyer, "the first free flyer")
	assert_true(saved.owns(Catalog.FLYER, flyer))
	assert_eq(saved.equipped_id(Catalog.WORLD), ThemeCatalog.DEFAULT_ID, "the default world")
	assert_true(saved.owns(Catalog.WORLD, ThemeCatalog.DEFAULT_ID))
	assert_false(main._room.show_score, "no ghost score behind the menus")
	assert_false(main._bird.visible, "Home draws its own big flyer")
	main.start_run()
	assert_eq(main.mode, main.Mode.RUN)
	assert_true(main._bird.visible, "the live flyer plays")
	main._run.request_tap()
	main._run._physics_process(1.0 / 60.0)
	assert_true(main._hud._score.visible, "the score shows at the top while playing")
	assert_false(main._room.show_score, "no ghost score behind the flyer any more")
	assert_true(main._menus.current() == null, "menus close when playing")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## "Tap to flap" has a back arrow to Home; the first flap swaps it for pause.
func test_ready_has_a_back_arrow_home() -> void:
	var main := _make_main()
	main.start_run()
	var hud: Hud = main._hud
	assert_true(hud._back_button.visible, "the back arrow shows before the first flap")
	assert_false(hud._pause_button.visible, "no pause yet")
	assert_eq(hud._back_button.position, hud._pause_button.position, "same corner as pause")
	assert_eq(hud._back_button.tooltip_text, "Home")
	hud._back_button.pressed.emit()
	assert_eq(main.mode, main.Mode.MENU, "back ends the run before it starts")
	assert_true(main._menus.current() is HomeScreen, "back goes Home")
	assert_false(hud._back_button.visible, "no back arrow over the menus")
	main.start_run()
	main._run.request_tap()
	main._run._physics_process(1.0 / 60.0)
	assert_false(hud._back_button.visible, "the first flap hides the back arrow")
	assert_true(hud._pause_button.visible, "and shows pause in its place")
	main._toggle_pause()
	assert_false(hud._back_button.visible, "not on the pause screen")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## Regression: a Button doesn't grow with its children, and the status line
## ("In use") used to hang below the card.
func test_cards_are_tall_enough_for_their_content() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var p := Profile.new()
	p.grant(Catalog.FLYER, "dash")
	p.equip(Catalog.FLYER, "dash")
	var world := ThemeCatalog.default_theme()
	for thumb_height in [ItemCard.THUMB_HEIGHT, 80.0]:
		for kind in Catalog.KINDS:
			var card := ItemCard.new(kind, Catalog.ids(kind)[0], world, thumb_height)
			holder.add_child(card)
			card.refresh(p, true)
			var content: Vector2 = card._box.get_combined_minimum_size()
			var have := card.get_combined_minimum_size()
			assert_true(
				have.y >= content.y + ItemCard.PAD * 2,
				"%s card (%d px picture) fits its content" % [kind, thumb_height]
			)
			assert_true(have.x >= UiTokens.SIZE_TAP_MIN, "%s card is big enough to tap" % kind)
	holder.free()


func test_strip_items_say_in_use_owned_free_or_price() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var p := Profile.new()
	p.grant(Catalog.FLYER, "buzz")
	p.grant(Catalog.FLYER, "dash")
	p.equip(Catalog.FLYER, "buzz")
	var world := ThemeCatalog.default_theme()
	var want := {
		"buzz": "In use",
		"dash": "Owned",
		"nimbus": "Free",
		"ember": str(Shop.price(Catalog.FLYER, "ember")),
	}
	for id: String in want:
		var card := ItemCard.new(Catalog.FLYER, id, world)
		holder.add_child(card)
		card.refresh(p, false)
		assert_eq(card.status_text(), want[id], "%s status" % id)
	holder.free()


func test_home_shows_stats_flyer_and_the_dock() -> void:
	var p := Profile.new()
	p.grant(Catalog.FLYER, "dash")
	p.equip(Catalog.FLYER, "dash")
	p.best_score = 87
	p.coins = 1240
	var home := HomeScreen.new(p, 14)
	home.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(home)
	assert_eq((home.logo() as Label).text, "flapjaw", "the wordmark, one word")
	assert_eq(home.stats_line(), "Best 87, #14 today")
	assert_eq(HomeScreen.stats_text(87, 0), "Best 87", "no rank before today's first run")
	assert_eq(home.flyer().texture, Catalog.flyer("dash").idle, "the flyer in use, big")
	assert_true(home.flyer().art_size() > BirdView.ART_CANVAS * BirdView.ART_SCALE, "bigger")
	var dock := home.dock()
	for id in ["rooms", "style", "play", "rank", "settings"]:
		var b := dock.button(id)
		assert_true(b != null, "the dock has %s" % id)
		if b != null:
			var s := b.get_combined_minimum_size()
			assert_true(minf(s.x, s.y) >= UiTokens.SIZE_TAP_MIN, "%s is big enough to tap" % id)
	assert_eq(dock.button("rank").text, "#14", "today's rank in the dock")
	assert_eq(dock.primary().get_combined_minimum_size(), Vector2(100, 100), "round Play")
	home.set_daily_rank(3)
	assert_eq(home.stats_line(), "Best 87, #3 today")
	assert_eq(dock.button("rank").text, "#3")
	var got: Array[String] = []
	home.play_pressed.connect(func() -> void: got.append("play"))
	home.rooms_pressed.connect(func() -> void: got.append("rooms"))
	home.customize_pressed.connect(func() -> void: got.append("style"))
	home.leaderboard_pressed.connect(func() -> void: got.append("rank"))
	for id in ["play", "rooms", "style", "rank"]:
		dock.button(id).pressed.emit()
	assert_eq(got, ["play", "rooms", "style", "rank"], "each dock item does its job")
	dock.button("settings").pressed.emit()
	assert_true(home.settings() != null, "Settings opens the sheet")
	home.free()


func test_customize_previews_filters_and_merges_the_shop() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz")
	var home := main._menus.current() as HomeScreen
	home.customize_pressed.emit()
	var look := main._menus.current() as LookScreen
	assert_true(look != null, "Style opens Your look")
	if look != null:
		look.card(Catalog.FLYER).pressed.emit()
	var c := main._menus.current() as CollectionScreen
	assert_true(c != null and c.mode == CollectionScreen.Mode.SHOP, "a card opens its list")
	if c == null:
		main.free()
		return
	var ids := c.item_ids()
	var first_shop := -1
	for i in ids.size():
		if not main._profile.owns(Catalog.FLYER, ids[i]):
			first_shop = i
			break
	for i in ids.size():
		var own: bool = main._profile.owns(Catalog.FLYER, ids[i])
		assert_eq(own, i < first_shop or first_shop < 0, "yours first, then the shop (%s)" % ids[i])
	assert_false(c.is_popup_open(), "no popup until you tap")
	c._tap("hoot")
	assert_eq(c.preview_ids(), ["hoot", "sunset", "world_ribbon"], "preview swaps in the tap")
	assert_true(c.is_popup_open(), "tapping opens the item popup")
	c.close_popup()
	assert_false(c.is_popup_open(), "Close dismisses it")
	c._show_kind(Catalog.TRAIL)
	c._tap("comet_tail")
	assert_eq(c.preview_ids(), ["buzz", "sunset", "comet_tail"], "trails too, flyer in use")
	c._tap("world_ribbon")
	assert_eq(c.action_label(), ["In use", false], "the trail in use")
	assert_false(c._action.disabled, "In use still taps")
	c._on_action()
	assert_false(c.is_popup_open(), "In use just closes the popup")
	main._profile.coins = Shop.price(Catalog.TRAIL, "comet_tail")
	c._tap("comet_tail")
	c._on_action()
	assert_true(main._profile.owns(Catalog.TRAIL, "comet_tail"), "the popup buys")
	assert_eq(main._profile.equipped_id(Catalog.TRAIL), "comet_tail", "and puts it on")
	assert_false(c.is_popup_open(), "and closes")
	assert_eq(c.item_ids().find("comet_tail"), 1, "it moves up to Yours")
	c._show_kind(CollectionScreen.HATS)
	assert_eq(c.item_ids(), [], "no hats yet")
	assert_eq(c.action_label(), ["Hats are coming", false])
	main.show_home()
	(main._menus.current() as HomeScreen).shop_pressed.emit(Catalog.FLYER)
	assert_true(main._menus.current() is CollectionScreen, "Shop opens Customize")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_shop_previews_worlds_and_hides_the_live_flyer() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz")
	assert_false(main._bird.visible, "Home draws the flyer itself")
	main.show_shop(Catalog.WORLD)
	var shop := main._menus.current() as CollectionScreen
	assert_false(main._bird.visible, "the shop shows the flyer itself")
	if shop != null:
		shop._select("ice")
		assert_eq(main._room._theme.id, "ice", "the room previews the tapped world")
		assert_eq(main._profile.equipped_id(Catalog.WORLD), "sunset", "a preview is not saved")
		shop.closed.emit()
	assert_eq(main._room._theme.id, "sunset", "the world in use shows again")
	var look := main._menus.current() as LookScreen
	assert_true(look != null, "back to Your look")
	if look != null:
		look.closed.emit()
	assert_true(main._menus.current() is HomeScreen, "and back again to Home")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_shop_buttons_follow_coins_and_ownership() -> void:
	var p := Profile.new()
	p.grant(Catalog.FLYER, "buzz")
	p.equip(Catalog.FLYER, "buzz")
	var shop := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, Catalog.FLYER)
	(Engine.get_main_loop() as SceneTree).root.add_child(shop)
	assert_eq(shop.item_ids(), Catalog.ids(Catalog.FLYER), "shop lists every flyer")
	shop._select("buzz")
	assert_eq(shop.action_label(), ["In use", false])
	shop._select("dash")
	assert_eq(shop.action_label(), ["Get for free", true])
	shop._select("ember")
	var cost := Shop.price(Catalog.FLYER, "ember")
	assert_eq(shop.action_label(), ["Need %d more gold" % cost, false])
	p.coins = cost
	shop.refresh()
	assert_eq(shop.action_label(), ["Unlock for %d" % cost, true])
	shop._on_action()
	assert_true(p.owns(Catalog.FLYER, "ember"), "bought")
	assert_eq(p.equipped_id(Catalog.FLYER), "ember", "and put to use")
	assert_eq(p.coins, 0)
	shop._show_kind(Catalog.WORLD)
	assert_eq(shop.item_ids(), Catalog.ids(Catalog.WORLD), "worlds tab")
	shop.free()


func test_shop_selected_card_is_raised_and_the_one_in_use_ringed() -> void:
	var p := Profile.new()
	p.grant(Catalog.FLYER, "buzz")
	p.equip(Catalog.FLYER, "buzz")
	var shop := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, Catalog.FLYER)
	shop.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(shop)
	assert_eq(shop.caption_text(), "Buzz, in use", "the line under the flyer")
	shop._select("hoot")
	assert_eq(shop.caption_text(), "Hoot", "the tapped flyer's name")
	for card in shop._cards:
		var on := card.item_id == "hoot"
		assert_eq(card.is_selected_look(), on, "%s fill follows the selection" % card.item_id)
		assert_eq(card.is_in_use_look(), card.item_id == "buzz", "%s ring" % card.item_id)
		assert_eq(card.rotation, 0.0, "no card tilts (%s)" % card.item_id)
		assert_true(card.get_parent() == shop._owned_grid, "cards sit straight in the grid")
	shop.free()


func test_only_unaffordable_items_are_faded() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var p := Profile.new()
	p.coins = Shop.price(Catalog.FLYER, "hoot")
	var world := ThemeCatalog.default_theme()
	var hoot := ItemCard.new(Catalog.FLYER, "hoot", world)
	var ember := ItemCard.new(Catalog.FLYER, "ember", world)
	holder.add_child(hoot)
	holder.add_child(ember)
	hoot.refresh(p, false)
	ember.refresh(p, false)
	assert_false(hoot._thumb.dimmed, "affordable item shows in full colour")
	assert_true(ember._thumb.dimmed, "item you can't afford yet is faded")
	holder.free()


func test_game_over_shows_best_stats_and_its_dock() -> void:
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.show_game_over(64, 92, false, 64, 92, 6, 14, 4000000000)
	assert_false(hud.is_new_best_showing(), "no ribbon without a new best")
	assert_true(hud._seed.visible, "the seed shows, for reporting a run")
	assert_eq(hud._seed.text, "Seed 4000000000 · v%d" % SimConfig.GAMEPLAY_VERSION)
	assert_true(hud._seed.offset_top >= hud._stats.offset_bottom, "the seed sits under the stats")
	assert_true(hud._seed.offset_bottom <= 640.0 - Dock.HEIGHT, "and above the dock")
	assert_eq(hud._final_score.text, "64")
	assert_eq(hud._best_score.text, "Best 92")
	assert_eq(
		[hud._stat_coins.text, hud._stat_rooms.text, hud._stat_rank.text],
		["+64", "6", "#14"],
		"coins, rooms cleared, today's rank"
	)
	var dock := hud._dock
	var got: Array[String] = []
	hud.play_again_pressed.connect(func() -> void: got.append("again"))
	hud.home_pressed.connect(func() -> void: got.append("home"))
	hud.rooms_pressed.connect(func() -> void: got.append("rooms"))
	hud.leaderboard_pressed.connect(func() -> void: got.append("rank"))
	hud.style_pressed.connect(func() -> void: got.append("style"))
	for id in ["again", "home", "rooms", "rank", "style"]:
		dock.button(id).pressed.emit()
	assert_eq(got, ["again", "home", "rooms", "rank", "style"], "the Game over dock")
	assert_eq(dock.button("rank").text, "#14")
	hud.set_daily_rank(0)
	assert_eq(hud._stat_rank.text, "-", "no rank yet")
	hud.free()


func test_new_best_counts_up_once_and_stays_still_with_reduced_motion() -> void:
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.show_game_over(92, 92, true, 92, 87, 9, 14)
	assert_true(hud.is_new_best_showing(), "the New best ribbon")
	assert_eq(hud._new_best.ribbon_text(), "New best!")
	assert_eq(hud._best_score.text, "was 87")
	assert_eq(hud._final_score.text, "0", "the score starts counting at 0")
	hud._process(Hud.COUNT_TIME / 2.0)
	var mid := int(hud._final_score.text)
	assert_true(mid > 0 and mid < 92, "half way it is counting (%d)" % mid)
	hud._process(Hud.FX_TIME)
	assert_eq(hud._final_score.text, "92", "it lands on the score")
	assert_eq(NewBestFx.confetti_at(0.0).y, 0.0, "confetti starts hidden")
	assert_eq(NewBestFx.confetti_at(NewBestFx.FALL_TIME).y, 0.0, "and is gone after one fall")
	assert_true(NewBestFx.confetti_at(1.0).y > 0.9, "it shows while falling")
	hud.reduced_motion = true
	hud.show_game_over(95, 95, true, 95, 92, 9, 14)
	assert_eq(hud._final_score.text, "95", "reduced motion: no count-up")
	assert_true(hud._new_best.still, "and no confetti")
	hud.free()


func test_paused_shows_the_score_sound_circles_and_home() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz")
	main.start_run()
	main._run.request_tap()
	main._run._physics_process(1.0 / 60.0)
	main._set_paused(true)
	var hud: Hud = main._hud
	assert_true(hud._paused.visible, "paused")
	assert_true((hud._toggles["music"] as Button).button_pressed, "music is on")
	(hud._toggles["sfx"] as Button).button_pressed = false
	assert_false(main._profile.sfx_on, "the Sounds circle turns sounds off")
	assert_false(Profile.load_or_new(TEST_PATH).sfx_on, "and it is saved")
	assert_true(hud._paused_home.visible, "Home (ends this run)")
	main._set_paused(false)
	assert_false(hud._paused.visible)
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_shop_badges_mark_premium_seasonal_and_fitting_worlds() -> void:
	assert_eq(CollectionScreen.badge_text(Catalog.WORLD, "neon"), "Premium")
	assert_eq(CollectionScreen.badge_text(Catalog.WORLD, "haunted"), "Seasonal: October")
	assert_eq(CollectionScreen.badge_text(Catalog.WORLD, "sunset"), "", "free worlds have none")
	var names: Array[String] = []
	for w in Catalog.flyer("tock").fits_worlds:
		names.append(Catalog.display_name(Catalog.WORLD, w))
	var want := "Fits " + " and ".join(names)
	assert_eq(CollectionScreen.badge_text(Catalog.FLYER, "tock"), want)
	assert_eq(CollectionScreen.badge_text(Catalog.FLYER, "fold"), "", "fits nothing special")


## Puts a flyer in use, as Customize would (first start already gave Sunset Glow).
static func _use_flyer(main: Node, id: String) -> void:
	main._profile.grant(Catalog.FLYER, id)
	main._profile.equip(Catalog.FLYER, id)
	main._load_equipped()
