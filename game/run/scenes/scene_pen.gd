class_name ScenePen
extends RefCounted
## Draws the flat room scenes on a canvas item in room px (360 x 640, y down),
## like the design boards' SVG: filled shapes, circles, ellipses, rounded
## rects and round-capped lines, under an optional transform.
##
## Filled shapes go out as triangle lists, so a shape that cannot be
## triangulated is skipped instead of logging an engine error. With no canvas
## (or `record` on) every shape's bounds and colour are kept in `shapes`, so
## tests can check what sits behind the spikes.

const W := 360.0
const H := 640.0

## Where shapes go; null only records.
var canvas: CanvasItem
var record := false
## [{rect: Rect2, color: Color, kind, pts, width}] in room px, when recording:
## kind is "fill" (pts: the outline), "line" (pts, width) or "circle"
## (pts: [centre], width: the diameter).
var shapes: Array[Dictionary] = []
## The room's current sky stops (top, mid, bottom) and where the top blend ends.
var sky: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE]
var sky_split := 0.62
var _xf := Transform2D.IDENTITY
var _stack: Array[Transform2D] = []


func _init(p_canvas: CanvasItem = null, p_record: bool = false) -> void:
	canvas = p_canvas
	record = p_record or p_canvas == null


## Shapes drawn after this are moved by `t` (on top of the current transform)
## until pop(). Like SVG's <g transform="...">.
func push(t: Transform2D) -> void:
	_stack.append(_xf)
	_xf = _xf * t


func pop() -> void:
	_xf = _stack.pop_back()


## translate(x y) rotate(deg) scale(sx sy), the SVG way.
static func place(
	x: float, y: float, deg: float = 0.0, sx: float = 1.0, sy: float = 1.0
) -> Transform2D:
	return Transform2D(deg_to_rad(deg), Vector2(sx, sy), 0.0, Vector2(x, y))


## rotate(deg cx cy).
static func turn_about(deg: float, cx: float, cy: float) -> Transform2D:
	var c := Vector2(cx, cy)
	return Transform2D(0.0, c) * Transform2D(deg_to_rad(deg), Vector2.ZERO) * Transform2D(0.0, -c)


## The sky's colour at height y (for cut-outs that must match it).
func sky_at(y: float) -> Color:
	var split := H * sky_split
	if y <= split:
		return sky[0].lerp(sky[1], clampf(y / split, 0.0, 1.0))
	return sky[1].lerp(sky[2], clampf((y - split) / (H - split), 0.0, 1.0))


## The sky: a blend from the top stop to the mid stop down to sky_split, then
## to the bottom stop.
func paint_sky() -> void:
	var split := H * sky_split
	_band(0.0, split, sky[0], sky[1])
	_band(split, H, sky[1], sky[2])


func _band(y0: float, y1: float, c0: Color, c1: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, y0), Vector2(W, y0), Vector2(W, y1), Vector2(0, y1)])
	_note(Rect2(0, y0, W, y1 - y0), c0)
	_note(Rect2(0, y0, W, y1 - y0), c1)
	if canvas != null:
		canvas.draw_polygon(_xf * pts, PackedColorArray([c0, c0, c1, c1]))


## A filled outline (any simple polygon, convex or not).
func fill(pts: PackedVector2Array, col: Color) -> void:
	var p := _clean(_xf * pts, true)
	if p.size() < 3:
		return
	_note(_bounds(p, 0.0), col, "fill", p)
	if canvas == null:
		return
	var idx := Geometry2D.triangulate_polygon(p)
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), idx, p, PackedColorArray([col])
	)
	# No 2D MSAA in the Compatibility renderer: an anti-aliased outline
	# smooths the stair-stepped edge of opaque shapes.
	if col.a >= 1.0:
		var o := p.duplicate()
		o.append(p[0])
		canvas.draw_polyline(o, col, 1.0, true)


func circle(c: Vector2, r: float, col: Color) -> void:
	if r <= 0.0:
		return
	var k := _scale()
	var at := _xf * c
	_note(
		Rect2(at - Vector2(r, r) * k, Vector2(r, r) * 2.0 * k),
		col,
		"circle",
		PackedVector2Array([at]),
		r * k * 2.0
	)
	if canvas != null:
		canvas.draw_circle(at, r * k, col, true, -1.0, true)


## An ellipse turned `deg` degrees about its centre.
func ellipse(c: Vector2, rx: float, ry: float, col: Color, deg: float = 0.0) -> void:
	fill(ellipse_points(c, rx, ry, deg), col)


static func ellipse_points(
	c: Vector2, rx: float, ry: float, deg: float = 0.0, from: float = 0.0, to: float = TAU
) -> PackedVector2Array:
	var n := clampi(ceili((rx + ry) * absf(to - from) / 6.0), 10, 64)
	var pts := PackedVector2Array()
	var rot := deg_to_rad(deg)
	var closed := is_equal_approx(absf(to - from), TAU)
	for i in n if closed else n + 1:
		var a := from + (to - from) * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


## A rect with rounded corners (radius r), like SVG's <rect rx>.
func rect(x: float, y: float, w: float, h: float, col: Color, r: float = 0.0) -> void:
	fill(rect_points(x, y, w, h, r), col)


static func rect_points(
	x: float, y: float, w: float, h: float, r: float = 0.0
) -> PackedVector2Array:
	r = clampf(r, 0.0, minf(w, h) / 2.0)
	if r <= 0.01:
		return PackedVector2Array(
			[Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
		)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(x + w - r, y + r), -PI / 2.0],
		[Vector2(x + w - r, y + h - r), 0.0],
		[Vector2(x + r, y + h - r), PI / 2.0],
		[Vector2(x + r, y + r), PI],
	]
	for corner: Array in corners:
		for i in 5:
			pts.append(corner[0] + Vector2.from_angle(corner[1] + PI / 2.0 * i / 4.0) * r)
	return pts


## A line through `pts`, `width` px wide, with round ends (SVG stroke-linecap round).
func stroke(pts: PackedVector2Array, col: Color, width: float, round_caps: bool = true) -> void:
	var p := _clean(_xf * pts, false)
	if p.size() < 2:
		return
	var w := width * _scale()
	_note(_bounds(p, w / 2.0), col, "line", p, w)
	if canvas == null:
		return
	canvas.draw_polyline(p, col, w, true)
	if round_caps and col.a >= 1.0 and w > 1.5:
		canvas.draw_circle(p[0], w / 2.0, col, true, -1.0, true)
		canvas.draw_circle(p[p.size() - 1], w / 2.0, col, true, -1.0, true)


func line(x0: float, y0: float, x1: float, y1: float, col: Color, width: float) -> void:
	stroke(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1)]), col, width)


## A circle outline.
func ring(c: Vector2, r: float, col: Color, width: float) -> void:
	var pts := ellipse_points(c, r, r)
	pts.append(pts[0])
	stroke(pts, col, width, false)


func _scale() -> float:
	return absf(_xf.get_scale().x)


func _note(
	r: Rect2,
	col: Color,
	kind: String = "fill",
	pts: PackedVector2Array = PackedVector2Array(),
	width: float = 0.0
) -> void:
	if record:
		shapes.append({"rect": r, "color": col, "kind": kind, "pts": pts, "width": width})


## Whether a recorded shape covers point q.
static func covers(shape: Dictionary, q: Vector2) -> bool:
	var pts: PackedVector2Array = shape.pts
	var w: float = shape.width
	match shape.kind:
		"fill":
			return pts.size() >= 3 and Geometry2D.is_point_in_polygon(q, pts)
		"circle":
			return pts.size() == 1 and q.distance_to(pts[0]) <= w / 2.0
		"line":
			for i in pts.size() - 1:
				var c := Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])
				if c.distance_to(q) <= w / 2.0:
					return true
	return false


static func _bounds(p: PackedVector2Array, pad: float) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r.grow(pad)


## Drops repeated points (they can break triangulation); for a filled shape
## also the closing point that repeats the first.
static func _clean(p: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(v) > 0.0001:
			out.append(v)
	if closed and out.size() > 2 and out[0].distance_squared_to(out[out.size() - 1]) <= 0.0001:
		out.remove_at(out.size() - 1)
	return out
