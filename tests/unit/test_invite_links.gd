extends TestCase
## Invite links: the link a friend gets, Android's App Links intent filter, and
## a link the phone opened the game with joining that battle or Duel.

const TEST_PATH := "user://test_invite_links_profile.json"
const AppLinks := preload("res://addons/flapjaw_links/app_links.gd")


class FakeLink:
	extends DuelLink
	var sent: Array[Dictionary] = []

	func _init() -> void:
		super(null)

	func send(msg: Dictionary) -> void:
		sent.append(msg)

	func open(_player_name: String, _flyer: String) -> void:
		pass


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_each_invite_names_its_own_link() -> void:
	assert_eq(
		BattleScreen.invite_text("KD7WQ3"),
		"Battle me in Flapjaw! https://flapjaw.mn-platform.tech/battle/KD7WQ3 (code KD7WQ3)"
	)
	assert_eq(
		BattleScreen.invite_text("KD7WQ3", true),
		"Duel me in Flapjaw! https://flapjaw.mn-platform.tech/duel/KD7WQ3 (code KD7WQ3)"
	)


func test_share_has_no_sheet_off_a_phone() -> void:
	assert_false(ShareSheet.share("hi", "Windows"), "desktop: no sheet, the caller copies")
	assert_false(ShareSheet.share("hi", "Linux"))
	assert_false(ShareSheet.share("hi", "Android"), "no AndroidRuntime here: no sheet either")
	assert_eq(
		ShareSheet.ios_url("Duel me! https://x/duel/AB (code AB)"),
		"flapjaw-share:?text=Duel%20me%21%20https%3A%2F%2Fx%2Fduel%2FAB%20%28code%20AB%29"
	)


func test_share_on_the_invite_screens_copies_off_a_phone() -> void:
	SafeFile.remove(TEST_PATH)
	var main := _main()
	await _tree().process_frame
	var flow: BattleFlow = main._battle
	# The Duel's invite: Share through DuelFlow, which copies here (no sheet).
	var duel := flow.duel.open()
	duel.show_invite("KD7WQ3")
	assert_eq(duel.primary().text, "Share")
	duel.primary().pressed.emit()
	assert_eq(main._hud._toast.text, BattleFlow.COPIED, "copied, with a toast")
	duel.a_button().pressed.emit()
	assert_eq(main._hud._toast.text, BattleFlow.COPIED, "Copy stays")
	main.free()
	SafeFile.remove(TEST_PATH)


func _main() -> Node:
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	_tree().root.add_child(main)
	return main


func test_android_opens_both_link_kinds_once_verified() -> void:
	var xml := AppLinks.intent_filter()
	assert_true(xml.contains('android:autoVerify="true"'))
	assert_true(xml.contains('android:host="flapjaw.mn-platform.tech"'))
	assert_true(xml.contains('android:pathPrefix="/battle/"'))
	assert_true(xml.contains('android:pathPrefix="/duel/"'))
	assert_true(xml.contains("android.intent.category.BROWSABLE"))


func test_a_duel_link_joins_once_the_server_greets() -> void:
	SafeFile.remove(TEST_PATH)
	var main := _main()
	await _tree().process_frame
	var link := FakeLink.new()
	main.add_child(link)
	var flow := DuelFlow.new(link, main._battle, main._menus, main._hud, main._profile)
	flow.open_joining("KD7WQ3")
	assert_true(main._menus.current() is DuelScreen)
	assert_eq(link.sent.size(), 0, "nothing before the server's welcome")
	flow.on_message({"t": "welcome", "player": "p"})
	assert_eq(link.sent, [{"t": "join", "code": "KD7WQ3"}])
	flow.on_message({"t": "welcome", "player": "p"})
	assert_eq(link.sent.size(), 1, "joined once")
	# Through the app: a Battle link opens Battles, a Duel link the Duel screen.
	var intents: AppIntents = main._battle.intents
	intents.deliver({"link": "https://flapjaw.mn-platform.tech/battle/KD7WQ3"})
	assert_true(main._menus.current() is BattleListScreen, "Battles, joining KD7WQ3")
	intents.deliver({"link": "https://flapjaw.mn-platform.tech/duel/kd7wq3?x=1"})
	assert_true(main._menus.current() is DuelScreen, "the Duel screen, joining KD7WQ3")
	intents.deliver({"link": "https://flapjaw.mn-platform.tech/"})
	assert_true(main._menus.current() is DuelScreen, "any other link opens nothing new")
	main.free()
	SafeFile.remove(TEST_PATH)
