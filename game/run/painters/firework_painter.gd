extends RefCounted
## Firework (New Year Firework Burst). On the pad: the rocket on the floor with
## a fizzing fuse and a faint ring where it will burst (the warning). Climbing:
## the rocket with a glowing trail. Burst: eight sparks in the spike colour
## with streaks back to the centre, fading out.

const Firework := preload("res://sim/hazards/firework.gd")


static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float) -> void:
	var p := HazardLayer.at(h.x, h.y)
	match h.phase:
		Firework.Phase.PAD:
			var k: float = h.fuse_progress() / float(SimTrig.ONE)
			var target := Vector2(p.x, HazardLayer.px(h.burst_y))
			c.draw_arc(
				target, 10.0 + 8.0 * k, 0.0, TAU, 32, Color(theme.spike, 0.15 + 0.35 * k), 2.0, true
			)
			_rocket(c, p, theme)
			var fizz := 2.0 + absf(sin(time * 30.0)) * 3.0 * (0.5 + k)
			c.draw_circle(p + Vector2(0, 12), fizz, Color(theme.glow, 0.9))
		Firework.Phase.CLIMB:
			var trail := PackedVector2Array(
				[p + Vector2(-3, 10), p + Vector2(3, 10), p + Vector2(0, 46)]
			)
			c.draw_colored_polygon(trail, Color(theme.glow, 0.6))
			_rocket(c, p, theme)
		Firework.Phase.BURST:
			var a: float = h.spark_alpha() / float(SimTrig.ONE)
			var sr := HazardLayer.px(Firework.SPARK_RADIUS)
			for i in Firework.SPARKS:
				var s := HazardLayer.at(h.spark_x(i), h.spark_y(i))
				var back := p.lerp(s, 0.55)
				c.draw_line(back, s, Color(theme.spike, 0.35 * a), 2.0, true)
				_spark(c, s, sr, theme, a, time + i)


static func _rocket(c: CanvasItem, p: Vector2, theme: ThemeDef) -> void:
	var body := Rect2(p + Vector2(-5, -8), Vector2(10, 18))
	var box := StyleBoxFlat.new()
	box.bg_color = theme.spike
	box.set_corner_radius_all(3)
	box.anti_aliasing = true
	box.draw(c.get_canvas_item(), body)
	var nose := PackedVector2Array([p + Vector2(-6, -7), p + Vector2(6, -7), p + Vector2(0, -17)])
	c.draw_colored_polygon(nose, theme.spike)
	c.draw_line(p + Vector2(-2, -5), p + Vector2(-2, 7), Color(theme.spike_edge, 0.8), 2.0, true)


static func _spark(
	c: CanvasItem, s: Vector2, r: float, theme: ThemeDef, a: float, t: float
) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var ang := t * 4.0 + TAU * i / 8.0
		var rr := r * (1.4 if i % 2 == 0 else 0.6)
		pts.append(s + Vector2(cos(ang), sin(ang)) * rr)
	c.draw_colored_polygon(pts, Color(theme.spike, a))
	c.draw_circle(s, r * 0.4, Color(theme.spike_edge, 0.8 * a))
