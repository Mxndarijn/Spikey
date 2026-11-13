extends TestCase
## The rooms' measured difficulty scores (game/rooms/room_scores.gd, baked by
## tools/make_room_scores.gd) and the Score on the Rooms screen's room page.

const TOOL := preload("res://tools/make_room_scores.gd")


func test_every_room_in_the_catalog_has_a_score() -> void:
	for def in RoomCatalog.all():
		if def.id in RoomScores.UNMEASURED:
			assert_eq(RoomScores.of(def.id), -1, "%s has no number" % def.id)
			continue
		var s := RoomScores.of(def.id)
		assert_true(s >= 0 and s <= 130, "%s has a score 0..130 (%d)" % [def.id, s])


func test_an_id_not_in_the_catalog_has_none() -> void:
	assert_eq(RoomScores.of("no-such-room"), -1)


func test_the_tool_averages_todays_variants_and_drops_removed_ones() -> void:
	var def := RoomCatalog.find("stalac")
	var by_label := {"gone/classic": 99.0, "stalac/old-variant": 120.0}
	for i in def.variants.size():
		by_label["stalac/%s" % def.variants[i].id] = 10.0 + 10.0 * i
	by_label["narrow"] = 41.6
	var means: Dictionary = TOOL.means(by_label)
	var want := 0.0
	for i in def.variants.size():
		want += 10.0 + 10.0 * i
	assert_eq(means["stalac"], roundi(want / def.variants.size()), "mean over today's variants")
	assert_eq(means["narrow"], 42, "a room without variants uses its own label")
	assert_false(means.has("gone"), "a removed room is left out")
	assert_false(means.has("tide"), "a room with no measured variant is left out")


func test_room_page_shows_the_score() -> void:
	DevMode.override = 0
	var p := Profile.new()
	var screen := RoomDetailScreen.new(p, "piston")
	screen.theme = UiTheme.get_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_eq(screen.score_text(), str(RoomScores.of("piston")))
	screen.free()
	var locked := RoomDetailScreen.new(p, "flip")
	(Engine.get_main_loop() as SceneTree).root.add_child(locked)
	assert_eq(locked.score_text(), str(RoomScores.of("flip")), "a locked room shows it too")
	locked.free()


func test_a_room_no_bot_can_measure_shows_a_dash() -> void:
	var ids: Array[String] = RoomScores.UNMEASURED
	if ids.is_empty():
		return
	var id: String = ids[0]
	DevMode.override = 1
	var screen := RoomDetailScreen.new(Profile.new(), id)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	assert_eq(screen.score_text(), "—")
	screen.free()
	DevMode.override = 0
