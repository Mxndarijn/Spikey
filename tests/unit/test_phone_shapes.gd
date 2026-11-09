extends TestCase
## Phones of every shape: no black bars, the room keeps its 360 x 640 size,
## sits at the top of the safe area (centred sideways) and the space around it
## is filled. HUD and menus follow the room.

const TEST_PATH := "user://test_phone_shapes_profile.json"
const ROOM := Vector2(360, 640)
const HUD_SCENE := "res://game/ui/hud.tscn"


func test_project_expands_instead_of_letterboxing() -> void:
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/aspect")), "expand")
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")


func test_room_keeps_its_size_and_sits_at_the_top_on_every_shape() -> void:
	# visible canvas size -> expected room position, with the whole screen safe.
	var cases := {
		Vector2(360, 640): Vector2(0, 0),  # 9:16
		Vector2(360, 780): Vector2(0, 0),  # 9:19.5
		Vector2(360, 840): Vector2(0, 0),  # 9:21
		Vector2(480, 640): Vector2(60, 0),  # 3:4 tablet
	}
	for visible: Vector2 in cases:
		var r := ScreenLayout.room_rect(visible, Rect2(Vector2.ZERO, visible))
		assert_eq(r.size, ROOM, "same room size at %s" % visible)
		assert_eq(r.position, cases[visible], "placed right at %s" % visible)


## iPhone 13 shape: 1170 x 2532 px, notch 141 px, home bar 102 px.
func test_room_sits_inside_the_safe_area_of_a_notched_phone() -> void:
	var window := Rect2i(0, 0, 1170, 2532)
	var visible := Vector2(360, 2532.0 * 360.0 / 1170.0)
	var safe := ScreenLayout.safe_rect(visible, window, Rect2i(0, 141, 1170, 2289))
	assert_true(safe.position.y > 40.0, "the notch is cut off the top (%d)" % safe.position.y)
	var r := ScreenLayout.room_rect(visible, safe)
	assert_eq(r.size, ROOM)
	assert_true(safe.encloses(r), "room %s inside the safe area %s" % [r, safe])
	assert_eq(r.position.y, ceilf(safe.position.y), "right under the notch")
	assert_true(Rect2(Vector2.ZERO, visible).encloses(r), "and on screen")


func test_a_safe_area_too_small_for_the_room_falls_back_to_the_screen() -> void:
	var visible := Vector2(360, 660)
	var r := ScreenLayout.room_rect(visible, Rect2(0, 40, 360, 600))
	assert_eq(r.position, Vector2(0, 0), "at the top of the screen instead")


func test_missing_safe_area_means_the_whole_screen() -> void:
	var visible := Vector2(360, 780)
	var whole := Rect2(Vector2.ZERO, visible)
	assert_eq(ScreenLayout.safe_rect(visible, Rect2i(), Rect2i(0, 0, 100, 100)), whole)
	assert_eq(ScreenLayout.safe_rect(visible, Rect2i(0, 0, 720, 1560), Rect2i()), whole)


## A desktop window: the screen's safe area is far bigger than the window.
func test_safe_area_is_clipped_to_the_window() -> void:
	var visible := Vector2(360, 640)
	var window := Rect2i(500, 200, 405, 720)
	var safe := ScreenLayout.safe_rect(visible, window, Rect2i(0, 0, 2560, 1440))
	assert_eq(safe, Rect2(Vector2.ZERO, visible))


## The band colour covers everything around the room, and none of the room.
func test_space_around_the_room_is_filled() -> void:
	var rects := RoomView.surround_rects()
	var room := Rect2(Vector2.ZERO, ROOM)
	for r in rects:
		assert_false(r.intersects(room), "%s stays off the room" % r)
	for p: Vector2 in [
		Vector2(180, -1),
		Vector2(180, -100),
		Vector2(180, 641),
		Vector2(180, 740),
		Vector2(-1, 320),
		Vector2(-60, 320),
		Vector2(361, 320),
		Vector2(-60, -100)
	]:
		var hit := false
		for r in rects:
			hit = hit or r.has_point(p)
		assert_true(hit, "%s is filled" % p)


## On a tall phone the world, HUD and menus all move down to the room.
func test_main_moves_world_hud_and_menus_together() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node2D = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var rect := Rect2(Vector2(0, 70), ROOM)
	main.set_room_rect(rect)
	assert_eq(main.position, rect.position, "world")
	assert_eq(main._hud._root.position, rect.position, "HUD")
	assert_eq(main._hud._root.size, ROOM, "HUD size")
	assert_eq(main._menus.room_rect(), rect, "menus")
	var screen := main._menus.current() as Control
	assert_eq(screen.get_global_rect(), rect, "the menu screen covers the room")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


## Coins fly into the counter from the room, wherever the room sits.
func test_coin_target_is_in_room_px() -> void:
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	# Lay out once so the counter has its final width before measuring.
	hud.room_rect = Rect2(Vector2.ZERO, ROOM)
	hud._run_coins.reset_size()
	var at_top := hud._counter_target()
	hud.room_rect = Rect2(Vector2(0, 70), ROOM)
	assert_eq(hud._counter_target(), at_top, "same spot in the room")
	hud.free()


## Dim overlays reach the screen edges: the bleed paints all around the scrim,
## never over it, takes no taps and leaves the scrim's children alone.
func test_scrims_dim_past_the_room() -> void:
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	var label := Label.new()
	var bleed := ScrimBleed.attach(scrim)
	scrim.add_child(label)
	assert_eq(scrim.get_child(0), label, "the scrim's own children keep their order")
	assert_eq(bleed.mouse_filter, Control.MOUSE_FILTER_IGNORE, "taps go through")
	var size := Vector2(360, 640)
	var rects := ScrimBleed.rects(size)
	for r in rects:
		assert_false(r.intersects(Rect2(Vector2.ZERO, size)), "%s stays off the scrim" % r)
	for p: Vector2 in [Vector2(180, -70), Vector2(180, 710), Vector2(-60, 320), Vector2(420, 0)]:
		var hit := false
		for r in rects:
			hit = hit or r.has_point(p)
		assert_true(hit, "%s is dimmed" % p)
	scrim.free()


## The HUD's pause scrim has its bleed.
func test_pause_dims_the_whole_screen() -> void:
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	var found := false
	for n in hud._paused.get_children(true):
		found = found or n is ScrimBleed
	assert_true(found, "pause scrim reaches past the room")
	hud.free()
