extends HazardPainter
## Bumper (Bumper Cloud; "heart" skin for Heart Bumpers): a soft, safe shape
## that squashes a little as it breathes. Never in the spike colour.

const BumperHazard := preload("res://sim/hazards/bumper.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BumperHazard
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.x, h.y)
	var r := HazardLayer.px(h.RADIUS)
	var pulse := 1.0 + sin(time * 3.0) * 0.04
	c.draw_circle(center, r * 1.25 * pulse, Color(theme.glow, 0.25), true, -1.0, true)
	if look.skin == "heart":
		_heart(c, center, r * pulse, theme)
	else:
		_cloud(c, center, r * pulse, theme)


static func _cloud(c: CanvasItem, center: Vector2, r: float, theme: ThemeDef) -> void:
	# Puffs: [x offset, y offset, radius] as fractions of r.
	var puffs: Array[Vector3] = [
		Vector3(-0.55, 0.15, 0.55),
		Vector3(0.55, 0.15, 0.55),
		Vector3(-0.2, -0.25, 0.62),
		Vector3(0.28, -0.18, 0.5),
		Vector3(0.0, 0.25, 0.6),
	]
	var edge := Color(theme.world_accent, 0.9)
	for p in puffs:
		c.draw_circle(center + Vector2(p.x, p.y) * r, p.z * r + 2.0, edge, true, -1.0, true)
	for p in puffs:
		c.draw_circle(center + Vector2(p.x, p.y) * r, p.z * r, Color.WHITE, true, -1.0, true)
	c.draw_circle(
		center + Vector2(-0.25, -0.35) * r, r * 0.18, Color(theme.glow, 0.6), true, -1.0, true
	)


static func _heart(c: CanvasItem, center: Vector2, r: float, theme: ThemeDef) -> void:
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var a := TAU * i / n
		# The classic heart curve, scaled to about r.
		var hx := 16.0 * pow(sin(a), 3.0)
		var hy := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
		pts.append(center + Vector2(hx, hy) * (r / 16.0))
	c.draw_colored_polygon(pts, theme.world_accent)
	pts.append(pts[0])
	c.draw_polyline(pts, Color.WHITE, 2.0, true)
	c.draw_circle(
		center + Vector2(-0.4, -0.35) * r, r * 0.16, Color(Color.WHITE, 0.7), true, -1.0, true
	)
