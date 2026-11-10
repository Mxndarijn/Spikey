extends HazardPainter
## Bubble (Bubble Lift): a clear wobbling bubble with a white rim and shine.
## Safe, so never in the spike colour. A carrying bubble glows brighter.

const BubbleHazard := preload("res://sim/hazards/bubble.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BubbleHazard
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.x, h.y)
	var r := HazardLayer.px(h.RADIUS)
	var wobble := sin(time * 5.0 + h.lane * 1.7) * 0.05
	c.draw_set_transform(center, 0.0, Vector2(1.0 + wobble, 1.0 - wobble))
	var fill := Color(theme.glow, 0.32 if h.carrying else 0.16)
	c.draw_circle(Vector2.ZERO, r, fill)
	c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.75), 2.0, true)
	# Shine.
	c.draw_arc(Vector2.ZERO, r * 0.7, PI * 1.1, PI * 1.45, 12, Color(1, 1, 1, 0.8), 3.0, true)
	c.draw_circle(Vector2(r * 0.35, -r * 0.45), r * 0.1, Color(1, 1, 1, 0.85))
	c.draw_set_transform(Vector2.ZERO)
