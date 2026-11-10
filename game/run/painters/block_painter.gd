extends HazardPainter
## Block (Floating Isles, Ghost Doors): a rounded rock box. Fading blocks show
## their outline while they are safe, so players see where they come back.

const BlockHazard := preload("res://sim/hazards/block.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BlockHazard
	var theme := look.theme
	var r := Rect2(
		HazardLayer.at(h.x0, h.y0), HazardLayer.at(h.x1, h.y1) - HazardLayer.at(h.x0, h.y0)
	)
	var a: float = h.opacity() / float(SimTrig.ONE)
	if a < 1.0:
		c.draw_rect(r, Color(theme.spike, 0.45), false, 2.0, true)
	if a > 0.0:
		HazardLayer.rock_box(c, r, look, a)
