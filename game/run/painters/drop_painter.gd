extends HazardPainter
## Drop (Spike Rain; "pinecone" in Orchard Drop, "icicle" in Winter Icicle
## Drop). While warning: a dark mark on the ceiling grows over the column (the
## icicle shakes instead). While falling: the deadly drop in the spike colour.

const DropHazard := preload("res://sim/hazards/drop.gd")

const LENGTH := 26.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as DropHazard
	var theme := look.theme
	var time := look.time
	var r := HazardLayer.px(h.RADIUS)
	if h.warning():
		var k: float = h.warn_progress() / float(SimTrig.ONE)
		var top := HazardLayer.px(SimConfig.KILL_TOP)
		var x := HazardLayer.px(h.x)
		if look.skin == "icicle":
			var shake := sin(time * 60.0) * 2.5 * k
			_icicle(c, Vector2(x + shake, top + r), r, theme, 1.0)
			return
		# A faint column and a dark mark hanging from the ceiling.
		c.draw_line(
			Vector2(x, top), Vector2(x, top + 160.0 * k), Color(theme.spike, 0.12), r * 2.0, true
		)
		var mark := Rect2(x - r, top - 4.0, r * 2.0, 6.0 + 8.0 * k)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(theme.spike, 0.35 + 0.5 * k)
		box.set_corner_radius_all(4)
		box.anti_aliasing = true
		box.draw(c.get_canvas_item(), mark)
		return
	if not h.falling():
		return
	var p := HazardLayer.at(h.x, h.y)
	match look.skin:
		"icicle":
			_icicle(c, p, r, theme, 1.0)
		"pinecone":
			_pinecone(c, p, r, theme, time)
		_:
			_spike_drop(c, p, r, theme)


## A teardrop pointing down, with a lighter edge.
static func _spike_drop(c: CanvasItem, p: Vector2, r: float, theme: ThemeDef) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI * i / 12.0
		pts.append(p + Vector2(cos(a) * r, -sin(a) * r * 0.9))
	pts.append(p + Vector2(0, r * 1.6))
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_arc(p, r * 0.6, PI * 1.15, PI * 1.6, 8, Color(theme.spike_edge, 0.8), 2.0, true)


static func _icicle(c: CanvasItem, p: Vector2, r: float, theme: ThemeDef, alpha: float) -> void:
	var pts := PackedVector2Array(
		[p + Vector2(-r, -r), p + Vector2(r, -r), p + Vector2(0, -r + LENGTH * 1.4)]
	)
	c.draw_colored_polygon(pts, Color(theme.spike, alpha))
	pts.append(pts[0])
	c.draw_polyline(pts, Color(theme.spike, alpha), 1.0, true)
	c.draw_line(
		p + Vector2(-r * 0.4, -r), p + Vector2(-r * 0.1, r), Color(theme.spike_edge, 0.8), 2.0, true
	)


static func _pinecone(c: CanvasItem, p: Vector2, r: float, theme: ThemeDef, time: float) -> void:
	var spin := sin(time * 6.0) * 0.25
	c.draw_set_transform(p, spin, Vector2(1.0, 1.3))
	# Thorns around an oval body.
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		var rr := r * (1.25 if i % 2 == 0 else 0.95)
		pts.append(Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike, 1.0, true)
	# Scales.
	for row in 3:
		var y := (row - 1) * r * 0.5
		c.draw_arc(
			Vector2(0, y), r * 0.55, 0.2, PI - 0.2, 8, Color(theme.spike_edge, 0.7), 1.5, true
		)
	c.draw_set_transform(Vector2.ZERO)
