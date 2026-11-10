extends HazardPainter
## Saw Ring: a faint guide circle (safe) and the spinning saws on it.

const SawRingHazard := preload("res://sim/hazards/saw_ring.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as SawRingHazard
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.CENTER_X, h.center_y)
	var ring := HazardLayer.px(h.radius)
	c.draw_arc(center, ring, 0.0, TAU, 64, Color(theme.world_accent, 0.25), 2.0, true)
	c.draw_circle(center, 4.0, Color(theme.world_accent, 0.4), true, -1.0, true)
	var r := HazardLayer.px(h.SAW_RADIUS)
	for i in h.xs.size():
		HazardLayer.spiky_ball(c, HazardLayer.at(h.xs[i], h.ys[i]), r, look, time * 6.0 * h.dir)
