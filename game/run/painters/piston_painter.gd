extends HazardPainter
## Piston (Piston Press): a metal housing in the wall. While warning, its face
## glows and a faint outline shows how far the ram will reach; once out, the
## ram is a rod in spike colour with a toothed nose.

const PistonHazard := preload("res://sim/hazards/piston.gd")

const HOUSING_W := 12.0
const TEETH := 3
const NOSE := 12.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as PistonHazard
	var theme := look.theme
	var time := look.time
	var y := HazardLayer.px(h.y)
	var half := HazardLayer.px(h.HALF_H)
	var base := HazardLayer.px(h.base_x())
	var dir := 1.0 if h.side == 0 else -1.0
	# Housing plate on the wall (safe, part of the wall).
	var hx := base if dir > 0.0 else base - HOUSING_W
	var housing := Rect2(hx, y - half - 6.0, HOUSING_W, half * 2.0 + 12.0)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(theme.world_accent, 0.85)
	plate.set_corner_radius_all(4)
	plate.border_color = Color(Color.WHITE, 0.6)
	plate.set_border_width_all(1)
	plate.anti_aliasing = true
	plate.draw(c.get_canvas_item(), housing)

	var glow: float = h.glow() / float(SimTrig.ONE)
	if glow > 0.0:
		# Pulsing face and the reach outline: a clear warning before the slam.
		var pulse := 0.55 + 0.45 * sin(time * 24.0)
		var face := Rect2(hx, y - half, HOUSING_W, half * 2.0)
		c.draw_rect(face, Color(theme.spike_edge, (0.4 + 0.6 * glow) * pulse), true)
		var reach := HazardLayer.px(h.reach)
		var x0 := minf(base, base + dir * reach)
		var outline := Rect2(x0, y - half, reach, half * 2.0)
		c.draw_rect(outline, Color(theme.spike, 0.25 + 0.35 * glow), false, 2.0, true)

	var ext := HazardLayer.px(h.extent())
	if ext <= 0.0:
		return
	var tip := base + dir * ext
	var nose_x := tip - dir * minf(NOSE, ext)
	var body := Rect2(minf(base, nose_x), y - half * 0.7, absf(nose_x - base), half * 1.4)
	if body.size.x > 0.5:
		HazardLayer.rock_box(c, body, look)
	# Nose: a plate with teeth pointing into the room.
	var head := Rect2(minf(nose_x, nose_x - dir * 6.0), y - half, 6.0, half * 2.0)
	c.draw_rect(head, theme.spike, true)
	var tooth_h := half * 2.0 / TEETH
	for i in TEETH:
		var ty := y - half + tooth_h * i
		var pts := PackedVector2Array(
			[Vector2(nose_x, ty), Vector2(tip, ty + tooth_h / 2.0), Vector2(nose_x, ty + tooth_h)]
		)
		c.draw_colored_polygon(pts, theme.spike)
		pts.append(pts[0])
		c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_line(
		Vector2(head.position.x, y - half + 1.0),
		Vector2(head.end.x, y - half + 1.0),
		theme.spike_edge,
		2.0,
		true
	)
