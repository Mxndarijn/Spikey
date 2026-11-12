extends HazardPainter
## Stalker (Stalker Rail): a faint rail along the wall and the spike pair that
## slides on it, shaped like the wall spikes so it reads as one of them.

const StalkerHazard := preload("res://sim/hazards/stalker.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as StalkerHazard
	var theme := look.theme
	var time := look.time
	var bx := HazardLayer.px(h.x)
	var cy := HazardLayer.px(h.y)
	var dir := 1.0 if h.side == 0 else -1.0
	var depth := HazardLayer.px(h.DEPTH)
	var hb := HazardLayer.px(h.HALF_BASE)
	# The rail: a safe guide line, so not in the spike colour. It runs from the
	# ceiling band to the floor band, so it never ends in the air.
	var rail_x := bx + dir * 3.0
	var rail := HazardLayer.guide(theme)
	c.draw_line(Vector2(rail_x, 0.0), Vector2(rail_x, RoomView.H), rail, 2.0, true)
	# The carriage, then the two spikes, drawn like the wall spikes (two-tone,
	# rounded tip) so it reads as one of them; they twitch a little as they hunt.
	var twitch := sin(time * 18.0) * 0.8
	var carriage_x := bx if dir > 0.0 else bx - 6.0
	c.draw_rect(Rect2(carriage_x, cy - hb * 2.0, 6.0, hb * 4.0), theme.spike_edge)
	for s: float in [-1.0, 1.0]:
		var base := Vector2(bx, cy + s * hb)
		var d := Vector2(dir, 0.0)
		var pts := RoomView.spike_points(base, d, hb, depth + twitch)
		c.draw_colored_polygon(pts, theme.spike)
		c.draw_colored_polygon(
			RoomView.spike_lit_points(base, d, hb, depth + twitch), theme.spike_edge
		)
		if look.ink:
			c.draw_polyline(pts, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W, true)
