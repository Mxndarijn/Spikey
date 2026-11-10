extends TestCase
## Diamonds on the server: the wallet services, the daily prize popup on Home,
## and the migration the game's calls have to agree with.

const TEST_PATH := "user://test_wallet_profile.json"
const MIGRATION := "res://supabase/migrations/20261110100000_diamonds.sql"


## A wallet that answers like the server would, without one.
class FakeWallet:
	extends WalletService
	var prizes: Array = []
	var online := true
	var refuse := false
	var spends: Array = []

	func is_online() -> bool:
		return online

	func sync() -> void:
		synced.emit(_profile.diamonds, prizes)

	func spend(amount: int, reason: String, ref: String = "") -> bool:
		if refuse or _profile.diamonds < amount:
			return false
		spends.append([amount, reason, ref])
		_profile.diamonds -= amount
		return true

	func claim() -> int:
		if refuse:
			return 0
		var won := 0
		for p: Dictionary in prizes:
			won += int(p.diamonds)
		prizes = []
		_profile.diamonds += won
		return won


func _make_main(wallet: WalletService = null, profile: Profile = null) -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	if profile != null:
		profile.save(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	if wallet != null:
		main.wallet = wallet
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _in_tree(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


func _prize(day: String, rank: int) -> Dictionary:
	return {"day": day, "rank": rank, "score": 80, "diamonds": Economy.daily_prize(rank)}


func test_local_wallet_spends_from_the_save() -> void:
	var p := Profile.new()
	p.diamonds = 5
	var w := WalletService.new(p)
	assert_false(w.is_online())
	assert_false(w.spend(6, WalletService.ITEM), "not enough")
	assert_false(w.spend(0, WalletService.ITEM), "nothing to spend")
	assert_eq(p.diamonds, 5)
	assert_true(w.spend(2, WalletService.CONVERT))
	assert_eq(p.diamonds, 3)
	assert_eq(w.claim(), 0, "no daily prizes without a server")
	var got: Array = []
	w.synced.connect(func(d: int, prizes: Array) -> void: got.append([d, prizes]))
	w.sync()
	assert_eq(got, [[3, []]])


func test_reads_the_server_wallet() -> void:
	var w := (
		SupabaseWallet
		. parse_wallet(
			{
				"diamonds": 7.0,
				"prizes":
				[
					{"day": "2026-11-09", "rank": 2.0, "score": 87.0, "diamonds": 2.0},
					{"day": "2026-11-08", "rank": 0, "diamonds": 1},
					"junk",
				]
			}
		)
	)
	assert_eq(w.diamonds, 7)
	assert_eq(
		w.prizes, [{"kind": "daily", "day": "2026-11-09", "rank": 2, "score": 87, "diamonds": 2}]
	)
	var mixed := (
		SupabaseWallet
		. parse_wallet(
			{
				"diamonds": 0,
				"bonuses":
				[
					{"kind": "milestone", "ref": "50", "diamonds": 1.0},
					{"kind": "streak", "ref": "2026-11-09", "diamonds": 1},
					{"kind": "gift", "ref": "x", "diamonds": 99},
					{"kind": "streak", "ref": "2026-11-02", "diamonds": 0},
				]
			}
		)
	)
	assert_eq(
		mixed.prizes,
		[
			{"kind": "milestone", "ref": "50", "diamonds": 1},
			{"kind": "streak", "ref": "2026-11-09", "diamonds": 1},
		],
		"only the kinds the game knows, and only ones that pay"
	)
	assert_eq(SupabaseWallet.parse_wallet(null), {}, "no answer")
	assert_eq(SupabaseWallet.parse_wallet({"message": "not found"}), {}, "not a wallet")
	assert_eq(SupabaseWallet.parse_wallet({"diamonds": -3}).diamonds, 0)
	assert_eq(
		SupabaseWallet.spend_body(30, WalletService.ITEM, "world:neon"),
		{"p_amount": 30, "p_reason": "item", "p_ref": "world:neon"}
	)


## The game calls three functions; the migration has to offer exactly those,
## pay the same prizes as Economy, and keep the tables shut.
func test_migration_matches_the_game() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	for fn in ["get_wallet()", "claim_prizes()", "spend_diamonds(integer, text, text)"]:
		assert_true(
			sql.contains("grant execute on function public.%s to authenticated" % fn),
			"the game may call %s" % fn
		)
		assert_true(
			sql.contains("revoke all on function public.%s from public, anon" % fn),
			"%s needs a signed-in player" % fn
		)
	for fn in ["spikey_settle_days()", "spikey_daily_prize(integer)", "spikey_award_bonuses(uuid)"]:
		assert_true(
			sql.contains("revoke all on function public.%s from public, anon, authenticated" % fn),
			"%s is not callable by the game" % fn
		)
	assert_true(
		sql.contains("spikey_change_diamonds(uuid, integer, text, text)\n  from public, anon"),
		"the game can't add diamonds itself"
	)
	for table in ["wallets", "diamond_ledger", "daily_prizes", "settled_days", "bonus_prizes"]:
		assert_true(
			sql.contains("alter table public.%s enable row level security" % table),
			"%s is locked" % table
		)
	assert_false(sql.contains("create policy"), "no direct access to the tables")
	assert_true(sql.contains("check (diamonds >= 0)"), "a balance never goes below zero")
	assert_true(sql.contains("r.status = 'ok'"), "only checked runs win prizes")
	# The prize table, in the migration's own words.
	assert_eq(Economy.DAILY_PRIZES, [3, 2, 2, 1, 1, 1, 1, 1, 1, 1] as Array[int])
	assert_true(sql.contains("when p_rank = 1 then 3"))
	assert_true(sql.contains("when p_rank in (2, 3) then 2"))
	assert_true(sql.contains("when p_rank between 4 and 10 then 1"))
	for reason: String in [WalletService.ITEM, WalletService.CONVERT]:
		assert_true(sql.contains("'%s'" % reason), "the database knows the reason %s" % reason)
	assert_true(sql.contains("p_reason not in ('convert', 'item')"), "the game can't grant")


func test_prize_popup_says_what_was_won() -> void:
	var one := DailyPrizePopup.new([_prize("2026-11-09", 2)])
	_in_tree(one)
	assert_eq(one.rank_text(), "#2")
	assert_eq(one.summary(), "You won 2 diamonds.")
	assert_eq(one.claim_text(), "Claim 2")
	assert_eq(DailyPrizePopup.day_line(one.latest()), "Daily board, 9 November")
	one.free()
	var many := DailyPrizePopup.new([_prize("2026-11-07", 1), _prize("2026-11-09", 7)])
	_in_tree(many)
	assert_eq(many.rank_text(), "#7", "the latest day's place")
	assert_eq(many.total(), 4)
	assert_eq(many.summary(), "You won 4 diamonds over 2 days.")
	many.free()
	assert_eq(DailyPrizePopup.diamonds_text(1), "1 diamond")
	assert_eq(DailyPrizePopup.day_line({"day": "soon"}), "Daily board", "a broken day")


func test_home_offers_a_daily_prize_and_claims_it() -> void:
	var p := Profile.new()
	p.diamonds = 4
	var wallet := FakeWallet.new(p)
	wallet.prizes = [_prize("2026-11-09", 1)]
	var main := _make_main(wallet, p)
	# main loads its own Profile from the save: point the wallet at that one.
	wallet._profile = main._profile
	main.show_home()
	var home := main._menus.current() as HomeScreen
	var popup := home.prize_popup()
	assert_true(popup != null, "the prize shows on Home")
	assert_eq(popup.claim_text(), "Claim 3")
	popup._claim.pressed.emit()
	assert_eq(main._profile.diamonds, 7, "3 diamonds for first place")
	assert_eq(home.wallet().diamonds_text(), "7")
	assert_true(home.prize_popup() == null, "the popup closes")
	assert_eq(Profile.load_or_new(TEST_PATH).diamonds, 7, "saved")
	main.show_home()
	assert_true((main._menus.current() as HomeScreen).prize_popup() == null, "claimed once")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_a_failed_claim_keeps_the_prize_on_screen() -> void:
	var p := Profile.new()
	var wallet := FakeWallet.new(p)
	wallet.prizes = [_prize("2026-11-09", 5)]
	wallet.refuse = true
	var main := _make_main(wallet, p)
	wallet._profile = main._profile
	main.show_home()
	var home := main._menus.current() as HomeScreen
	var popup := home.prize_popup()
	popup._claim.pressed.emit()
	assert_eq(main._profile.diamonds, 0)
	assert_true(home.prize_popup() == popup, "still there")
	assert_eq(popup.note_text(), DailyPrizePopup.FAILED)
	assert_false(popup.is_claiming(), "the player can try again")
	popup.closed.emit()
	assert_true(home.prize_popup() == null, "Later closes it")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_an_online_wallet_closes_the_pretend_store() -> void:
	var p := Profile.new()
	var wallet := FakeWallet.new(p)
	var main := _make_main(wallet, p)
	assert_false(main.store.is_open(), "no pretend purchases against the server's balance")
	main.free()
	var local := _make_main()
	assert_true(local.store.is_open(), "debug builds with a local wallet can pretend")
	local.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_premium_items_are_paid_through_the_wallet() -> void:
	var p := Profile.new()
	p.diamonds = 40
	var wallet := FakeWallet.new(p)
	var main := _make_main(wallet, p)
	wallet._profile = main._profile
	main.show_shop(Catalog.WORLD)
	var c := main._menus.current() as CollectionScreen
	c._tap("neon")
	wallet.refuse = true
	c._on_action()
	assert_false(main._profile.owns(Catalog.WORLD, "neon"), "a refused spend buys nothing")
	assert_eq(main._profile.diamonds, 40)
	wallet.refuse = false
	c._tap("neon")
	c._on_action()
	assert_true(main._profile.owns(Catalog.WORLD, "neon"))
	assert_eq(main._profile.diamonds, 10)
	assert_eq(wallet.spends, [[30, "item", "world:neon"]], "the server is told what for")
	assert_eq(Profile.load_or_new(TEST_PATH).diamonds, 10, "saved")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_converting_goes_through_the_wallet() -> void:
	var p := Profile.new()
	p.diamonds = 3
	var wallet := FakeWallet.new(p)
	wallet.refuse = true
	var sheet := ConvertSheet.new(p, 2, "", wallet)
	_in_tree(sheet)
	sheet.confirm()
	assert_eq([p.diamonds, p.coins], [3, 0], "a refused spend adds no gold")
	assert_true(sheet.can_convert(), "the player can try again")
	wallet.refuse = false
	sheet.confirm()
	assert_eq([p.diamonds, p.coins], [1, 200])
	assert_eq(wallet.spends, [[2, "convert", ""]])
	sheet.free()
