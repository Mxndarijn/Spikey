extends TestCase
## Shop, Rooms and Leaderboard lists follow the finger and coast after a flick.


static func make_list(max_offset: float = 600.0) -> SmoothScroll:
	var s := SmoothScroll.new()
	var bar := s.get_v_scroll_bar()
	bar.step = 0.0
	bar.max_value = max_offset + 400.0
	bar.page = 400.0
	return s


func test_small_moves_are_still_a_tap() -> void:
	var s := make_list()
	s.press(300.0, 0.0)
	assert_false(s.move(300.0 - SmoothScroll.DEADZONE + 1.0, 0.02), "inside the deadzone")
	assert_eq(s.offset(), 0.0)
	s.release(0.04)
	assert_false(s.swallow_tap(), "a tap stays a tap")
	assert_false(s.is_coasting())
	s.free()


func test_drag_follows_the_finger_after_the_deadzone() -> void:
	var s := make_list()
	s.press(300.0, 0.0)
	assert_true(s.move(290.0, 0.016), "past the deadzone")
	assert_eq(s.offset(), 0.0, "the deadzone itself does not jump the list")
	s.move(250.0, 0.032)
	assert_eq(s.offset(), 40.0, "list moves up as the finger moves up")
	assert_true(s.swallow_tap(), "a drag is not a tap")
	s.free()


func test_flick_coasts_and_slows_down_smoothly() -> void:
	var s := make_list(5000.0)
	s.press(500.0, 0.0)
	for i in range(1, 6):
		s.move(500.0 - 30.0 * i, 0.016 * i)
	s.release(0.09)
	assert_true(s.swallow_tap(), "the release that ends a drag is not a tap")
	assert_true(s.is_coasting(), "a flick coasts")
	var last := s.offset()
	var last_step := INF
	for i in 30:
		s.advance(1.0 / 120.0)
		var step := s.offset() - last
		assert_true(step > 0.0, "keeps moving the same way, frame %d" % i)
		assert_true(step < last_step, "every frame a little slower, frame %d" % i)
		last_step = step
		last = s.offset()
	for i in 600:
		s.advance(1.0 / 120.0)
	assert_false(s.is_coasting(), "comes to rest")
	s.free()


func test_resting_finger_does_not_flick() -> void:
	var s := make_list()
	s.press(400.0, 0.0)
	s.move(350.0, 0.05)
	s.move(300.0, 0.1)
	s.release(0.1 + SmoothScroll.HOLD_STOP + 0.05)
	assert_false(s.is_coasting())
	s.free()


func test_list_stops_at_its_ends() -> void:
	var s := make_list(100.0)
	s.press(500.0, 0.0)
	s.move(480.0, 0.01)
	s.move(100.0, 0.02)
	assert_eq(s.offset(), 100.0, "no further than the end")
	s.release(0.02)
	for i in 10:
		s.advance(1.0 / 60.0)
	assert_eq(s.offset(), 100.0)
	assert_false(s.is_coasting(), "hitting the end stops the coast")
	s.press(100.0, 1.0)
	s.move(120.0, 1.01)
	s.move(900.0, 1.02)
	assert_eq(s.offset(), 0.0, "no further than the top")
	s.free()


func test_a_new_touch_stops_the_coast() -> void:
	var s := make_list(5000.0)
	s.press(500.0, 0.0)
	s.move(480.0, 0.01)
	s.move(400.0, 0.03)
	s.release(0.03)
	assert_true(s.is_coasting())
	s.press(400.0, 0.1)
	assert_false(s.is_coasting(), "touching the list catches it")
	s.free()


func test_moving_the_list_elsewhere_stops_the_coast() -> void:
	var s := make_list(5000.0)
	s.press(500.0, 0.0)
	s.move(480.0, 0.01)
	s.move(400.0, 0.03)
	s.release(0.03)
	s.get_v_scroll_bar().value = 0.0
	s.advance(1.0 / 60.0)
	assert_false(s.is_coasting(), "a tab change resets the list")
	assert_eq(s.offset(), 0.0)
	s.free()


func test_built_in_drag_is_off() -> void:
	var s := make_list()
	assert_true(s.scroll_deadzone > 10000, "only this script drags")
	s.free()
