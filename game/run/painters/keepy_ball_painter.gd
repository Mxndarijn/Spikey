extends HazardPainter
## Keepy-Uppy ball: a soft ball in the world accent with a white shine
## ("beachball": white with coloured panels). Safe, never the spike colour.
## A heavy ball has a shaded bottom and a thicker rim; a ball waiting to drop
## in again is not drawn.

const KeepyBallHazard := preload("res://sim/hazards/keepy_ball.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as KeepyBallHazard
	if h.waiting > 0:
		return
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.x, h.y)
	var r := HazardLayer.px(h.RADIUS)
	var spin := time * 1.5 + HazardLayer.px(h.x) * 0.03
	if look.skin == "beachball":
		c.draw_circle(center, r, Color.WHITE)
		var colors: Array[Color] = [theme.world_accent, theme.glow, theme.world_accent]
		for i in 3:
			var a0 := spin + TAU * i / 3.0
			var pts := PackedVector2Array([center])
			for s in 9:
				var a := a0 + (TAU / 6.0) * s / 8.0
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			c.draw_colored_polygon(pts, colors[i])
		c.draw_circle(center, r * 0.18, Color.WHITE)
	else:
		c.draw_circle(center, r, theme.world_accent)
		c.draw_arc(center, r * 0.62, spin, spin + PI * 0.9, 16, Color(1, 1, 1, 0.35), 3.0, true)
	var heavy := h.gravity != h.GRAVITY
	if heavy:
		# Weight sits low: a shaded crescent along the bottom.
		c.draw_arc(
			center, r * 0.8, 0.2, PI - 0.2, 24, Color(theme.spike_edge, 0.35), r * 0.35, true
		)
	c.draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 3.5 if heavy else 2.0, true)
	c.draw_circle(center + Vector2(-r * 0.35, -r * 0.4), r * 0.16, Color(1, 1, 1, 0.8))
