extends HazardPainter
## Rotor (Pinwheel): tapered blades round each hub, all in the spike colour.

const RotorHazard := preload("res://sim/hazards/rotor.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as RotorHazard
	for hub in h.hubs:
		_paint_hub(c, h, hub, look.theme)


func _paint_hub(c: CanvasItem, h: RotorHazard, hub: int, theme: ThemeDef) -> void:
	var center := HazardLayer.at(h.hub_x(hub), h.hub_y(hub))
	var length := HazardLayer.px(h.blade_length) + HazardLayer.px(h.half_w)
	var half := HazardLayer.px(h.half_w)
	for i in h.blades:
		var a: float = h.blade_angle(hub, i) * TAU / SimTrig.TURN
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
	var radius := HazardLayer.px(h.hub_radius)
	c.draw_circle(center, radius, theme.spike, true, -1.0, true)
	c.draw_circle(center, radius, theme.spike_edge, false, 2.0, true)
	c.draw_circle(center, radius * 0.35, theme.spike_edge, true, -1.0, true)
