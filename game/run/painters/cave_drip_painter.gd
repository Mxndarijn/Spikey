extends HazardPainter
## Cave Tunnel's drip: before it falls, its point glints (two spike-edge rings
## that tighten as the drop nears); then a small spiked drop falls straight
## down, in the spike colour, no bigger than what kills.

const CaveDripHazard := preload("res://sim/hazards/cave_drip.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as CaveDripHazard
	var theme := look.theme
	var r := HazardLayer.px(h.RADIUS)
	if h.eta >= 0:
		var tip := HazardLayer.at(h.x, h.tip_y)
		var near := 1.0 - float(h.eta) / h.GLINT
		var pulse := 0.5 + 0.5 * sin(look.time * 12.0)
		c.draw_arc(tip, 8.0 + 6.0 * (1.0 - near), 0.0, TAU, 24, theme.spike_edge, 3.0, true)
		c.draw_arc(
			tip, 15.0 + 4.0 * pulse, 0.0, TAU, 32, Color(theme.spike_edge, 0.6 * near), 2.0, true
		)
	if not h.falling:
		return
	var p := HazardLayer.at(h.x, h.y)
	# A round drop with a point on top, all inside the hit circle.
	c.draw_circle(p + Vector2(0.0, r * 0.25), r * 0.75, theme.spike, true, -1.0, true)
	c.draw_colored_polygon(
		PackedVector2Array(
			[p + Vector2(-r * 0.6, 0.0), p + Vector2(0.0, -r), p + Vector2(r * 0.6, 0.0)]
		),
		theme.spike
	)
	c.draw_circle(p + Vector2(-r * 0.25, r * 0.05), r * 0.22, theme.spike_edge, true, -1.0, true)
	if look.ink:
		c.draw_arc(p, r, 0.0, TAU, 20, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W, true)
