extends TestCase
## The room picker on the debug page, in every build: it lists every catalog
## room and variant, Play starts a practice run that really plays the picked
## variant (any room, players too), and real runs never force a variant.

const TEST_PATH := "user://test_room_picker_profile.json"


func _reset(dev_mode: int = -1) -> void:
	DevMode.override = dev_mode
	RoomPicker.last_room = ""
	RoomPicker.last_variant = RoomPicker.RANDOM


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _free_main(main: Node) -> void:
	main.free()
	SafeFile.remove(TEST_PATH)


func _picker() -> RoomPicker:
	var picker := RoomPicker.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(picker)
	return picker


func test_lists_every_catalog_room_and_its_variants() -> void:
	_reset(1)
	var picker := _picker()
	var want: Array[String] = []
	for def in RoomCatalog.all():
		want.append(def.id)
	var listed := picker.listed_rooms()
	assert_eq(listed.size(), want.size(), "each room once")
	for def in RoomCatalog.all():
		assert_true(def.id in listed, "%s listed" % def.id)
		var b := picker.find_child("Room_" + def.id, true, false) as Button
		assert_true(b != null, "%s has a button" % def.id)
		assert_eq(b.text, RoomInfo.name_of(def.id), "%s shows its name" % def.id)
		picker.pick(def.id)
		var choices := picker.variant_choices()
		if def.variants.is_empty():
			assert_eq(choices.size(), 0, "%s just plays" % def.id)
			continue
		assert_eq(choices[0], RoomPicker.RANDOM, "%s: Random first" % def.id)
		assert_eq(choices.size(), def.variants.size() + 1, def.id)
		for v in def.variants:
			assert_true(v.id in choices, "%s offers %s" % [def.id, v.id])
	assert_true(picker.find_child("Room_pumpkin", true, false) != null, "seasonal rooms too")
	picker.free()
	_reset()


func test_picking_shows_variants_and_defaults_to_random() -> void:
	_reset(1)
	var picker := _picker()
	var got := []
	picker.play_pressed.connect(func(id: String, v: String) -> void: got.append([id, v]))
	(picker.find_child("Room_bramble", true, false) as Button).pressed.emit()
	assert_eq(picker.room_id, "bramble")
	assert_eq(picker.variant, RoomPicker.RANDOM, "Random by default")
	var last_id := RoomCatalog.find("bramble").variants[-1].id
	(picker.find_child("Variant_" + last_id, true, false) as Button).pressed.emit()
	(picker.find_child("PlayRoom", true, false) as Button).pressed.emit()
	assert_eq(got, [["bramble", last_id]])
	# The next picker (the debug page opened again) remembers it.
	picker.free()
	picker = _picker()
	assert_eq(picker.room_id, "bramble", "keeps the last room")
	assert_eq(picker.variant, last_id, "and its variant")
	var again := picker.find_child("PlayAgain", true, false) as Button
	assert_true(again.visible, "Play again shows")
	picker.play_pressed.connect(func(id: String, v: String) -> void: got.append([id, v]))
	again.pressed.emit()
	assert_eq(got[-1], ["bramble", last_id], "Play again plays the same pick")
	picker.free()
	_reset()


func test_forced_variant_practice_plays_that_variant() -> void:
	_reset(1)
	var main := _make_main()
	for def in RoomCatalog.all():
		for v in def.variants:
			main.start_picker_practice(def.id, v.id)
			assert_eq(main.mode, main.Mode.PRACTICE, def.id)
			assert_eq(main._run.sim.state.room_kind, RoomCatalog.index_of(def.id), def.id)
			assert_eq(main._run.sim.room.variant_id(), v.id, "%s plays %s" % [def.id, v.id])
		if def.variants.size() > 0:
			# Try again keeps the variant.
			main._restart_practice()
			assert_eq(main._run.sim.room.variant_id(), def.variants[-1].id, def.id + " again")
	_free_main(main)
	_reset()


func test_play_from_the_debug_page_starts_the_practice_run() -> void:
	_reset(1)
	var main := _make_main()
	var home := main._menus.current() as HomeScreen
	var sheet := home.open_settings()
	sheet.show_debug(true)
	var picker := sheet.debug_page().room_picker()
	assert_true(picker != null, "the page has the picker")
	var v := RoomCatalog.find("tide").variants[1].id
	picker.pick("tide", v)
	picker.play()
	assert_eq(main.mode, main.Mode.PRACTICE)
	assert_eq(main._run.sim.room.variant_id(), v)
	assert_eq(main._run.sim.forced_variant, v)
	# Random draws as usual.
	main.show_home()
	(main._menus.current() as HomeScreen).practice_requested.emit("tide", RoomPicker.RANDOM)
	assert_eq(main.mode, main.Mode.PRACTICE)
	assert_eq(main._run.sim.forced_variant, "", "Random forces nothing")
	_free_main(main)
	_reset()


func test_players_have_the_picker_too() -> void:
	_reset(0)
	var page := DebugPage.new(Profile.new(), AppServices.offline(Profile.new()))
	assert_true(page.room_picker() != null, "release builds show the picker")
	assert_true(page.find_child("RoomPicker", true, false) != null)
	page.free()
	# It plays any room and variant, even one the player never met.
	var main := _make_main()
	var v := RoomCatalog.find("tide").variants[1].id
	main.start_picker_practice("tide", v)
	assert_eq(main.mode, main.Mode.PRACTICE, "the picker plays an unmet room")
	assert_eq(main._run.sim.forced_variant, v)
	# An unknown room or variant does nothing.
	main.show_home()
	main.start_picker_practice("tide", "no_such_variant")
	assert_eq(main.mode, main.Mode.MENU, "unknown variant")
	main.start_picker_practice("no_such_room")
	assert_eq(main.mode, main.Mode.MENU, "unknown room")
	# The Rooms screen keeps its rules: open rooms only, the variant drawn.
	main.start_practice("tide")
	assert_eq(main.mode, main.Mode.MENU, "Rooms screen: unmet rooms stay closed")
	main._profile.record_room_met("tide")
	main.start_practice("tide")
	assert_eq(main.mode, main.Mode.PRACTICE)
	assert_eq(main._run.sim.forced_variant, "", "normal practice draws")
	_free_main(main)
	_reset()


func test_real_runs_never_force_a_variant() -> void:
	_reset(1)
	var main := _make_main()
	main.start_picker_practice("tide", RoomCatalog.find("tide").variants[1].id)
	main.show_home()
	main.start_run()
	assert_eq(main.mode, main.Mode.RUN)
	assert_eq(main._run.sim.forced_variant, "", "a real run after a forced practice")
	assert_eq(main._run.sim.practice_room, -1)
	_free_main(main)
	# The run controller ignores a variant for real runs, and plays them like
	# a plain GameSim with the same seed.
	var run := RunController.new()
	run.new_run(77, Seasons.NONE, -1, "split")
	assert_eq(run.sim.forced_variant, "")
	var plain := GameSim.new(77)
	for t in 300:
		run.sim.step(t % 23 == 0)
		plain.step(t % 23 == 0)
	assert_eq(run.sim.state.checksum(), plain.state.checksum(), "same run")
	run.free()
	_reset()
