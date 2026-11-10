extends HazardPainter
## Bouncer (Bramble Ball; Pumpkin Bounce skin): a spiked ball that rolls as it
## flies.

const BouncerHazard := preload("res://sim/hazards/bouncer.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BouncerHazard
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.x, h.y)
	var r := HazardLayer.px(h.RADIUS)
	if look.skin == "pumpkin":
		# Ribbed pumpkin in the spike colour, with a small stem.
		for i in 3:
			var w := r * (1.0 - i * 0.25)
			c.draw_set_transform(center, 0.0, Vector2(w / r, 1.0))
			c.draw_circle(Vector2.ZERO, r, theme.spike if i == 0 else Color(theme.spike_edge, 0.35))
		c.draw_set_transform(Vector2.ZERO)
		c.draw_rect(Rect2(center + Vector2(-3, -r - 6), Vector2(6, 8)), theme.spike_edge)
		return
	HazardLayer.spiky_ball(c, center, r, look, time * 2.0 * signf(h.vx))
