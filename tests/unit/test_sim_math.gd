extends TestCase

# Triangle pointing right from the left wall: base (0,-10)-(0,10), tip (20,0).


func test_point_inside_triangle() -> void:
	assert_true(SimMath.point_in_triangle(5, 0, 0, -10, 0, 10, 20, 0))
	assert_false(SimMath.point_in_triangle(25, 0, 0, -10, 0, 10, 20, 0))
	assert_false(SimMath.point_in_triangle(15, 8, 0, -10, 0, 10, 20, 0))


func test_circle_touching_tip() -> void:
	assert_true(SimMath.circle_hits_triangle(25, 0, 5, 0, -10, 0, 10, 20, 0))
	assert_false(SimMath.circle_hits_triangle(26, 0, 5, 0, -10, 0, 10, 20, 0))


func test_circle_near_slanted_edge() -> void:
	# Edge from (0,10) to (20,0). Point (15, 10) is ~6.7 away from it.
	assert_true(SimMath.circle_hits_triangle(15, 10, 7, 0, -10, 0, 10, 20, 0))
	assert_false(SimMath.circle_hits_triangle(15, 10, 6, 0, -10, 0, 10, 20, 0))


func test_large_sub_unit_coordinates_do_not_overflow() -> void:
	var s := SimConfig.SUB
	var w := SimConfig.WORLD_W
	var cy := SimConfig.slot_center_y(12)
	var hb := SimConfig.SPIKE_HALF_BASE
	var tip := w - SimConfig.SPIKE_DEPTH
	assert_true(
		SimMath.circle_hits_triangle(
			tip - 10 * s, cy, SimConfig.BIRD_RADIUS, w, cy - hb, w, cy + hb, tip, cy
		)
	)
	assert_false(
		SimMath.circle_hits_triangle(
			tip - 20 * s, cy, SimConfig.BIRD_RADIUS, w, cy - hb, w, cy + hb, tip, cy
		)
	)
