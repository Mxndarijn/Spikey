extends HazardPainter
## Stalactite Run: dripping rock. A stalactite hangs from the top and a
## stalagmite stands from the bottom, both with bumpy, tapering sides and a
## lighter ridge, in spike colour. Water drips (safe, white) fall from the tip.

const StalactiteHazard := preload("res://sim/hazards/stalactite.gd")

const STEPS := 14
const TAPER := 18.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as StalactiteHazard
	var theme := look.theme
	var time := look.time
	var x := HazardLayer.px(h.x)
	var half := HazardLayer.px(h.HALF_W)
	var top_tip := HazardLayer.px(h.top_tip())
	var bottom_tip := HazardLayer.px(h.bottom_tip())
	var floor_y := HazardLayer.px(SimConfig.WORLD_H)
	_rock(c, x, half, 0.0, top_tip, theme, 1.0)
	_rock(c, x, half, floor_y, bottom_tip, theme, -1.0)
	# A drop forming at the tip and falling a little way (cosmetic, safe).
	var cycle := fmod(time * 0.9 + x * 0.01, 1.0)
	var drop_y := top_tip + 3.0 + cycle * cycle * 40.0
	c.draw_circle(
		Vector2(x, drop_y), 2.5, Color(Color.WHITE, 0.7 * (1.0 - cycle)), true, -1.0, true
	)


## One rock from `base` (an edge of the screen) to `tip`; dir 1 hangs down.
static func _rock(
	c: CanvasItem, x: float, half: float, base: float, tip: float, theme: ThemeDef, dir: float
) -> void:
	var length := absf(tip - base)
	if length < 1.0:
		return
	var taper := minf(TAPER, length)
	var body_end := tip - dir * taper
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in STEPS + 1:
		var f := float(i) / STEPS
		var y := lerpf(base, body_end, f)
		# Bumpy sides, fixed by position so they do not shimmer.
		var bump := sin(y * 0.11 + x) * 2.0 + sin(y * 0.29) * 1.2
		left.append(Vector2(x - half + 1.5 + bump, y))
		right.append(Vector2(x + half - 1.5 + bump * 0.7, y))
	var pts := PackedVector2Array()
	pts.append_array(left)
	# Dripping tip: narrows to a blunt rounded point.
	pts.append(Vector2(x - half * 0.55, tip - dir * taper * 0.45))
	pts.append(Vector2(x - half * 0.2, tip - dir * 2.0))
	pts.append(Vector2(x, tip))
	pts.append(Vector2(x + half * 0.2, tip - dir * 2.0))
	pts.append(Vector2(x + half * 0.55, tip - dir * taper * 0.45))
	right.reverse()
	pts.append_array(right)
	c.draw_colored_polygon(pts, theme.spike)
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_polyline(outline, theme.spike, 1.0, true)
	# Lighter ridge down one side and a few drip streaks.
	var ridge := PackedVector2Array()
	for p in left:
		ridge.append(p + Vector2(5.0, 0.0))
	ridge.append(Vector2(x - half * 0.3, tip - dir * taper * 0.5))
	c.draw_polyline(ridge, Color(theme.spike_edge, 0.55), 2.0, true)
	for k in 2:
		var sx := x + (k * 2 - 1) * half * 0.35
		var sy := lerpf(base, body_end, 0.35 + 0.3 * k)
		var streak := Vector2(sx, sy + dir * 12.0)
		c.draw_line(Vector2(sx, sy), streak, Color(theme.spike_edge, 0.35), 2.0, true)
