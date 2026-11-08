class_name RoomThumb
extends ItemThumb
## A room kind's picture for the Rooms screens, flat (no outline): a rounded
## mini room in its preview world (sky, sun, two hills, spike rows on the
## ceiling and floor) with a simple sketch of its hazard (the glyph from
## RoomInfo) in that world's spike colour. A locked room is greyed and faded
## with a small paper disc and a lock on it.

const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
## A locked picture's opacity.
const LOCKED_ALPHA := 0.55
const LOCK_DISC := 16.0
const LOCK_SIZE := 16.0

var glyph := "":
	set(value):
		glyph = value
		queue_redraw()
var locked := false:
	set(value):
		locked = value
		queue_redraw()
## The picture's corner radius (16 on cards, 22 on the room detail).
var radius := 16.0:
	set(value):
		radius = value
		queue_redraw()

var _clip := PackedVector2Array()


func _init() -> void:
	super()
	custom_minimum_size = Vector2(80, 76)


func _draw() -> void:
	if world == null or size.x < 8.0 or size.y < 8.0:
		return
	var r := Rect2(Vector2.ZERO, size)
	var w := size.x
	var h := size.y
	_clip = _round_rect(r, radius)
	var cols := PackedColorArray()
	for p in _clip:
		cols.append(_c(_sky_at(p.y / h)))
	draw_polygon(_clip, cols)
	draw_circle(Vector2(w * 0.72, h * 0.3), h * 0.14, _c(world.glow))
	var far := PackedVector2Array([Vector2(0, h * 0.78)])
	far.append_array(
		_quad(Vector2(0, h * 0.78), Vector2(w * 0.3, h * 0.66), Vector2(w * 0.6, h * 0.76))
	)
	far.append_array(
		_quad(Vector2(w * 0.6, h * 0.76), Vector2(w * 0.9, h * 0.86), Vector2(w, h * 0.72))
	)
	far.append_array([Vector2(w, h), Vector2(0, h)])
	_fill(far, world.hill_far)
	var near := PackedVector2Array([Vector2(0, h * 0.88)])
	near.append_array(_quad(Vector2(0, h * 0.88), Vector2(w * 0.4, h * 0.8), Vector2(w, h * 0.86)))
	near.append_array([Vector2(w, h), Vector2(0, h)])
	_fill(near, world.hill_near)
	_draw_glyph(r, _c(world.spike), _c(world.spike_edge))
	var n := maxi(5, int(w / 14.0))
	var step := w / n
	var tip := h * 0.09
	for i in n:
		var x := i * step
		_fill(
			PackedVector2Array([Vector2(x, 0), Vector2(x + step / 2.0, tip), Vector2(x + step, 0)]),
			world.spike
		)
		_fill(
			PackedVector2Array(
				[Vector2(x, h), Vector2(x + step / 2.0, h - tip), Vector2(x + step, h)]
			),
			world.spike
		)
	if locked:
		var c := size / 2.0
		draw_circle(c, LOCK_DISC, UiTokens.PANEL)
		var s := Vector2(LOCK_SIZE, LOCK_SIZE)
		draw_texture_rect(LOCK_ICON, Rect2(c - s / 2.0, s), false, UiTokens.INK_LINE)


## A colour as drawn: greyed and faded when the room is locked.
func _c(col: Color) -> Color:
	if not locked:
		return col
	var l := col.get_luminance()
	return Color(l, l, l, col.a * LOCKED_ALPHA)


## Fills a polygon cut to the rounded picture.
func _fill(poly: PackedVector2Array, col: Color) -> void:
	# The shapes are simple and lie across the edge, so the cut has no holes.
	for part in Geometry2D.intersect_polygons(poly, _clip):
		draw_colored_polygon(part, _c(col))


## Points along a quadratic curve from `a` (excluded) to `b` with control `k`.
static func _quad(a: Vector2, k: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(1, 11):
		var t := i / 10.0
		pts.append(a.lerp(k, t).lerp(k.lerp(b, t), t))
	return pts


static func _round_rect(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) / 2.0 - 0.5)
	var corners := [
		[r.position + Vector2(r.size.x - rad, rad), -PI / 2.0],
		[r.end - Vector2(rad, rad), 0.0],
		[r.position + Vector2(rad, r.size.y - rad), PI / 2.0],
		[r.position + Vector2(rad, rad), PI],
	]
	for c: Array in corners:
		for k in 9:
			pts.append((c[0] as Vector2) + Vector2.from_angle(c[1] + PI / 2.0 * k / 8.0) * rad)
	return pts


## The hazard sketch, in a 90 x 96 design box scaled to the picture.
func _draw_glyph(r: Rect2, col: Color, edge: Color) -> void:
	var k := Vector2(r.size.x / 90.0, r.size.y / 96.0)
	var u := minf(k.x, k.y)
	var o := r.position
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var white := _c(UiTokens.PANEL)
	# Two wall spikes every room has.
	_tri(p.call(0, 34), p.call(12, 40), p.call(0, 46), col)
	_tri(p.call(90, 52), p.call(78, 58), p.call(90, 64), col)
	match glyph:
		"extra":
			for y in [52.0, 66.0]:
				_tri(p.call(0, y), p.call(12, y + 6), p.call(0, y + 12), col)
			for y in [24.0, 66.0]:
				_tri(p.call(90, y), p.call(78, y + 6), p.call(90, y + 12), col)
		"blocks":
			_bar(Rect2(p.call(20, 34), Vector2(30, 10) * k), col)
			_bar(Rect2(p.call(46, 58), Vector2(28, 10) * k), col)
		"cols":
			_bar(Rect2(p.call(30, 10), Vector2(8, 34) * k), col)
			_bar(Rect2(p.call(30, 58), Vector2(8, 30) * k), col)
			_bar(Rect2(p.call(54, 10), Vector2(8, 18) * k), col)
			_bar(Rect2(p.call(54, 42), Vector2(8, 46) * k), col)
		"ball":
			var c: Vector2 = p.call(54, 48)
			var pts := PackedVector2Array()
			for i in 16:
				var rr := (15.0 if i % 2 == 0 else 9.0) * u
				pts.append(c + Vector2.from_angle(TAU * i / 16.0) * rr)
			draw_colored_polygon(pts, col)
			draw_circle(c, 5.0 * u, edge)
		"cloud":
			# Clouds and bumpers are safe: plain white puffs.
			for c in [[31, 50, 7], [43, 44, 9], [56, 48, 8]]:
				draw_circle(p.call(c[0], c[1]), c[2] * u, white)
		"rain":
			for c in [[30, 26], [50, 46], [64, 30]]:
				var at: Vector2 = p.call(c[0], c[1])
				draw_circle(at, 4.0 * u, col)
				_tri(at + Vector2(-4, 0) * u, at + Vector2(0, 9) * u, at + Vector2(4, 0) * u, col)
		"coins":
			for c in [[32, 40], [50, 52], [64, 38]]:
				draw_circle(p.call(c[0], c[1]), 6.0 * u, _c(UiTokens.COIN))
		"crawl":
			for x in [34.0, 43.0, 52.0, 61.0]:
				draw_circle(p.call(x, 80), (6.0 if x == 61.0 else 5.0) * u, col)
		"bubbles":
			for c in [[34, 62, 8], [56, 44, 10]]:
				draw_circle(p.call(c[0], c[1]), c[2] * u, Color(white, white.a * 0.25))
				draw_arc(p.call(c[0], c[1]), c[2] * u, 0, TAU, 20, white, 2.0, true)
		"dark":
			draw_colored_polygon(_clip, _c(Color(UiTokens.INK_900, 0.45)))
			draw_circle(p.call(45, 50), 18.0 * u, _c(Color(1, 1, 1, 0.18)))
		"flip":
			draw_line(p.call(45, 34), p.call(45, 62), white, 4.0, true)
			draw_polyline(
				PackedVector2Array([p.call(37, 54), p.call(45, 62), p.call(53, 54)]),
				white,
				4.0,
				true
			)
		"beam":
			draw_line(p.call(12, 48), p.call(78, 48), col, 5.0, true)
			draw_dashed_line(p.call(12, 64), p.call(78, 64), col, 2.0, 3.0, true)


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)


func _bar(r: Rect2, col: Color) -> void:
	draw_colored_polygon(ItemThumb._rounded(r, minf(r.size.x, r.size.y) / 2.0), col)
