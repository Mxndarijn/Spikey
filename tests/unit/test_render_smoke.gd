extends TestCase
## Draws every world, particle kind and trail for a few real frames headless, so
## drawing code (which only runs inside _draw) is exercised. Any engine or script
## error logged while drawing fails the test.

const TEST_PATH := "user://test_render_profile.json"
const FRAMES := 3


func _make_main() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _frames(n: int = FRAMES) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in n:
		await tree.process_frame


func test_every_world_and_trail_draws_in_a_run() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz")
	main.start_run()
	main._run.request_tap()
	await _frames()
	for id in Catalog.ids(Catalog.WORLD):
		main.set_world(id)
		await _frames()
	for t in Catalog.trails():
		main._trail.set_style(t, main._theme)
		main._trail.start()
		main._trail.on_flap()
		await _frames(6)
	assert_true(main._run.sim != null, "the run kept going while drawing")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_shop_previews_draw_for_every_kind() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz", "ice")
	for kind in Catalog.KINDS:
		main.show_shop(kind)
		var shop := main._menus.current() as CollectionScreen
		for id in Catalog.ids(kind):
			shop._select(id)
			await _frames(1)
	assert_true(main._menus.current() is CollectionScreen, "shop stayed open")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## Particles at many moments (embers flicker out, stars flare, bubbles grow)
## and every trail at every age, so all shape code paths really draw.
func test_particles_and_trails_draw_through_their_life() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz")
	main.start_run()
	main._run.request_tap()
	await _frames()
	for id in Catalog.ids(Catalog.WORLD):
		main.set_world(id)
		for k in 4:
			main._room._time = 3.7 * k
			await _frames(1)
	for t in Catalog.trails():
		main._trail.set_style(t, main._theme)
		var pts := PackedVector2Array()
		var ages := PackedFloat32Array()
		for i in 12:
			pts.append(Vector2(60 + i * 18, 400 - i * 12))
			ages.append(t.lifetime * (1.0 - i / 11.0))
		main._trail._points = pts
		main._trail._ages = ages
		main._trail.queue_redraw()
		await _frames(1)
	assert_true(main._run.sim != null, "the run kept going while drawing")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_rooms_screens_and_practice_draw() -> void:
	var main := _make_main()
	_use_flyer(main, "buzz")
	for def in RoomCatalog.all():
		main._profile.record_room_met(def.id)
	main._profile.record_room_cleared("piston")
	main.show_rooms()
	await _frames()
	for id in ["piston", "pumpkin", "midnight"]:
		main.show_room(id)
		await _frames(1)
		main.start_practice(id)
		main._run.request_tap()
		await _frames()
		main._set_paused(true)
		await _frames(1)
		main._set_paused(false)
		main._on_died(Replay.from_sim(main._run.sim, PackedInt32Array()))
		await _frames(1)
	assert_true(main._hud.practice_hud().is_over_showing(), "practice crash screen drew")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## Every world's scene in every time of day (room palettes fade in), with the
## world's spikes and with color-blind ink spikes, plus the generic scene a
## world without its own gets.
func test_every_world_scene_draws_in_every_time_of_day() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var run := RunController.new()
	var view := RoomView.new()
	tree.root.add_child(run)
	tree.root.add_child(view)
	run.new_run(5)
	run.sim.step(true)
	for t in ThemeCatalog.all():
		view.bind(run, t)
		for ink in [false, true]:
			view.color_blind_spikes = ink
			for room in t.palette_count():
				view.on_room_changed(room)
				await _frames(2)
				view._fade = 1.0
				await _frames(1)
	var unknown: ThemeDef = ThemeCatalog.all()[0].duplicate()
	unknown.id = "not_a_world"
	view.set_theme(unknown)
	await _frames(2)
	assert_eq(view._drawn_sky, view._shown_sky(), "the backdrop drew the room's sky")
	run.free()
	view.free()


## Puts a flyer (and optionally a world) in use, as Customize would; a first
## start already gave the default world.
static func _use_flyer(main: Node, id: String, world: String = "") -> void:
	main._profile.grant(Catalog.FLYER, id)
	main._profile.equip(Catalog.FLYER, id)
	if not world.is_empty():
		main._profile.grant(Catalog.WORLD, world)
		main._profile.equip(Catalog.WORLD, world)
	main._load_equipped()
