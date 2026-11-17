extends TestCase
## Battle is paused (GameModes.BATTLE_ENABLED): nothing in the app leads to it.
## Its own tests turn it back on; this is the app as players get it.

const TEST_PATH := "user://test_battle_paused_profile.json"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_the_app_shows_no_battle() -> void:
	assert_false(GameModes.BATTLE_ENABLED, "Battle is paused")
	assert_eq(GameModes.ids(), [GameModes.CLASSIC, GameModes.DAILY, GameModes.DUEL])
	assert_eq(GameModes.find(GameModes.BATTLE).id, GameModes.CLASSIC, "a saved Battle tab: Classic")
	var tabs := ModeTabs.new(GameModes.BATTLE)
	assert_eq(tabs.tab_ids(), [GameModes.CLASSIC, GameModes.DAILY, GameModes.DUEL])
	tabs.free()
	var wins := WinsScreen.new("battle")
	assert_eq(wins.mode, "duel", "the Wins boards show Duel only")
	wins.free()
	var duel := DuelScreen.new()
	_tree().root.add_child(duel)
	duel.show_finding()
	duel._process(31.0)
	assert_false(duel.b_button().visible, "no Battle offered while you wait for a Duel")
	duel.free()


func test_battle_pushes_and_links_open_home() -> void:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	_tree().root.add_child(main)
	await _tree().process_frame
	var intents: AppIntents = main._battle.intents
	intents.deliver({"push": {"kind": "battle_alert", "battle": "12"}})
	assert_true(main._menus.current() is HomeScreen, "a battle push: Home")
	intents.deliver({"link": "https://flapjaw.mn-platform.tech/battle/KD7WQ3"})
	assert_true(main._menus.current() is HomeScreen, "a battle link: Home")
	intents.deliver({"push": {"kind": "duel_alert"}})
	assert_true(main._menus.current() is DuelScreen, "Duel goes on")
	main.free()
	SafeFile.remove(TEST_PATH)
