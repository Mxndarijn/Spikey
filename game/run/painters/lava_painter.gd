extends HazardPainter
## Lava Rise: the lava (or the Crusher's spiked slab) in the spike colour, the
## one colour that kills, with a lighter crest; and the cool stone in paper
## with a mint frost mark (safe).

const LavaHazard := preload("res://sim/hazards/lava.gd")

const WAVE := 3.0
const SPIKE_HALF := 20.0
const SPIKE_DEPTH := 26.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as LavaHazard
	var theme := look.theme
	var line := HazardLayer.px(h.line)
	var w := RoomView.W
	if h.mode == LavaHazard.Mode.CEILING:
		if h.line > SimConfig.KILL_TOP:
			var base := line - SPIKE_DEPTH
			c.draw_rect(
				Rect2(
					-RoomView.SURROUND,
					-RoomView.SURROUND,
					w + RoomView.SURROUND * 2.0,
					base + RoomView.SURROUND
				),
				theme.spike
			)
			for x in range(12, int(w), 44):
				c.draw_rect(Rect2(x, base - 16.0, 20.0, 5.0), Color(theme.spike_edge, 0.8))
			for i in 9:
				var cx := w / 9.0 * (i + 0.5)
				var pts := PackedVector2Array(
					[
						Vector2(cx - SPIKE_HALF, base),
						Vector2(cx, line),
						Vector2(cx + SPIKE_HALF, base)
					]
				)
				c.draw_colored_polygon(pts, theme.spike)
				c.draw_colored_polygon(
					PackedVector2Array(
						[Vector2(cx, base), Vector2(cx, line), Vector2(cx + SPIKE_HALF, base)]
					),
					theme.spike_edge
				)
	elif h.line < SimConfig.KILL_BOTTOM:
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
