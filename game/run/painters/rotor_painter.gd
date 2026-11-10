extends HazardPainter
## Rotor (Pinwheel): four tapered blades round a hub, all in the spike colour.

const RotorHazard := preload("res://sim/hazards/rotor.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as RotorHazard
	var theme := look.theme
	var center := HazardLayer.at(h.CENTER_X, h.center_y)
	var length := HazardLayer.px(h.BLADE_LENGTH) + HazardLayer.px(h.BLADE_HALF_W)
	var half := HazardLayer.px(h.BLADE_HALF_W)
	for i in h.BLADES:
		var a: float = h.blade_angle(i) * TAU / SimTrig.TURN
		var along := Vector2.RIGHT.rotated(a)
		var side := along.orthogonal()
		# Wide at the hub, a curved sail, a rounded tip.
		var pts := PackedVector2Array(
			[
				center + side * half * 1.2,
				center + along * length * 0.55 + side * half * 1.5,
				center + along * length * 0.92 + side * half * 0.9,
				center + along * length,
				center + along * length * 0.92 - side * half * 0.7,
				center + along * length * 0.5 - side * half * 0.8,
				center - side * half * 0.9,
			]
		)
		c.draw_colored_polygon(pts, theme.spike)
		pts.append(pts[0])
		c.draw_polyline(pts, theme.spike, 1.0, true)
		c.draw_line(
			center + side * half * 1.2,
			center + along * length * 0.55 + side * half * 1.5,
			theme.spike_edge,
			1.5,
			true
		)
	var hub := HazardLayer.px(h.HUB_RADIUS)
	c.draw_circle(center, hub, theme.spike, true, -1.0, true)
	c.draw_circle(center, hub, theme.spike_edge, false, 2.0, true)
	c.draw_circle(center, hub * 0.35, theme.spike_edge, true, -1.0, true)
