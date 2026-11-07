class_name SimMath
extends RefCounted
## Integer geometry. Inputs are sub-unit coordinates small enough that all
## intermediate products stay well inside 64-bit range.


static func cross(ax: int, ay: int, bx: int, by: int, px: int, py: int) -> int:
	return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


static func point_in_triangle(
	px: int, py: int, ax: int, ay: int, bx: int, by: int, cx: int, cy: int
) -> bool:
	var d1 := cross(ax, ay, bx, by, px, py)
	var d2 := cross(bx, by, cx, cy, px, py)
	var d3 := cross(cx, cy, ax, ay, px, py)
	var has_neg := d1 < 0 or d2 < 0 or d3 < 0
	var has_pos := d1 > 0 or d2 > 0 or d3 > 0
	return not (has_neg and has_pos)


## True when the circle (px, py, r) touches segment a-b.
static func circle_hits_segment(
	px: int, py: int, r: int, ax: int, ay: int, bx: int, by: int
) -> bool:
	var dx := bx - ax
	var dy := by - ay
	var fx := px - ax
	var fy := py - ay
	var len2 := dx * dx + dy * dy
	var t := fx * dx + fy * dy
	var r2 := r * r
	if len2 == 0 or t <= 0:
		return fx * fx + fy * fy <= r2
	if t >= len2:
		var gx := px - bx
		var gy := py - by
		return gx * gx + gy * gy <= r2
	var c := dx * fy - dy * fx
	return c * c <= r2 * len2


static func circle_hits_triangle(
	px: int, py: int, r: int, ax: int, ay: int, bx: int, by: int, cx: int, cy: int
) -> bool:
	if point_in_triangle(px, py, ax, ay, bx, by, cx, cy):
		return true
	return (
		circle_hits_segment(px, py, r, ax, ay, bx, by)
		or circle_hits_segment(px, py, r, bx, by, cx, cy)
		or circle_hits_segment(px, py, r, cx, cy, ax, ay)
	)
