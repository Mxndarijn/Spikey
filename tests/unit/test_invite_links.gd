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
	var battle := BattleScreen.invite_text("KD7WQ3")
	assert_true(battle.begins_with("Battle me"), battle)
	assert_true(battle.ends_with("https://flapjaw.mn-platform.tech/battle/KD7WQ3"), battle)
	var duel := BattleScreen.invite_text("KD7WQ3", true)
	assert_true(duel.begins_with("Duel me"), duel)
	assert_true(duel.ends_with("https://flapjaw.mn-platform.tech/duel/KD7WQ3"), duel)


func test_android_opens_both_link_kinds_once_verified() -> void:
	var xml := AppLinks.intent_filter()
	assert_true(xml.contains('android:autoVerify="true"'))
	assert_true(xml.contains('android:host="flapjaw.mn-platform.tech"'))
	assert_true(xml.contains('android:pathPrefix="/battle/"'))
	assert_true(xml.contains('android:pathPrefix="/duel/"'))
	assert_true(xml.contains("android.intent.category.BROWSABLE"))


func test_a_duel_link_joins_once_the_server_greets() -> void:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	_tree().root.add_child(main)
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
