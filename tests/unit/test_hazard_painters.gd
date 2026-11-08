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
