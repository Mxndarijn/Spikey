extends TestCase
## The seed picker on the debug page, in every build: it reads a seed (also
## the whole game over line), and Play runs that seed again from its first
## room as practice, the same run every try, without touching the save.

const TEST_PATH := "user://test_seed_picker_profile.json"


func _reset() -> void:
	SeedPicker.last_seed = -1


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free_main(main: Node) -> void:
	main.free()
	SafeFile.remove(TEST_PATH)


func test_parse_reads_the_seed() -> void:
	assert_eq(SeedPicker.parse("123456"), 123456)
	assert_eq(SeedPicker.parse("  42 "), 42)
	assert_eq(SeedPicker.parse("0"), 0)
	assert_eq(SeedPicker.parse(GameOverScreen.seed_text(98765)), 98765, "the game over line")
	assert_eq(SeedPicker.parse(str(SeedPicker.MAX_SEED)), SeedPicker.MAX_SEED)
	assert_eq(SeedPicker.parse(str(SeedPicker.MAX_SEED + 1)), -1, "too big")
	assert_eq(SeedPicker.parse("99999999999999999999999"), -1, "far too big")
	assert_eq(SeedPicker.parse(""), -1)
	assert_eq(SeedPicker.parse("seed"), -1)


func test_play_needs_a_seed_and_keeps_it() -> void:
	_reset()
	var picker := SeedPicker.new()
	var got: Array[int] = []
	picker.play_pressed.connect(func(s: int) -> void: got.append(s))
	var play := picker.find_child("PlaySeed", true, false) as Button
	assert_true(play.disabled, "nothing typed yet")
	picker.set_text("abc")
	assert_true(play.disabled, "not a seed")
	picker.play()
	assert_eq(got.size(), 0)
	picker.set_text("Seed 31337 · v1")
	assert_false(play.disabled)
	play.pressed.emit()
	assert_eq(got, [31337] as Array[int])
	picker.free()
	# The next picker (the debug page opened again) has it filled in.
	picker = SeedPicker.new()
	assert_eq(picker.seed_value(), 31337, "keeps the last seed")
	picker.free()
	_reset()


func test_players_have_the_seed_picker_too() -> void:
	DevMode.override = 0
	var page := DebugPage.new(Profile.new(), AppServices.offline(Profile.new()))
	assert_true(page.seed_picker() != null, "release builds show it")
	page.free()
	DevMode.override = -1


func test_play_from_the_debug_page_runs_that_seed_as_practice() -> void:
	_reset()
	var main := _make_main()
	var home := main._menus.current() as HomeScreen
	var sheet := home.open_settings()
	sheet.show_debug(true)
	var picker := sheet.debug_page().seed_picker()
	picker.set_text("4242")
	picker.play()
	assert_eq(main.mode, main.Mode.PRACTICE, "a seed plays as practice")
	assert_eq(main._run.sim.seed_value, 4242)
	assert_eq(main._run.sim.practice_room, -1, "the whole run, not one room")
	assert_eq(main._run.sim.forced_variant, "")
	# It plays exactly like a real run with that seed.
	var plain := GameSim.new(4242, main.season)
	for t in 400:
		main._run.sim.step(t % 19 == 0)
		plain.step(t % 19 == 0)
	assert_eq(main._run.sim.state.checksum(), plain.state.checksum(), "same run")
	# Try again plays the same seed.
	main._restart_practice()
	assert_eq(main._run.sim.seed_value, 4242, "every try")
	# Leaving goes back to the debug page.
	main._leave_to_rooms()
	var back := main._menus.current() as HomeScreen
	assert_true(back != null and back.settings().debug_page() != null, "back on the debug page")
	# A real run after it draws a new seed (and so does room practice).
	main.show_home()
	main.start_run()
	assert_eq(main.mode, main.Mode.RUN)
	assert_eq(main._practice_seed, -1, "a real run forgets the seed")
	main.start_seed_practice(4242)
	main.start_picker_practice("tide")
	assert_eq(main._practice_seed, -1, "room practice draws its seeds")
	_free_main(main)
	_reset()


func test_seed_practice_never_touches_the_save() -> void:
	_reset()
	var main := _make_main()
	main.start_seed_practice(777)
	assert_eq(main.mode, main.Mode.PRACTICE)
	for t in 2000:
		if main._run.sim.is_over():
			break
		main._run.sim.step(t % 25 == 0)
	main._on_died(null)
	assert_eq(main._profile.best_score, 0, "no best score")
	assert_eq(main._profile.coins, 0, "no coins")
	# Bad seeds do nothing.
	main.show_home()
	main.start_seed_practice(-5)
	assert_eq(main.mode, main.Mode.MENU)
	main.start_seed_practice(SeedPicker.MAX_SEED + 1)
	assert_eq(main.mode, main.Mode.MENU)
	_free_main(main)
	_reset()
