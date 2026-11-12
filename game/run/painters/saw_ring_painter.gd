extends HazardPainter
## Saw Ring: a faint guide circle (or oval) per ring (safe) and the spinning
## saws on it. An inner ring spins the other way.

const SawRingHazard := preload("res://sim/hazards/saw_ring.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as SawRingHazard
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.center_x, h.center_y)
	var squash := float(h.ry_num) / float(h.ry_den)
	var guide := HazardLayer.guide(theme)
	_guide(c, center, HazardLayer.px(h.radius), squash, guide)
	if h.inner_count > 0:
		_guide(c, center, HazardLayer.px(h.inner_radius), squash, guide)
	c.draw_circle(center, 4.0, Color(theme.world_accent, 0.4), true, -1.0, true)
	for i in h.xs.size():
		var spin := time * 6.0 * h.dir * (1.0 if i < h.count else -1.0)
		var r := HazardLayer.px(h.saw_r(i))
		HazardLayer.spiky_ball(c, HazardLayer.at(h.xs[i], h.ys[i]), r, look, spin)


static func _guide(c: CanvasItem, center: Vector2, ring: float, squash: float, col: Color) -> void:
	if squash == 1.0:
		c.draw_arc(center, ring, 0.0, TAU, 64, col, 2.0, true)
		return
	var pts := PackedVector2Array()
	for k in 65:
		var a := TAU * k / 64.0
		pts.append(center + Vector2(cos(a) * ring, sin(a) * ring * squash))
	c.draw_polyline(pts, col, 2.0, true)
