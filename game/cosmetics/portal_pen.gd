class_name PortalPen
extends RefCounted
## Draws in a portal's own units for PortalPainter: HALF tall from the middle,
## the wall at x = 0 and the room toward -x (mirrored on the left wall), scaled
## to the real size. Every portal design is written in these units.

## Half the portal's height in pen units.
const HALF := 26.0

var ci: CanvasItem
var origin: Vector2
var scale: float
## +1 on the left wall (the room is to the right), -1 on the right wall.
var into: float
var alpha: float


func _init(p_ci: CanvasItem, p_origin: Vector2, half: float, p_into: float, a: float) -> void:
	ci = p_ci
	origin = p_origin
	scale = half / HALF
	into = p_into
	alpha = a


## A point in pen units, on the canvas.
func at(x: float, y: float) -> Vector2:
	return origin + Vector2(-into * x, y) * scale


## `c` with the pen's alpha (and `a` more) applied.
func col(c: Color, a: float = 1.0) -> Color:
	return Color(c, c.a * a * alpha)


func disc(x: float, y: float, r: float, c: Color) -> void:
	if r > 0.0:
		ci.draw_circle(at(x, y), r * scale, col(c))


func glow(x: float, y: float, r: float, c: Color, a: float) -> void:
	var radii := Vector2(r, r) * scale
	ci.draw_texture_rect(
		PortalPainter.bloom_texture(), Rect2(at(x, y) - radii, radii * 2.0), false, col(c, a)
	)


## Points of an ellipse around (cx, cy), turned by `rot`, on the canvas.
func ellipse(
	cx: float, cy: float, rx: float, ry: float, n: int, rot: float = 0.0
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var v := Vector2(cos(a) * rx, sin(a) * ry).rotated(rot)
		pts.append(at(cx + v.x, cy + v.y))
	return pts


func fill(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() >= 3 and _has_area(pts):
		ci.draw_colored_polygon(pts, col(c))


func outline(pts: PackedVector2Array, c: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col(c), maxf(width * scale, 1.0), true)


func line(x0: float, y0: float, x1: float, y1: float, c: Color, width: float) -> void:
	ci.draw_line(at(x0, y0), at(x1, y1), col(c), maxf(width * scale, 1.0), true)


## Godot logs an error for polygons with no area; a portal opening from a
## thin slit can have one for a frame.
static func _has_area(pts: PackedVector2Array) -> bool:
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) > 0.5
