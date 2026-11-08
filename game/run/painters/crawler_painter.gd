extends RefCounted
## Crawler (Caterpillar Crawl; "crab" skin for Summer Crab Walk): round body
## segments in the spike colour that bob as they walk, with a face on the head.


static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float) -> void:
	var r := HazardLayer.px(h.SEG_RADIUS)
	var n: int = h.xs.size()
	# Tail first, so the head is drawn on top.
	for k in n:
		var i := n - 1 - k
		var p := HazardLayer.at(h.xs[i], h.ys[i])
		var bob := sin(time * 8.0 + i * 1.3) * 1.2
		if h.skin == "crab":
			_crab_segment(c, p, r, theme, i == 0, bob)
		else:
			_segment(c, p + Vector2(0, bob), r, theme, i == 0)
	if n > 1:
		var head := HazardLayer.at(h.xs[0], h.ys[0])
		var facing := (head - HazardLayer.at(h.xs[1], h.ys[1])).normalized()
		_face(c, head, facing, r)


static func _segment(c: CanvasItem, p: Vector2, r: float, theme: ThemeDef, head: bool) -> void:
	var rr := r * (1.12 if head else 1.0)
	c.draw_circle(p, rr, theme.spike, true, -1.0, true)
	c.draw_circle(p, rr, theme.spike_edge, false, 1.5, true)
	c.draw_circle(
		p + Vector2(-0.3, -0.35) * rr, rr * 0.3, Color(theme.spike_edge, 0.55), true, -1.0, true
	)


static func _crab_segment(
	c: CanvasItem, p: Vector2, r: float, theme: ThemeDef, head: bool, bob: float
) -> void:
	# A wide shell with little legs; the head carries two claws.
	c.draw_set_transform(p + Vector2(0, bob), 0.0, Vector2(1.25, 0.9))
	c.draw_circle(Vector2.ZERO, r, theme.spike, true, -1.0, true)
	c.draw_circle(Vector2.ZERO, r, theme.spike_edge, false, 1.5, true)
	c.draw_set_transform(Vector2.ZERO)
	for s: float in [-1.0, 1.0]:
		var leg := p + Vector2(s * r * 1.2, r * 0.5)
		c.draw_line(
			p + Vector2(s * r * 0.8, r * 0.3), leg + Vector2(0, bob), theme.spike, 2.0, true
		)
	if head:
		for s: float in [-1.0, 1.0]:
			var claw := p + Vector2(s * r * 1.3, -r * 0.9 + bob)
			c.draw_circle(claw, r * 0.45, theme.spike, true, -1.0, true)
			c.draw_circle(claw, r * 0.45, theme.spike_edge, false, 1.2, true)


static func _face(c: CanvasItem, head: Vector2, facing: Vector2, r: float) -> void:
	var side := facing.orthogonal()
	for s: float in [-1.0, 1.0]:
		var eye := head + facing * r * 0.35 + side * s * r * 0.4
		c.draw_circle(eye, r * 0.28, Color.WHITE, true, -1.0, true)
		c.draw_circle(eye + facing * r * 0.1, r * 0.13, Color(0.1, 0.1, 0.15), true, -1.0, true)
