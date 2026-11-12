extends TestCase
## Game over empties the room (GameOverStage) and shows the flyer big in the
## middle (BirdView.showcase); its text is laid out round the flyer.


func _screen(new_best: bool, revived_at: int) -> GameOverScreen:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var screen := GameOverScreen.new()
	holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var best := 1024 if new_best else 87
	screen.show_result(
		best if new_best else 42,
		best,
		new_best,
		1240,
		987,
		31,
		1234,
		"Seed ABC123",
		revived_at,
		true
	)
	return screen


func _bottom(c: Control) -> float:
	return c.offset_top + c.get_combined_minimum_size().y


func _labels(screen: GameOverScreen) -> Array[Control]:
	var out: Array[Control] = []
	for child in screen.get_children():
		if child is Label or child is HBoxContainer:
			out.append(child as Control)
	return out


## The flyer's top (with its dazed stars) and bottom on screen.
func _flyer_span() -> Vector2:
	var k := BirdView.SHOW_SCALE
	var body := UiTokens.SIZE_BIRD / 2.0
	var stars := -BirdView.STAR_Y + BirdView.STAR_ORBIT.y + BirdView.STAR_R
	return Vector2(
		GameOverScreen.FLYER_Y - maxf(body, stars) * k, GameOverScreen.FLYER_Y + body * k
	)


## Everything above the flyer ends above it, everything below starts below it,
## and the seed ends above the dock: normal, revived and new best.
func test_text_clears_the_flyer() -> void:
	var span := _flyer_span()
	var dock_top := UiTokens.SIZE_VIEWPORT_H - Dock.HEIGHT
	for case: Array in [[false, -1], [false, 63], [true, -1]]:
		var screen := _screen(case[0], case[1])
		for c in _labels(screen):
			if not c.visible:
				continue
			var top := c.offset_top
			var bottom := _bottom(c)
			if top < GameOverScreen.FLYER_Y:
				assert_true(
					bottom <= span.x,
					"%s ends at %d, the flyer starts at %d" % [c.name, bottom, span.x]
				)
			else:
				assert_true(
					top >= span.y, "%s starts at %d, the flyer ends at %d" % [c.name, top, span.y]
				)
				assert_true(bottom <= dock_top, "%s ends at %d, above the dock" % [c.name, bottom])
		screen.get_parent().queue_free()


## The flyer flies from the wall to the spot, growing and tilting as it goes.
func test_showcase_pose_runs_from_wall_to_spot() -> void:
	var from := Vector2(330, 120)
	var to := GameOverStage.SPOT
	var start := BirdView.showcase_pose(from, to, 0.0, -1.0)
	assert_eq(start.position, from)
	assert_eq(start.scale, Vector2(-1, 1))
	var end := BirdView.showcase_pose(from, to, 1.0, -1.0)
	assert_eq(end.position, to)
	assert_eq(end.scale, Vector2(-BirdView.SHOW_SCALE, BirdView.SHOW_SCALE))
	assert_true(absf(end.rotation + BirdView.SHOW_TILT) < 0.0001, "it ends tilted")
	var mid := BirdView.showcase_pose(from, to, 0.5, 1.0)
	assert_true(mid.scale.x > 1.0 and mid.scale.x < BirdView.SHOW_SCALE, "it grows on the way")


## Game over fades the room's own drawing and the run's views; a new run brings
## them back. With reduced motion it happens at once.
func test_stage_empties_and_restores_the_room() -> void:
	var room := RoomView.new()
	var bird := BirdView.new()
	var hazards := Node2D.new()
	var coins := Node2D.new()
	var stage := GameOverStage.new()
	var root := Node.new()
	for n: Node in [room, bird, hazards, coins, stage]:
		root.add_child(n)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	stage.setup(room, bird, [hazards, coins])
	stage.show_empty(false, true)
	assert_true(stage.is_empty(), "the room is empty")
	assert_eq(room.self_modulate.a, 0.0)
	assert_eq(hazards.modulate.a, 0.0)
	assert_eq(coins.modulate.a, 0.0)
	assert_eq(room.modulate.a, 1.0, "the sky and landscape stay")
	assert_true(bird.is_showcased(), "the flyer is shown")
	stage.reset()
	assert_false(stage.is_empty(), "a new run brings the room back")
	assert_eq(room.self_modulate.a, 1.0)
	assert_eq(hazards.modulate.a, 1.0)
	assert_eq(coins.modulate.a, 1.0)
	root.queue_free()


## The flyer settles where the screen leaves room for it.
func test_stage_spot_is_the_screen_gap() -> void:
	assert_eq(GameOverStage.SPOT.y, GameOverScreen.FLYER_Y)
	assert_eq(GameOverStage.SPOT.x, UiTokens.SIZE_VIEWPORT_W / 2.0)
