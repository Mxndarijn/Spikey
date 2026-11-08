class_name RoomThumb
extends ItemThumb
## A room kind's picture for the Rooms screen: a mini room in its preview world
## with a simple sketch of its hazard (the glyph from RoomInfo), drawn in that
## world's spike colour. A locked room is a faint ink silhouette on grey with
## a lock badge.

const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
const SILHOUETTE_ALPHA := 0.16

var glyph := "":
	set(value):
		glyph = value
		queue_redraw()
var locked := false:
	set(value):
		locked = value
		queue_redraw()


func _init() -> void:
	super()
	custom_minimum_size = Vector2(80, 96)


func _draw() -> void:
	if world == null or size.x < 8.0 or size.y < 8.0:
		return
	var r := Rect2(Vector2.ZERO, size).grow(-BORDER / 2.0)
	if locked:
		var pts := _rounded(r, CORNER)
		draw_colored_polygon(pts, UiTheme.DISABLED_FILL)
		var ink := Color(UiTokens.INK_LINE, SILHOUETTE_ALPHA)
		_draw_glyph(r, ink, ink)
		_outline(r, UiTokens.INK_LINE)
		var c := size / 2.0
		var b := minf(size.x, size.y) * 0.17
		draw_circle(c, b + 3.0, UiTokens.INK_LINE)
		draw_circle(c, b, UiTokens.PANEL)
		var s := b * 1.1
		draw_texture_rect(
			LOCK_ICON, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, UiTokens.INK_LINE
		)
		return
	super._draw()
	_draw_glyph(r, world.spike, world.spike_edge)
	_outline(r, UiTokens.INK_LINE)


## The hazard sketch, in a 90 x 96 design box scaled to the picture.
func _draw_glyph(r: Rect2, col: Color, edge: Color) -> void:
	var k := Vector2(r.size.x / 90.0, r.size.y / 96.0)
	var o := r.position
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
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
				var rr := (15.0 if i % 2 == 0 else 9.0) * k.x
				pts.append(c + Vector2.from_angle(TAU * i / 16.0) * rr)
			draw_colored_polygon(pts, col)
			draw_circle(c, 5.0 * k.x, edge)
		"cloud":
			# Clouds and bumpers are safe: white with an ink edge (ink silhouette when locked).
			var ring := col if locked else UiTokens.INK_LINE
			var fill := col if locked else UiTokens.PANEL
			for c in [[31, 50, 7], [43, 44, 9], [56, 48, 8]]:
				draw_circle(p.call(c[0], c[1]), c[2] * k.x + 2.0, ring)
			for c in [[31, 50, 7], [43, 44, 9], [56, 48, 8]]:
				draw_circle(p.call(c[0], c[1]), c[2] * k.x, fill)
		"rain":
			for c in [[30, 26], [50, 46], [64, 30]]:
				var at: Vector2 = p.call(c[0], c[1])
				draw_circle(at, 4.0 * k.x, col)
				_tri(
					at + Vector2(-4, 0) * k.x,
					at + Vector2(0, 9) * k.x,
					at + Vector2(4, 0) * k.x,
					col
				)
		"coins":
			for c in [[32, 40], [50, 52], [64, 38]]:
				draw_circle(
					p.call(c[0], c[1]), 7.0 * k.x, UiTokens.COIN_EDGE if not locked else col
				)
				draw_circle(p.call(c[0], c[1]), 5.0 * k.x, UiTokens.COIN if not locked else col)
		"crawl":
			for x in [34.0, 43.0, 52.0, 61.0]:
				draw_circle(p.call(x, 80), (6.0 if x == 61.0 else 5.0) * k.x, col)
		"bubbles":
			for c in [[34, 62, 8], [56, 44, 10]]:
				var tint := Color(UiTokens.PANEL, 0.25) if not locked else Color(col, col.a * 0.5)
				draw_circle(p.call(c[0], c[1]), c[2] * k.x, tint)
				draw_arc(
					p.call(c[0], c[1]),
					c[2] * k.x,
					0,
					TAU,
					20,
					UiTokens.PANEL if not locked else col,
					2.0,
					true
				)
		"dark":
			if not locked:
				draw_colored_polygon(_rounded(r, CORNER), Color(UiTokens.INK_900, 0.45))
				draw_circle(p.call(45, 50), 18.0 * k.x, Color(1, 1, 1, 0.18))
		"flip":
			var line := UiTokens.PANEL if not locked else col
			draw_line(p.call(45, 34), p.call(45, 62), line, 4.0, true)
			draw_polyline(
				PackedVector2Array([p.call(37, 54), p.call(45, 62), p.call(53, 54)]),
				line,
				4.0,
				true
			)
		"beam":
			draw_line(p.call(12, 48), p.call(78, 48), col, 5.0, true)
			draw_dashed_line(p.call(12, 64), p.call(78, 64), col, 2.0, 3.0, true)


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)


func _bar(r: Rect2, col: Color) -> void:
	draw_colored_polygon(_rounded(r, minf(r.size.x, r.size.y) / 2.0), col)
