extends TestCase
## Narrow: its walls slide in as the room starts. Their spikes stay hidden
## until the walls stand still, then slide out (they don't ride in from the
## screen edge), and the walls themselves cover any spike still inside them.

const DT := 1.0 / 60.0


func _view(run: RunController) -> RoomView:
	var view := RoomView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.bind(run, ThemeCatalog.default_theme())
	return view


func _shown(view: RoomView) -> float:
	var out := 0.0
	for t in view._left_reveal:
		out = maxf(out, t)
	for t in view._right_reveal:
		out = maxf(out, t)
	return out


func test_narrow_spikes_wait_for_the_walls() -> void:
	var run := RunController.new()
	run.new_run(5, Seasons.NONE, RoomCatalog.index_of("narrow"))
	var view := _view(run)
	var room := run.sim.room
	# Spikes on the far wall from the start, as out of a portal.
	run.sim.state.right_spikes = 0b11100
	var ticks := 0
	# The room starts on the first tap; a flap now and then keeps the bird up.
	while room.inset(0) < room.def.inset and ticks < 600:
		view._process(DT)
		assert_eq(_shown(view), 0.0, "no spike while the walls move (tick %d)" % ticks)
		run.sim.step(ticks % 20 == 0)
		ticks += 1
	assert_true(run.sim.state.alive, "the bird lived through the slide")
	assert_eq(room.inset(0), room.def.inset, "the walls did slide in")
	assert_true(run.sim.wall_mask(1) != 0, "the far wall has spikes")
	for i in 20:
		view._process(DT)
	assert_eq(_shown(view), 1.0, "then they slide out")
	view.free()
	run.free()


func test_open_sky_spikes_slide_out_at_once() -> void:
	var run := RunController.new()
	run.new_run(5, Seasons.NONE, RoomCatalog.first_index())
	var view := _view(run)
	run.sim.state.right_spikes = 0b11100
	view._process(DT)
	assert_true(run.sim.wall_mask(1) != 0, "the far wall has spikes")
	assert_true(_shown(view) > 0.0, "fixed walls show their spikes right away")
	view.free()
	run.free()
