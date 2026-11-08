extends TestCase
## Every hazard kind used by a room has a painter, and every painter draws
## without errors.


func test_every_hazard_kind_has_a_painter() -> void:
	var kinds := {}
	for def in RoomCatalog.all():
		var sim := GameSim.new(1)
		sim.room.start(def, RoomCatalog.index_of(def.id), sim, SimRng.new(1))
		for h in sim.room.hazards:
			kinds[h.kind] = def.id
	for kind: String in kinds:
		assert_true(
			ResourceLoader.exists(HazardLayer.painter_path(kind)),
			"%s (room %s) has %s" % [kind, kinds[kind], HazardLayer.painter_path(kind)]
		)


## Draws every room's hazards for a few frames (catches painter errors).
func test_every_room_draws() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var run := RunController.new()
	var layer := HazardLayer.new()
	tree.root.add_child(run)
	tree.root.add_child(layer)
	for def in RoomCatalog.all():
		run.new_run(3)
		var index := RoomCatalog.index_of(def.id)
		run.sim.room.start(def, index, run.sim, SimRng.new(5))
		layer.bind(run, ThemeCatalog.default_theme())
		for i in 3:
			run.sim.room.step(run.sim)
			await tree.process_frame
	run.free()
	layer.free()


## Color-blind spikes: every room's hazards draw from the ink copy of the
## world (ink spikes, white edges), which keeps the world's other colours.
func test_every_room_draws_with_color_blind_spikes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var run := RunController.new()
	var layer := HazardLayer.new()
	tree.root.add_child(run)
	tree.root.add_child(layer)
	layer.color_blind_spikes = true
	for t in ThemeCatalog.all():
		var ink := HazardLayer.ink_theme(t)
		assert_eq(ink.spike, RoomView.INK_SPIKE, "%s hazards are ink" % t.id)
		assert_eq(ink.spike_edge, HazardLayer.INK_EDGE, "%s hazards have a white edge" % t.id)
		assert_eq(ink.world_accent, t.world_accent, "%s keeps its other colours" % t.id)
		assert_ne(t.spike, RoomView.INK_SPIKE, "%s world itself is unchanged" % t.id)
	for def in RoomCatalog.all():
		run.new_run(3)
		var index := RoomCatalog.index_of(def.id)
		run.sim.room.start(def, index, run.sim, SimRng.new(5))
		layer.bind(run, ThemeCatalog.default_theme())
		assert_true(layer.drawn_theme().has_meta(HazardLayer.INK_META), "painters get ink")
		for i in 2:
			run.sim.room.step(run.sim)
			await tree.process_frame
	run.free()
	layer.free()
