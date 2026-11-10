extends HazardPainter
## Mover (Bat Loop "bat", Bee Line "bee"): small deadly creatures in the spike
## colour, facing the way they fly. Without a skin: small spiked balls.

const MoverHazard := preload("res://sim/hazards/mover.gd")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as MoverHazard
	var theme := look.theme
	var time := look.time
	var r := HazardLayer.px(h.RADIUS)
	for i in h.xs.size():
		var p := HazardLayer.at(h.xs[i], h.ys[i])
		var face: float = h.facing[i]
		var flap := sin(time * 18.0 + i * 1.9)
		match look.skin:
			"bat":
				_bat(c, p, r, face, flap, theme)
			"bee":
				_bee(c, p, r, face, flap, theme)
			_:
				HazardLayer.spiky_ball(c, p, r, look, time * 3.0)


static func _bat(
	c: CanvasItem, p: Vector2, r: float, face: float, flap: float, theme: ThemeDef
) -> void:
	var lift := flap * r * 0.6
	for side: float in [-1.0, 1.0]:
		var wing := PackedVector2Array(
			[
				p + Vector2(side * r * 0.4, -r * 0.2),
				p + Vector2(side * r * 1.9, -r * 0.5 - lift),
				p + Vector2(side * r * 1.5, r * 0.2 - lift * 0.5),
				p + Vector2(side * r * 1.0, r * 0.05),
				p + Vector2(side * r * 0.5, r * 0.4),
			]
		)
		c.draw_colored_polygon(wing, theme.spike)
		wing.append(wing[0])
		c.draw_polyline(wing, theme.spike, 1.0, true)
	c.draw_circle(p, r * 0.7, theme.spike)
	# Ears and eyes.
	for side: float in [-1.0, 1.0]:
		var ear := PackedVector2Array(
			[
				p + Vector2(side * r * 0.2, -r * 0.55),
				p + Vector2(side * r * 0.55, -r * 1.05),
				p + Vector2(side * r * 0.6, -r * 0.35),
			]
		)
		c.draw_colored_polygon(ear, theme.spike)
		c.draw_circle(
			p + Vector2(side * r * 0.25 + face * r * 0.1, -r * 0.1), 2.0, theme.spike_edge
		)


static func _bee(
	c: CanvasItem, p: Vector2, r: float, face: float, flap: float, theme: ThemeDef
) -> void:
	# Wings first (pale), then the striped body in the spike colour.
	var wing := Color(1, 1, 1, 0.55)
	var w := r * (0.55 + 0.2 * flap)
	c.draw_set_transform(p + Vector2(-face * r * 0.2, -r * 0.7), 0.0, Vector2(0.7, 1.0))
	c.draw_circle(Vector2.ZERO, w, wing)
	c.draw_set_transform(Vector2.ZERO)
	c.draw_set_transform(p, 0.0, Vector2(1.25, 0.9))
	c.draw_circle(Vector2.ZERO, r, theme.spike)
	for k in 2:
		var sx := (k - 0.5) * r * 0.7
		c.draw_line(
			Vector2(sx, -r * 0.85), Vector2(sx, r * 0.85), Color(theme.spike_edge, 0.75), 3.0, true
		)
	c.draw_set_transform(Vector2.ZERO)
	# Stinger at the back, eye at the front.
	var tail := PackedVector2Array(
		[
			p + Vector2(-face * r * 1.1, -r * 0.25),
			p + Vector2(-face * r * 1.7, 0),
			p + Vector2(-face * r * 1.1, r * 0.25),
		]
	)
	c.draw_colored_polygon(tail, theme.spike)
	c.draw_circle(p + Vector2(face * r * 0.75, -r * 0.2), 2.0, theme.spike_edge)
