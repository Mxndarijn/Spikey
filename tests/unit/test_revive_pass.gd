extends ScreenFitCase
## The Revive Pass (docs/REVIVE.md): every revive offer is free, the day's
## free revives are left alone, still one revive per run. Bought in the Shop,
## saved with the profile, merged back from the server after a reinstall and
## given back by the store's restore.

const TEST_PATH := "user://test_revive_pass_profile.json"
const SyncTest := preload("res://tests/unit/test_profile_sync.gd")


## Keeps what was sent to the leaderboards.
class SpyBoard:
	extends SampleLeaderboard
	var runs: Array[Dictionary] = []

	func _init() -> void:
		super(Profile.new())

	func submit_run(_score: int, replay: Dictionary = {}) -> void:
		runs.append(replay)


func _make_main(
	board: SpyBoard, ads: AdsService = null, store: StoreService = null, has_pass := false
) -> Node:
	SafeFile.remove(TEST_PATH)
	if has_pass:
		var saved := Profile.new()
		saved.packs_bought.append(DiamondPacks.REVIVE_PASS)
		saved.save(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.leaderboard = board
	main.ads = ads if ads != null else FakeAds.new()
	main.store = store if store != null else SampleStore.new()
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free(main: Node) -> void:
	main.free()
	SafeFile.remove(TEST_PATH)


## Starts a run, gives it `score` points and lets the flyer fall to its death.
static func _crash(main: Node, score: int) -> void:
	main.start_run()
	main._run.request_tap()
	main._run.advance()
	# The falling flyer still bounces once: that point brings it to `score`.
	main._run.sim.state.score = score - 1
	_fall(main)


static func _fall(main: Node) -> void:
	while not main._run.sim.is_over():
		main._run.advance()


static func _tap(main: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)


func test_the_pass_is_a_once_only_product_at_4_99() -> void:
	var pass_item := DiamondPacks.find(DiamondPacks.REVIVE_PASS)
	assert_eq(DiamondPacks.REVIVE_PASS, "revive_pass")
	assert_eq(pass_item.price, "€4.99")
	assert_true(DiamondPacks.is_kept(DiamondPacks.REVIVE_PASS), "non-consumable")
	assert_false(DiamondPacks.is_kept(DiamondPacks.STARTER), "the starter holds diamonds")
	assert_true(DiamondPacks.REVIVE_PASS in DiamondPacks.product_ids(), "the store sells it")
	assert_false(DiamondPacks.REVIVE_PASS in DiamondPacks.ids(), "it is not a diamond pack")
	assert_eq(StoreService.new().price_text(DiamondPacks.REVIVE_PASS), "€4.99")
	var p := Profile.new()
	assert_false(DiamondPacks.has_revive_pass(p))
	assert_true(DiamondPacks.can_buy(p, DiamondPacks.REVIVE_PASS))
	assert_true(DiamondPacks.grant(p, DiamondPacks.REVIVE_PASS))
	assert_true(DiamondPacks.has_revive_pass(p))
	assert_eq([p.diamonds, p.coins], [0, 0], "no diamonds or gold with it")
	assert_false(DiamondPacks.can_buy(p, DiamondPacks.REVIVE_PASS), "bought once")
	assert_false(DiamondPacks.grant(p, DiamondPacks.REVIVE_PASS))
	assert_eq(p.packs_bought, [DiamondPacks.REVIVE_PASS] as Array[String])


func test_the_offer_says_the_pass_pays() -> void:
	var offer := ReviveOffer.new()
	offer.show_offer(47, 0, true)
	assert_true(offer.visible)
	assert_true(offer.is_free(), "no AD pill, even with no free revive left")
	assert_true(offer.shows_pass(), "the PASS pill")
	assert_false(offer.pips_visible(), "the day's count doesn't matter")
	assert_eq(offer.line_text(), ReviveOffer.PASS_LINE)
	assert_eq(offer.note_text(), ReviveOffer.FREE_NOTE)
	assert_eq(offer.score_text(), "47")
	offer.show_offer(47, 2)
	assert_false(offer.shows_pass(), "without the pass")
	assert_true(offer.pips_visible())
	assert_eq(offer.line_text(), "2 free revives left today")
	offer.show_offer(47, 0)
	assert_false(offer.is_free(), "without the pass and free revives: the ad")
	assert_false(offer.shows_pass())
	offer.free()


func test_with_the_pass_a_revive_needs_no_ad_and_keeps_the_free_revives() -> void:
	var board := SpyBoard.new()
	var ads := FakeAds.new()
	var main := _make_main(board, ads, null, true)
	var p: Profile = main._profile
	assert_true(DiamondPacks.has_revive_pass(p))
	_crash(main, 20)
	var offer: ReviveOffer = main._hud.revive_offer
	assert_true(offer.visible, "the offer shows")
	assert_true(offer.shows_pass() and offer.is_free())
	offer.revive_button().pressed.emit()
	assert_eq(ads.shown, 0, "no ad")
	assert_false(main._run.sim.is_over(), "revived")
	assert_eq(main._revive.revived_at, 20)
	assert_eq(p.revives.left(DailyRevives.today()), DailyRevives.PER_DAY, "the day's count is left")
	assert_eq(
		Profile.load_or_new(TEST_PATH).revives.left(DailyRevives.today()),
		DailyRevives.PER_DAY,
		"and nothing spent was saved"
	)
	# Still one revive per run: the second crash ends it.
	_tap(main)
	_fall(main)
	assert_false(offer.visible, "one revive per run")
	assert_true(main._hud.game_over.visible)
	assert_eq(main._hud.game_over._revived_text.text, "Revived at 20")
	assert_eq(board.runs.size(), 1)
	assert_eq(Replay.from_dict(board.runs[0]).revive_ticks.size(), 1, "sent like any revive")
	_free(main)


func test_the_pass_revives_with_no_free_revive_and_no_ad() -> void:
	var main := _make_main(SpyBoard.new(), AdsService.new(), null, true)
	var day := DailyRevives.today()
	while main._profile.revives.use(day):
		pass
	_crash(main, 20)
	var offer: ReviveOffer = main._hud.revive_offer
	assert_true(offer.visible, "the pass alone is enough for an offer")
	assert_true(offer.is_free())
	offer.revive_button().pressed.emit()
	assert_false(main._run.sim.is_over())
	assert_eq(main._profile.revives.left(day), 0)
	_free(main)


func test_without_the_pass_a_revive_still_uses_a_free_one() -> void:
	var ads := FakeAds.new()
	var main := _make_main(SpyBoard.new(), ads)
	_crash(main, 20)
	var offer: ReviveOffer = main._hud.revive_offer
	assert_false(offer.shows_pass())
	offer.revive_button().pressed.emit()
	assert_false(main._run.sim.is_over())
	assert_eq(main._profile.revives.left(DailyRevives.today()), DailyRevives.PER_DAY - 1)
	assert_eq(ads.shown, 0)
	_free(main)


func test_the_pass_keeps_the_low_score_and_practice_rules() -> void:
	var main := _make_main(SpyBoard.new(), FakeAds.new(), null, true)
	_crash(main, ReviveFlow.MIN_SCORE - 1)
	assert_false(main._hud.revive_offer.visible, "no offer below the score")
	assert_true(main._hud.game_over.visible)
	var first: String = RoomCatalog.all()[RoomCatalog.first_index()].id
	main._profile.record_room_met(first)
	main.start_practice(first)
	main._run.request_tap()
	main._run.advance()
	_fall(main)
	assert_false(main._hud.revive_offer.visible, "practice has no revive")
	_free(main)


func test_the_pass_is_bought_in_the_shop_and_shows_owned() -> void:
	var main := _make_main(SpyBoard.new())
	main.show_store()
	var shop := main._menus.current() as StoreScreen
	var buy := shop.price_button(DiamondPacks.REVIVE_PASS)
	assert_eq(buy.text, "€4.99")
	assert_true(buy.visible and not buy.disabled)
	assert_false(shop.pass_owned_visible())
	buy.pressed.emit()
	assert_true(DiamondPacks.has_revive_pass(main._profile))
	assert_true(DiamondPacks.has_revive_pass(Profile.load_or_new(TEST_PATH)), "saved at once")
	assert_true(shop.pass_owned_visible(), "Owned")
	assert_false(buy.visible, "no price any more")
	assert_eq(shop.message_text(), StoreScreen.PASS_BOUGHT)
	assert_eq(main._profile.diamonds, 0, "no diamonds came with it")
	shop.buy(DiamondPacks.REVIVE_PASS)
	assert_eq(main._profile.packs_bought.count(DiamondPacks.REVIVE_PASS), 1, "only once")
	_free(main)


func test_a_closed_store_shows_the_pass_but_cannot_sell_it() -> void:
	var p := Profile.new()
	var shop := StoreScreen.new(Checkout.offline(p), StoreService.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(shop)
	assert_true(shop.price_button(DiamondPacks.REVIVE_PASS).disabled)
	shop.buy(DiamondPacks.REVIVE_PASS)
	assert_false(DiamondPacks.has_revive_pass(p))
	assert_eq(shop.message_text(), StoreService.CLOSED)
	shop.free()


func test_the_shop_fits_with_and_without_the_pass() -> void:
	var fresh := _profile()
	_fits(StoreScreen.new(Checkout.offline(fresh), SampleStore.new()), "shop, pass for sale")
	var owner := _profile()
	owner.packs_bought.append(DiamondPacks.REVIVE_PASS)
	_fits(StoreScreen.new(Checkout.offline(owner), SampleStore.new()), "shop, pass owned")


func test_the_pass_is_saved_and_kept_on_the_server() -> void:
	var p := Profile.new()
	DiamondPacks.grant(p, DiamondPacks.REVIVE_PASS)
	assert_true(p.save(TEST_PATH))
	assert_true(DiamondPacks.has_revive_pass(Profile.load_or_new(TEST_PATH)), "round trip")
	SafeFile.remove(TEST_PATH)
	var cloud := p.cloud_dict()
	assert_true(DiamondPacks.REVIVE_PASS in (cloud.packs_bought as Array), "sent to the server")
	# A reinstall (never synced) gets it back from the server's copy.
	var fresh := Profile.new()
	fresh.merge_cloud(Profile.from_dict(JSON.parse_string(JSON.stringify(cloud))), 4)
	assert_true(DiamondPacks.has_revive_pass(fresh), "back after a reinstall")
	# A phone that synced before, bought nothing, and meets the bought copy.
	var other := Profile.new()
	other.mark_cloud_saved(2, 0)
	other.packs_bought.append("handful")
	other.merge_cloud(Profile.from_dict(cloud), 5)
	assert_true(DiamondPacks.has_revive_pass(other), "bought packs join")
	assert_true("handful" in other.packs_bought)
	# The server's copy without it never takes it away.
	var owner := Profile.new()
	owner.mark_cloud_saved(3, 0)
	DiamondPacks.grant(owner, DiamondPacks.REVIVE_PASS)
	owner.merge_cloud(Profile.new(), 6)
	assert_true(DiamondPacks.has_revive_pass(owner), "a merge never drops it")


func test_a_reinstalled_phone_gets_the_pass_through_the_sync() -> void:
	var server := SyncTest.FakeServer.new()
	var bought := Profile.new()
	DiamondPacks.grant(bought, DiamondPacks.REVIVE_PASS)
	await ProfileSync.new(bought, server).push()
	assert_eq(server.revision, 1)
	var fresh := Profile.new()
	var merged: Array[bool] = []
	var sync := ProfileSync.new(fresh, server)
	sync.synced.connect(func(m: bool) -> void: merged.append(m))
	await sync.push()
	assert_eq(merged, [true] as Array[bool], "the server's copy came in")
	assert_true(DiamondPacks.has_revive_pass(fresh), "with the pass")
	assert_true(fresh.cloud_revision >= 1)


func test_restore_hands_back_only_kept_products() -> void:
	var p := Profile.new()
	var ids: Array[String] = [DiamondPacks.STARTER, "handful", DiamondPacks.REVIVE_PASS, "nope"]
	assert_eq(DiamondPacks.restore(p, ids), [DiamondPacks.REVIVE_PASS] as Array[String])
	assert_true(DiamondPacks.has_revive_pass(p))
	assert_eq([p.diamonds, p.coins], [0, 0], "no pack of diamonds again")
	assert_eq(DiamondPacks.restore(p, ids), [] as Array[String], "nothing twice")
	var store := SampleStore.new()
	var got: Array = []
	store.restored.connect(func(r: Array[String]) -> void: got.append(r))
	store.buy("handful")
	store.buy(DiamondPacks.REVIVE_PASS)
	store.restore()
	assert_eq(got, [[DiamondPacks.REVIVE_PASS] as Array[String]], "the pretend store keeps it")
	var closed := StoreService.new()
	var failed: Array = []
	closed.failed.connect(func(id: String, why: String) -> void: failed.append([id, why]))
	closed.restore()
	assert_eq(failed, [["", StoreService.CLOSED]])


func test_restore_in_the_shop_gives_the_pass_back() -> void:
	var store := SampleStore.new()
	store.kept.append(DiamondPacks.REVIVE_PASS)
	var main := _make_main(SpyBoard.new(), null, store)
	main.show_store()
	var shop := main._menus.current() as StoreScreen
	var link := shop.restore_button()
	assert_true(link.visible, "Restore shows while the pass isn't owned")
	link.pressed.emit()
	assert_true(DiamondPacks.has_revive_pass(main._profile), "handed back")
	assert_true(DiamondPacks.has_revive_pass(Profile.load_or_new(TEST_PATH)), "and saved")
	assert_eq(shop.message_text(), StoreScreen.RESTORED)
	assert_true(shop.pass_owned_visible(), "Owned")
	assert_false(link.visible, "no Restore once it is owned")
	assert_eq(main._profile.diamonds, 0)
	_free(main)


func test_restore_says_when_there_is_nothing() -> void:
	var main := _make_main(SpyBoard.new())
	main.show_store()
	var shop := main._menus.current() as StoreScreen
	shop.restore()
	assert_eq(shop.message_text(), StoreScreen.NOTHING_RESTORED)
	assert_false(DiamondPacks.has_revive_pass(main._profile))
	assert_true(shop.restore_button().visible, "it can be asked again")
	_free(main)
	var p := Profile.new()
	var closed := StoreScreen.new(Checkout.offline(p), StoreService.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(closed)
	assert_false(closed.restore_button().visible, "a closed store has nothing to restore")
	closed.free()
