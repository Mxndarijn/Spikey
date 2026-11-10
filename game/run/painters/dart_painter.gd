extends HazardPainter
## Hunter Spike (and Cupid Lanes, skin "cupid"): while warning, a spike glows on
## the wall it fires from and a dashed lane line crosses the room; then the dart
## (or arrow) flies along it. Deadly parts in spike colour. Cupid pairs warn
## and fly on two lanes at once.

const DartHazard := preload("res://sim/hazards/dart.gd")

const LAUNCHER := 18.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as DartHazard
	for lane: int in h.shot_lanes():
		_lane(c, h, look, HazardLayer.px(lane))


func _lane(c: CanvasItem, h: DartHazard, look: HazardLook, y: float) -> void:
	var theme := look.theme
	var time := look.time
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var dir := 1.0 if h.side == 0 else -1.0
	var wall := 0.0 if h.side == 0 else w
	var cupid := h.lanes
	var st: int = h.state
	if st == h.State.GLOW:
		var g: float = h.glow() / float(SimTrig.ONE)
		var flash := 0.5 + 0.5 * sin(time * (16.0 + 20.0 * g))
		var lane := Color(theme.spike, (0.3 + 0.45 * g) * (0.55 + 0.45 * flash))
		c.draw_dashed_line(Vector2(wall, y), Vector2(w - wall, y), lane, 2.0, 10.0, true, true)
		if cupid:
			c.draw_rect(Rect2(0, y - 10.0, w, 20.0), Color(theme.spike, 0.08 + 0.1 * flash), true)
		var halo := Color(theme.spike_edge, 0.25 + 0.5 * g * flash)
		c.draw_circle(Vector2(wall + dir * 8.0, y), 14.0 + 4.0 * g, halo, true, -1.0, true)
		_launcher(c, wall, y, dir, theme)
	elif st == h.State.FLY:
		var tip := HazardLayer.px(h.x)
		var tail := HazardLayer.px(h.tail_x())
		if cupid:
			_arrow(c, tip, tail, y, dir, theme)
		else:
			_dart(c, tip, tail, y, dir, theme)


static func _launcher(c: CanvasItem, wall: float, y: float, dir: float, theme: ThemeDef) -> void:
	var pts := PackedVector2Array(
		[Vector2(wall, y - 10.0), Vector2(wall + dir * LAUNCHER, y), Vector2(wall, y + 10.0)]
	)
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike_edge, 1.5, true)


static func _dart(
	c: CanvasItem, tip: float, tail: float, y: float, dir: float, theme: ThemeDef
) -> void:
	# A long spike with a motion streak behind it.
	var streak := Color(theme.spike, 0.25)
	c.draw_line(Vector2(tail - dir * 24.0, y), Vector2(tail, y), streak, 3.0, true)
	var pts := PackedVector2Array(
		[
			Vector2(tail, y - 6.0),
			Vector2(tip, y),
			Vector2(tail, y + 6.0),
			Vector2(tail + dir * 5.0, y)
		]
	)
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_line(
		Vector2(tail + dir * 6.0, y - 1.0),
		Vector2(tip - dir * 4.0, y - 1.0),
		theme.spike_edge,
		1.5,
		true
	)


static func _arrow(
	c: CanvasItem, tip: float, tail: float, y: float, dir: float, theme: ThemeDef
) -> void:
	# Shaft, a heart-shaped head and fletching, all deadly.
	c.draw_line(Vector2(tail, y), Vector2(tip - dir * 8.0, y), theme.spike, 3.0, true)
	var hx := tip - dir * 6.0
	c.draw_circle(Vector2(hx - dir * 2.0, y - 3.0), 4.0, theme.spike, true, -1.0, true)
	c.draw_circle(Vector2(hx - dir * 2.0, y + 3.0), 4.0, theme.spike, true, -1.0, true)
	var head := PackedVector2Array(
		[Vector2(hx - dir * 3.0, y - 6.0), Vector2(tip, y), Vector2(hx - dir * 3.0, y + 6.0)]
	)
	c.draw_colored_polygon(head, theme.spike)
	for s: float in [-1.0, 1.0]:
		var f := PackedVector2Array(
			[
				Vector2(tail, y),
				Vector2(tail - dir * 4.0, y + s * 7.0),
				Vector2(tail + dir * 6.0, y + s * 6.0),
				Vector2(tail + dir * 8.0, y),
			]
		)
		c.draw_colored_polygon(f, theme.spike)
		c.draw_line(
			Vector2(tail, y), Vector2(tail + dir * 6.0, y + s * 6.0), theme.spike_edge, 1.0, true
		)
