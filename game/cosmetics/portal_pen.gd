class_name PortalPen
extends RefCounted
## Draws a portal's vortex disc for PortalPainter in the disc's own units: a
## circle of radius OUTER round (0, 0), y down, squashed sideways to SQUASH of
## its width. Disc points can turn with the spin; everything is scaled to the
## real size, mirrored per wall and faded by the pen's alpha.
##
## Shapes go out as plain triangle lists, so a strip that folds on itself (a
## fat arm near the eye) or one with no area (a portal just opening) never
## makes Godot log a polygon error.

## The disc's outer radius in disc units (the rim ring).
const OUTER := 66.0
## Width over height of the disc.
const SQUASH := 0.30

var ci: CanvasItem
var origin: Vector2
## Pixels per disc unit (already includes how open the portal is).
var scale: float
## +1 on the left wall, -1 on the right wall (mirrors the spin).
var into: float
## The disc's turn in radians.
var spin: float
var alpha: float


func _init(
	p_ci: CanvasItem, p_origin: Vector2, p_scale: float, p_into: float, p_spin: float, a: float
) -> void:
	ci = p_ci
	origin = p_origin
	scale = p_scale
	into = p_into
	spin = p_spin
	alpha = a


## A disc point on the canvas, squashed; turned with the spin when `turn`.
func at(x: float, y: float, turn: bool = true) -> Vector2:
	var v := Vector2(x, y)
	if turn:
		v = v.rotated(spin)
	return origin + Vector2(v.x * SQUASH * into, v.y) * scale


## A point on the rim at angle `a`, `r` units out (not turned).
func rim_point(a: float, r: float) -> Vector2:
	return at(cos(a) * r, sin(a) * r, false)


## `c` with the pen's alpha (and `a` more) applied.
func col(c: Color, a: float = 1.0) -> Color:
	return Color(c, c.a * a * alpha)


## A filled circle of the disc (squashed with it).
func circle(x: float, y: float, r: float, c: Color, turn: bool = true, n: int = 32) -> void:
	if r <= 0.0:
		return
	var pts := PackedVector2Array([at(x, y, turn)])
	for i in n:
		var a := TAU * i / n
		pts.append(at(x + cos(a) * r, y + sin(a) * r, turn))
	_fan(pts, c)


## A stroke `width` units wide along disc points `pts`, round ends when `caps`.
func stroke(
	pts: PackedVector2Array, width: float, c: Color, turn: bool = true, caps: bool = true
) -> void:
	var n := pts.size()
	if n < 2 or width <= 0.0:
		return
	var h := width * 0.5
	var verts := PackedVector2Array()
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-t.y, t.x) * h
		verts.append(at(pts[i].x + nrm.x, pts[i].y + nrm.y, turn))
		verts.append(at(pts[i].x - nrm.x, pts[i].y - nrm.y, turn))
	var idx := PackedInt32Array()
	for i in n - 1:
		var l := i * 2
		idx.append_array([l, l + 1, l + 2, l + 1, l + 3, l + 2])
	_tris(verts, idx, c)
	if caps:
		circle(pts[0].x, pts[0].y, h, c, turn, 12)
		circle(pts[n - 1].x, pts[n - 1].y, h, c, turn, 12)


## A square `s` units wide round a disc point (squashed and turned with it).
func square(x: float, y: float, s: float, c: Color) -> void:
	var h := s * 0.5
	_fan(
		PackedVector2Array(
			[at(x, y), at(x - h, y - h), at(x + h, y - h), at(x + h, y + h), at(x - h, y + h)]
		),
		c
	)


## Rim touches are drawn upright on the canvas (not squashed), sized in disc
## units. A filled ellipse round canvas point `p`, turned by `rot`.
func blob(p: Vector2, rx: float, ry: float, rot: float, c: Color, n: int = 14) -> void:
	var pts := PackedVector2Array([p])
	for i in n:
		var a := TAU * i / n
		pts.append(p + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot) * scale)
	_fan(pts, c)


## A filled shape from canvas points, fanned from its middle (convex, or a
## star round its centre).
func shape(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() >= 3:
		var mid := Vector2.ZERO
		for v in pts:
			mid += v
		var fan := PackedVector2Array([mid / pts.size()])
		fan.append_array(pts)
		_fan(fan, c)


func line(a: Vector2, b: Vector2, c: Color, width: float) -> void:
	ci.draw_line(a, b, col(c), maxf(width * scale, 1.0), true)


func polyline(pts: PackedVector2Array, c: Color, width: float) -> void:
	if pts.size() >= 2:
		ci.draw_polyline(pts, col(c), maxf(width * scale, 1.0), true)


## An outline round canvas point `p` (rx, ry in disc units, upright).
func ring(p: Vector2, rx: float, ry: float, c: Color, width: float, n: int = 32) -> void:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(p + Vector2(cos(a) * rx, sin(a) * ry) * scale)
	polyline(pts, c, width)


## Triangles from a centre (pts[0]) to the closed ring pts[1..].
func _fan(pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size() - 1
	if n < 2:
		return
	var idx := PackedInt32Array()
	for i in n:
		idx.append_array([0, 1 + i, 1 + (i + 1) % n])
	_tris(pts, idx, c)


func _tris(verts: PackedVector2Array, idx: PackedInt32Array, c: Color) -> void:
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(col(c))
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, verts, colors)
