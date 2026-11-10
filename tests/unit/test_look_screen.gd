extends TestCase
## "Your look": the Customize overview. One card per kind with what is in use;
## a card opens that kind's list and Back returns to the overview.

const TEST_PATH := "user://test_look_profile.json"


func _frames(n: int = 1) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in n:
		await tree.process_frame


func _profile() -> Profile:
	var p := Profile.new()
	p.coins = 1240
	p.grant(ItemKind.FLYER, "nimbus")
	p.equip(ItemKind.FLYER, "nimbus")
	p.grant(ItemKind.WORLD, "sunset")
	p.equip(ItemKind.WORLD, "sunset")
	p.grant(ItemKind.TRAIL, "hearts")
	p.equip(ItemKind.TRAIL, "hearts")
	p.grant(ItemKind.CRASH, "dizzy_stars")
	p.equip(ItemKind.CRASH, "dizzy_stars")
	p.grant(ItemKind.PLATE, "lava_forge")
	p.equip(ItemKind.PLATE, "lava_forge")
	return p


func test_cards_show_what_is_in_use() -> void:
	var look := LookScreen.new(_profile())
	look.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(look)
	assert_eq(look.kinds().size(), ItemKind.ALL.size(), "one card per kind")
	for k in ItemKind.ALL:
		assert_true(k in look.kinds(), "%s is on the overview" % k)
	var want := {
		ItemKind.FLYER: "Nimbus",
		ItemKind.WORLD: "Sunset Glow",
		ItemKind.TRAIL: "Hearts",
		ItemKind.PORTAL: "Match my world",
		ItemKind.MUSIC: "Match my world",
		ItemKind.CRASH: "Dizzy Stars",
		ItemKind.PLATE: "Lava Forge",
	}
	for k: String in want:
		assert_eq(look.card(k).name_text(), want[k], "%s card names the item in use" % k)
	assert_eq(look.card(ItemKind.TRAIL).count_line(), "2 of 20", "the default trail and Hearts")
	assert_eq(look.card(ItemKind.CRASH).count_line(), "2 of 10")
	# Counted from the catalog: new flyers must not break this test.
	assert_eq(
		look.card(ItemKind.FLYER).count_line(), "1 of %d" % Catalog.ids(ItemKind.FLYER).size()
	)
	assert_true(look.card(ItemKind.PLATE).wide, "the name plate is the wide card")
	assert_false(look.card(ItemKind.CRASH).wide)
	assert_eq(look.card(ItemKind.TRAIL).tooltip_text, "Change trail")
	await _frames(2)
	look.free()


func test_a_card_asks_for_its_kind() -> void:
	var look := LookScreen.new(_profile())
	(Engine.get_main_loop() as SceneTree).root.add_child(look)
	var got: Array[String] = []
	look.kind_pressed.connect(func(k: String) -> void: got.append(k))
	for k in look.kinds():
		look.card(k).pressed.emit()
	assert_eq(got, look.kinds(), "each card opens its own kind")
	var closed := [false]
	look.closed.connect(func() -> void: closed[0] = true)
	(look.find_child("Back", true, false) as Button).pressed.emit()
	assert_true(closed[0], "the back arrow closes the overview")
	look.free()


func test_count_text_counts_only_real_items() -> void:
	var p := Profile.new()
	assert_eq(LookCard.count_text(ItemKind.CRASH, p), "1 of 10", "the free default")
	p.grant(ItemKind.CRASH, "not_an_effect")
	assert_eq(LookCard.count_text(ItemKind.CRASH, p), "1 of 10", "unknown ids don't count")
	assert_eq(
		LookCard.count_text(ItemKind.FLYER, p), "0 of %d" % Catalog.ids(ItemKind.FLYER).size()
	)
	assert_eq(LookCard.label_for(ItemKind.PLATE), "Name plate")


## Home -> Style -> Your look -> a card -> its list -> Back -> Your look -> Home,
## and what was put to use in the list shows on the overview.
func test_flow_from_home_and_back() -> void:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main._profile.coins = Shop.price(ItemKind.CRASH, "firework")
	(main._menus.current() as HomeScreen).dock().button("style").pressed.emit()
	var look := main._menus.current() as LookScreen
	assert_true(look != null, "Style opens Your look")
	assert_false(main._bird.visible, "the overview draws the flyer itself")
	look.card(ItemKind.CRASH).pressed.emit()
	var list := main._menus.current() as CollectionScreen
	assert_true(list != null, "the Crash card opens a list")
	assert_eq(list.kind, ItemKind.CRASH)
	assert_eq(list.title_text(), "Crashes", "titled by its kind, no tabs")
	list._tap("firework")
	list._on_action()
	assert_eq(main._profile.equipped_id(ItemKind.CRASH), "firework")
	await _frames(2)
	list.closed.emit()
	look = main._menus.current() as LookScreen
	assert_true(look != null, "Back returns to Your look")
	assert_eq(look.card(ItemKind.CRASH).name_text(), "Firework", "the new pick shows")
	await _frames(2)
	look.closed.emit()
	assert_true(main._menus.current() is HomeScreen, "and Back again goes Home")
	main._hud.style_pressed.emit()
	assert_true(main._menus.current() is LookScreen, "Game over's Style opens it too")
	main.free()
	SafeFile.remove(TEST_PATH)


## Only the world card shows a whole room; a trail, portal, track or crash sits
## on a plain sky so the item itself is what you see.
func test_cards_show_the_item_not_a_room() -> void:
	var p := _profile()
	for k: String in ItemKind.ALL:
		var card := LookCard.new(k, p, ThemeCatalog.default_theme())
		var thumb := card.thumb()
		var want := k in [ItemKind.TRAIL, ItemKind.PORTAL, ItemKind.MUSIC, ItemKind.CRASH]
		assert_eq(thumb.plain, want, "%s card on a plain sky" % k)
		if k == ItemKind.CRASH:
			assert_true(thumb.flyer != null, "the crash bursts round the player's flyer")
		card.free()
