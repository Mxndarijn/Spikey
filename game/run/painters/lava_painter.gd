extends HazardPainter
## Lava Rise: the lava in the spike colour, the one colour that kills, with a
## lighter crest; and the cool stone in paper with a mint frost mark (safe).

const LavaHazard := preload("res://sim/hazards/lava.gd")

const WAVE := 3.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as LavaHazard
	var theme := look.theme
	var line := HazardLayer.px(h.line)
	var w := RoomView.W
	if h.line < SimConfig.KILL_BOTTOM:
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= w:
			pts.append(Vector2(x, line + sin(x / 22.0 + look.time * 4.0) * WAVE))
			x += 8.0
		pts.append(Vector2(w, RoomView.H + RoomView.SURROUND))
		pts.append(Vector2(0, RoomView.H + RoomView.SURROUND))
		c.draw_colored_polygon(pts, theme.spike)
		for i in range(0, int(w), 30):
			var cy := line + sin((i + 10) / 22.0 + look.time * 4.0) * WAVE - 1.0
			c.draw_set_transform(Vector2(i + 10.0, cy), 0.0, Vector2(1.0, 0.35))
			c.draw_circle(Vector2.ZERO, 9.0, theme.spike_edge)
			c.draw_set_transform(Vector2.ZERO)
	if h.stone_on:
		var p := HazardLayer.at(h.stone_x, h.stone_y)
		c.draw_set_transform(p, 0.2, Vector2(1.0, 0.8))
		c.draw_circle(Vector2.ZERO, 15.0, UiTokens.PANEL)
		c.draw_set_transform(Vector2.ZERO)
		for k in 3:
			var a := k * PI / 3.0 + look.time
			var d := Vector2(cos(a), sin(a)) * 7.0
			c.draw_line(p - d, p + d, UiTokens.SUCCESS, 3.0, true)
