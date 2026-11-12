extends TestCase
## The seed picker on the debug page, in every build: it reads a seed code
## (also the whole game over line, and old seed numbers), and Play runs that
## seed again from its first room as practice, in the code's own season, the
## same run every try, without touching the save.

const TEST_PATH := "user://test_seed_picker_profile.json"


func _reset() -> void:
	SeedPicker.last_text = ""


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free_main(main: Node) -> void:
	main.free()
	SafeFile.remove(TEST_PATH)


func _random(text: String) -> int:
	var p := SeedPicker.parse(text)
	return p.random if p != null else -1


func test_parse_reads_the_seed() -> void:
	var code := SeedCode.current(123456, Seasons.WINTER)
	assert_eq(_random(code), 123456)
	assert_eq(SeedPicker.parse(code).season, Seasons.WINTER, "the code's season")
	assert_eq(_random("  " + code.to_lower() + " "), 123456)
	assert_eq(_random(GameOverScreen.seed_text(98765)), 98765, "the game over line")
	assert_eq(_random(GameOverScreen.seed_text(98765, Seasons.SUMMER)), 98765)
	assert_eq(
		SeedPicker.parse(GameOverScreen.seed_text(98765, Seasons.SUMMER)).season, Seasons.SUMMER
	)
	# Old seed numbers still work, with no season.
	assert_eq(_random("42"), 42)
	assert_eq(SeedPicker.parse("42").season, Seasons.NONE)
	assert_eq(_random("Seed 98765 · v11"), 98765, "the old game over line")
	assert_eq(_random(str(SeedCode.MAX_RANDOM)), SeedCode.MAX_RANDOM)
	assert_eq(_random(str(SeedCode.MAX_RANDOM + 1)), -1, "too big")
	assert_eq(_random(""), -1)
	assert_eq(_random("seed"), -1)


func test_the_note_says_what_the_seed_holds() -> void:
	var now := SimConfig.GAMEPLAY_VERSION
	assert_eq(SeedPicker.note_for(""), "A seed code from the game over screen")
	assert_eq(
		SeedPicker.note_for(SeedCode.current(5000, Seasons.HALLOWEEN)),
		"Halloween · v%d. Plays from the first room, as practice" % now
	)
	assert_eq(
		SeedPicker.note_for(SeedCode.encode(5000, Seasons.NONE, now - 2)),
		"No season · v%d. This build plays v%d: the map will differ" % [now - 2, now]
	)
	assert_eq(SeedPicker.note_for("5000"), "Old seed: plays with no season on v%d" % now)
	assert_eq(SeedPicker.note_for("abc"), "Not a seed: a code like K7Q2M-9XH4D")


func test_play_needs_a_seed_and_keeps_it() -> void:
	_reset()
	var picker := SeedPicker.new()
	var got: Array = []
	picker.play_pressed.connect(func(s: int, season: int) -> void: got.append([s, season]))
	var play := picker.find_child("PlaySeed", true, false) as Button
	assert_true(play.disabled, "nothing typed yet")
	picker.set_text("abc")
	assert_true(play.disabled, "not a seed")
	picker.play()
	assert_eq(got.size(), 0)
	var code := SeedCode.current(31337, Seasons.SPRING)
	picker.set_text(GameOverScreen.seed_text(31337, Seasons.SPRING))
	assert_false(play.disabled)
	play.pressed.emit()
	assert_eq(got, [[31337, Seasons.SPRING]])
	picker.free()
	# The next picker (the debug page opened again) has it filled in.
	picker = SeedPicker.new()
	assert_eq(picker.parts().random, 31337, "keeps the last seed")
	assert_true(SeedPicker.last_text.contains(code))
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
	assert_eq(main._practice_season, Seasons.NONE, "an old seed has no season")
	assert_eq(main.mode, main.Mode.PRACTICE, "a seed plays as practice")
	assert_eq(main._run.sim.seed_value, 4242)
	assert_eq(main._run.sim.practice_room, -1, "the whole run, not one room")
	assert_eq(main._run.sim.forced_variant, "")
	# It plays exactly like a real run with that seed.
	var plain := GameSim.new(4242, Seasons.NONE)
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
	main.start_seed_practice(SeedCode.MAX_RANDOM + 1)
	assert_eq(main.mode, main.Mode.MENU)
	_free_main(main)
	_reset()


## Seed 3392377610 (a real v21 run) is above 2^31: the picker and seed
## practice must keep it whole, and practice plays exactly like that run.
func test_a_seed_above_two_to_the_31_plays_the_same_run() -> void:
	_reset()
	const BIG := 3392377610
	assert_eq(_random(str(BIG)), BIG)
	assert_eq(_random(GameOverScreen.seed_text(BIG)), BIG, "the game over line")
	var main := _make_main()
	main.start_seed_practice(BIG)
	assert_eq(main._run.sim.seed_value, BIG)
	var plain := GameSim.new(BIG, Seasons.NONE)
	assert_eq(main._run.sim.checksum(), plain.checksum(), "same first room")
	for t in 900:
		main._run.sim.step(t % 17 == 0)
		plain.step(t % 17 == 0)
	assert_eq(main._run.sim.checksum(), plain.checksum(), "same run, same taps")
	_free_main(main)
	_reset()


## A seed code plays its own season, whatever today is: seed 5000 in
## Halloween is not seed 5000 out of season, and a typed code matches the run.
func test_a_code_plays_its_own_season_not_todays() -> void:
	_reset()
	var main := _make_main()
	main.season = Seasons.SUMMER
	var sheet := (main._menus.current() as HomeScreen).open_settings()
	sheet.show_debug(true)
	var picker := sheet.debug_page().seed_picker()
	picker.set_text(SeedCode.current(5000, Seasons.HALLOWEEN))
	picker.play()
	assert_eq(main._run.sim.seed_value, 5000)
	assert_eq(main._run.sim.season, Seasons.HALLOWEEN, "the code's season, not today's")
	var plain := GameSim.new(5000, Seasons.HALLOWEEN)
	for t in 900:
		main._run.sim.step(t % 17 == 0)
		plain.step(t % 17 == 0)
	assert_eq(main._run.sim.checksum(), plain.checksum(), "same run as the Halloween seed")
	main._restart_practice()
	assert_eq(main._run.sim.season, Seasons.HALLOWEEN, "every try")
	_free_main(main)
	_reset()
