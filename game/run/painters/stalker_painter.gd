extends RefCounted
## Stalker (Stalker Rail): a faint rail along the wall and the spike pair that
## slides on it, shaped like the wall spikes so it reads as one of them.


static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float) -> void:
	var bx := HazardLayer.px(h.x)
	var cy := HazardLayer.px(h.y)
	var dir := 1.0 if h.side == 0 else -1.0
	var depth := HazardLayer.px(h.DEPTH)
	var hb := HazardLayer.px(h.HALF_BASE)
	# The rail: a safe guide line, so not in the spike colour.
	var rail_x := bx + dir * 3.0
	var rail := Color(theme.world_accent, 0.35)
	c.draw_line(
		Vector2(rail_x, HazardLayer.px(h.MIN_Y) - hb * 2.0),
		Vector2(rail_x, HazardLayer.px(h.MAX_Y) + hb * 2.0),
		rail,
		2.0,
		true
	)
	# The carriage, then the two spikes; they twitch a little as they hunt.
	var twitch := sin(time * 18.0) * 0.8
	var carriage_x := bx if dir > 0.0 else bx - 6.0
	c.draw_rect(Rect2(carriage_x, cy - hb * 2.0, 6.0, hb * 4.0), theme.spike_edge)
	for s: float in [-1.0, 1.0]:
		var y: float = cy + s * hb
		var pts := PackedVector2Array(
			[
				Vector2(bx, y - hb),
				Vector2(bx + dir * (depth + twitch), y),
				Vector2(bx, y + hb),
			]
		)
		c.draw_colored_polygon(pts, theme.spike)
		pts.append(pts[0])
		c.draw_polyline(pts, theme.spike, 1.0, true)
		c.draw_line(
			Vector2(bx, y - hb),
			Vector2(bx + dir * (depth + twitch), y),
			theme.spike_edge,
			1.5,
			true
		)
