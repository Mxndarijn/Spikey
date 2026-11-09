extends TestCase
## Gold and diamonds: the rules (Economy, DiamondPacks, Shop's premium line),
## the save, the stores, and the screens that use them (Shop, convert sheet,
## Customize, the wallet on Home).

const TEST_PATH := "user://test_economy_profile.json"


func _make_main() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _in_tree(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


func test_daily_prizes_pay_the_top_ten() -> void:
	assert_eq(Economy.daily_prize(1), 3)
	assert_eq(Economy.daily_prize(2), 2)
	assert_eq(Economy.daily_prize(3), 2)
	assert_eq(Economy.daily_prize(4), 1)
	assert_eq(Economy.daily_prize(10), 1)
	assert_eq(Economy.daily_prize(11), 0, "outside the top 10")
	assert_eq(Economy.daily_prize(0), 0, "no rank")
	var total := 0
	for rank in range(1, 11):
		total += Economy.daily_prize(rank)
	assert_eq(total, 14, "14 diamonds a day in the whole game")


func test_diamonds_to_cover_rounds_up() -> void:
	assert_eq(Economy.diamonds_to_cover(0), 0)
	assert_eq(Economy.diamonds_to_cover(-5), 0)
	assert_eq(Economy.diamonds_to_cover(1), 1)
	assert_eq(Economy.diamonds_to_cover(100), 1)
	assert_eq(Economy.diamonds_to_cover(101), 2)
	assert_eq(Economy.diamonds_to_cover(160), 2)


func test_convert_is_one_way_and_exact() -> void:
	var p := Profile.new()
	p.diamonds = 3
	p.coins = 40
	assert_eq(Economy.convert(p, 0), Economy.Result.BAD_AMOUNT)
	assert_eq(Economy.convert(p, -2), Economy.Result.BAD_AMOUNT)
	assert_eq(Economy.convert(p, 4), Economy.Result.NOT_ENOUGH_DIAMONDS)
	assert_eq([p.diamonds, p.coins], [3, 40], "a refused conversion changes nothing")
	assert_eq(Economy.convert(p, 2), Economy.Result.OK)
	assert_eq([p.diamonds, p.coins], [1, 240], "2 diamonds became 200 gold")


func test_diamonds_and_packs_are_saved() -> void:
	var p := Profile.new()
	p.diamonds = 7
	p.packs_bought.append(DiamondPacks.STARTER)
	assert_true(p.save(TEST_PATH))
	var back := Profile.load_or_new(TEST_PATH)
	assert_eq(back.diamonds, 7)
	assert_eq(back.packs_bought, [DiamondPacks.STARTER] as Array[String])
	DirAccess.remove_absolute(TEST_PATH)
	var old := Profile.from_dict({"version": 2, "coins": 50})
	assert_eq(old.diamonds, 0, "older saves load with no diamonds")
	assert_eq(old.coins, 50)
	var bad := Profile.from_dict({"diamonds": -4, "packs_bought": [3, "vault", "vault"]})
	assert_eq(bad.diamonds, 0)
	assert_eq(bad.packs_bought, ["vault"] as Array[String])


func test_packs_grant_diamonds_and_the_starter_only_once() -> void:
	var p := Profile.new()
	assert_true(DiamondPacks.grant(p, "handful"))
	assert_eq(p.diamonds, 10)
	assert_true(DiamondPacks.grant(p, "handful"), "normal packs can be bought again")
	assert_eq(p.diamonds, 20)
	assert_true(DiamondPacks.grant(p, DiamondPacks.STARTER))
	assert_eq([p.diamonds, p.coins], [40, 500], "the starter adds 20 diamonds and 500 gold")
	assert_false(DiamondPacks.can_buy(p, DiamondPacks.STARTER))
	assert_false(DiamondPacks.grant(p, DiamondPacks.STARTER), "only once")
	assert_eq([p.diamonds, p.coins], [40, 500])
	assert_false(DiamondPacks.grant(p, "nope"), "unknown pack")
	for id in DiamondPacks.ids():
		var pack := DiamondPacks.find(id)
		assert_true(int(pack.diamonds) > 0, "%s holds diamonds" % id)
		assert_false(str(pack.price).is_empty(), "%s shows a price" % id)


## A bigger pack is never a worse deal per diamond than a smaller one.
func test_bigger_packs_are_better_value() -> void:
	var cents := {"handful": 99, "pouch": 499, "chest": 999, "vault": 1999}
	var last := 0.0
	for id: String in ["handful", "pouch", "chest", "vault"]:
		var per_euro := float(DiamondPacks.find(id).diamonds) / float(cents[id])
		assert_true(per_euro >= last, "%s is at least as good as the pack before" % id)
		last = per_euro


func test_premium_worlds_sell_for_diamonds() -> void:
	for w in Catalog.worlds():
		var gems := Shop.diamond_price(Catalog.WORLD, w.id)
		if not w.premium:
			assert_eq(gems, 0, "%s sells for gold" % w.id)
		elif w.season.is_empty():
			assert_eq(gems, Shop.DIAMOND_WORLD, "%s is a premium world" % w.id)
		else:
			assert_eq(gems, Shop.DIAMOND_SEASONAL, "%s is a seasonal world" % w.id)
	assert_eq(Shop.diamond_price(Catalog.WORLD, "neon"), 30)
	assert_eq(Shop.diamond_price(Catalog.WORLD, "haunted"), 25)
	assert_eq(Shop.diamond_price(Catalog.FLYER, "ember"), 0)
	assert_eq(Shop.cost(Catalog.FLYER, "ember"), Shop.price(Catalog.FLYER, "ember"))
	assert_eq(Shop.cost(Catalog.WORLD, "neon"), 30)
	for kind in Catalog.KINDS:
		for id in Catalog.ids(kind):
			assert_true(Shop.cost(kind, id) >= 0, "%s %s is for sale" % [kind, id])


func test_buying_a_premium_item_spends_diamonds_only() -> void:
	var p := Profile.new()
	p.coins = 5000
	assert_false(Shop.can_afford(p, Catalog.WORLD, "neon"), "gold doesn't buy it")
	assert_eq(Shop.buy(p, Catalog.WORLD, "neon"), Shop.Result.NOT_ENOUGH_DIAMONDS)
	p.diamonds = 32
	assert_true(Shop.can_afford(p, Catalog.WORLD, "neon"))
	assert_eq(Shop.buy(p, Catalog.WORLD, "neon"), Shop.Result.OK)
	assert_eq([p.diamonds, p.coins], [2, 5000], "30 diamonds, no gold")
	assert_true(p.owns(Catalog.WORLD, "neon"))
	assert_eq(Shop.buy(p, Catalog.WORLD, "neon"), Shop.Result.ALREADY_OWNED)


func test_closed_store_fails_and_sample_store_pays() -> void:
	var closed := StoreService.new()
	var got: Array = []
	closed.failed.connect(func(id: String, reason: String) -> void: got.append([id, reason]))
	closed.purchased.connect(func(id: String) -> void: got.append(id))
	assert_false(closed.is_open())
	closed.buy("handful")
	assert_eq(got, [["handful", StoreService.CLOSED]])
	assert_eq(closed.price_text("handful"), "€0.99")
	var sample := SampleStore.new()
	var paid: Array = []
	sample.purchased.connect(func(id: String) -> void: paid.append(id))
	sample.failed.connect(func(id: String, _reason: String) -> void: paid.append("failed " + id))
	assert_true(sample.is_open())
	sample.buy("pouch")
	sample.buy("nope")
	assert_eq(paid, ["pouch", "failed nope"])


func test_home_wallet_opens_the_shop_and_packs_are_granted() -> void:
	var main := _make_main()
	var home := main._menus.current() as HomeScreen
	assert_eq([home.wallet().gold_text(), home.wallet().diamonds_text()], ["0", "0"])
	home.wallet().pressed.emit()
	var shop := main._menus.current() as StoreScreen
	assert_true(shop != null, "the wallet opens the Shop")
	assert_true(shop.starter_visible(), "the starter pack is offered")
	assert_eq(shop.price_button("vault").text, "€19.99")
	assert_eq(shop.message_text(), StoreScreen.LOOKS_ONLY)
	assert_false(shop.price_button("vault").disabled, "an open store sells")
	shop.price_button("handful").pressed.emit()
	assert_eq(main._profile.diamonds, 10, "the pack arrived")
	assert_eq(shop.wallet().diamonds_text(), "10")
	assert_eq(Profile.load_or_new(TEST_PATH).diamonds, 10, "and was saved at once")
	shop.buy(DiamondPacks.STARTER)
	assert_eq([main._profile.diamonds, main._profile.coins], [30, 500])
	assert_false(shop.starter_visible(), "the starter pack is gone once bought")
	shop.buy(DiamondPacks.STARTER)
	assert_eq(main._profile.diamonds, 30, "it can't be bought twice")
	var sheet := shop.open_convert()
	assert_eq(sheet.amount(), 1)
	sheet.step(2)
	assert_eq(sheet.convert_text(), "Convert 3 diamonds")
	assert_eq(sheet.becomes_text(), "Becomes 300 gold")
	sheet.confirm()
	assert_eq([main._profile.diamonds, main._profile.coins], [27, 800])
	assert_eq(shop.wallet().gold_text(), "800")
	assert_eq(Profile.load_or_new(TEST_PATH).coins, 800, "a conversion is saved")
	shop.closed.emit()
	assert_true(main._menus.current() is HomeScreen, "back goes Home")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_a_closed_store_says_why_and_grants_nothing() -> void:
	var p := Profile.new()
	var shop := StoreScreen.new(p, StoreService.new())
	_in_tree(shop)
	assert_eq(shop.message_text(), StoreService.CLOSED, "it says why from the start")
	assert_eq(shop.price_button("chest").text, "€9.99", "the packs still show their price")
	for id in DiamondPacks.ids():
		assert_true(shop.price_button(id).disabled, "%s can't be bought" % id)
	shop.buy("chest")
	assert_eq(p.diamonds, 0)
	assert_eq(shop.message_text(), StoreService.CLOSED)
	p.diamonds = 2
	shop.refresh()
	shop.open_convert().confirm()
	assert_eq([p.diamonds, p.coins], [1, 100], "turning diamonds into gold still works")
	shop.free()


func test_convert_sheet_stays_within_the_wallet() -> void:
	var p := Profile.new()
	var empty := ConvertSheet.new(p, 2)
	_in_tree(empty)
	assert_eq(empty.amount(), 0)
	assert_false(empty.can_convert(), "nothing to convert")
	assert_eq(empty.convert_text(), "No diamonds yet")
	empty.confirm()
	assert_eq(p.coins, 0)
	empty.free()
	p.diamonds = 3
	var sheet := ConvertSheet.new(p, 9)
	_in_tree(sheet)
	assert_eq(sheet.amount(), 3, "never more than the player has")
	sheet.step(-5)
	assert_eq(sheet.amount(), 1, "never less than one")
	assert_eq(sheet.convert_text(), "Convert 1 diamond")
	var done: Array = []
	sheet.converted.connect(func(n: int) -> void: done.append(n))
	sheet.confirm()
	assert_eq(done, [1])
	assert_eq([p.diamonds, p.coins], [2, 100])
	sheet.free()


func test_customize_offers_to_convert_when_gold_is_short() -> void:
	var main := _make_main()
	main.show_shop(Catalog.FLYER)
	var c := main._menus.current() as CollectionScreen
	var cost := Shop.price(Catalog.FLYER, "ember")
	main._profile.coins = cost - 160
	c._tap("ember")
	assert_eq(c.action_label(), ["Need 160 more gold", false], "no diamonds: as before")
	main._profile.diamonds = 5
	c.refresh()
	assert_eq(c.action_label(), [CollectionScreen.CONVERT_LABEL, true])
	c._on_action()
	var sheet := c.sheet()
	assert_true(sheet != null, "the action opens the convert sheet")
	assert_false(main._profile.owns(Catalog.FLYER, "ember"), "nothing is bought yet")
	assert_eq(sheet.amount(), 2, "the fewest diamonds that cover 160 gold")
	sheet.confirm()
	assert_eq([main._profile.diamonds, main._profile.coins], [3, cost + 40])
	assert_eq(Profile.load_or_new(TEST_PATH).diamonds, 3, "saved")
	assert_eq(c.action_label(), ["Unlock for %d" % cost, true], "now it can be bought")
	c._on_action()
	assert_true(main._profile.owns(Catalog.FLYER, "ember"))
	assert_eq(main._profile.coins, 40)
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_customize_sells_premium_worlds_for_diamonds() -> void:
	var main := _make_main()
	main._profile.coins = 9000
	main.show_shop(Catalog.WORLD)
	var c := main._menus.current() as CollectionScreen
	c._tap("neon")
	assert_eq(c.action_label(), ["Need 30 more diamonds", false], "gold doesn't count")
	var card: ItemCard
	for candidate in c._cards:
		if candidate.item_id == "neon":
			card = candidate
	assert_eq(card.status_text(), "30", "the tile shows the diamond price")
	main._profile.diamonds = 31
	c.refresh()
	assert_eq(c.action_label(), ["Unlock for 30", true])
	c._on_action()
	assert_true(main._profile.owns(Catalog.WORLD, "neon"))
	assert_eq([main._profile.diamonds, main._profile.coins], [1, 9000])
	c._wallet.pressed.emit()
	var shop := main._menus.current() as StoreScreen
	assert_true(shop != null, "the wallet in Customize opens the Shop")
	shop.closed.emit()
	var back := main._menus.current() as CollectionScreen
	assert_true(back != null and back.kind == Catalog.WORLD, "back returns to the same tab")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)
