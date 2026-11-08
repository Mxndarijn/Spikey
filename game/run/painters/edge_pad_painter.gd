extends RefCounted
## Edge pad (Bumper Court): a soft, safe pill lying on the ceiling or floor
## line, squashing when it bounces the bird. Never in the spike colour.


static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float) -> void:
	var x0 := HazardLayer.px(h.x0())
	var x1 := HazardLayer.px(h.x1())
	var line := HazardLayer.px(h.line_y())
	var squash := clampf(1.0 - h.since_bump / 12.0, 0.0, 1.0)
	var thick := 12.0 * (1.0 - 0.35 * squash) + sin(time * 4.0) * 0.6
	# The pad sits just inside the edge line, toward the room.
	var y := line if h.top else line - thick
	var rect := Rect2(x0, y, x1 - x0, thick)
	var halo := StyleBoxFlat.new()
	halo.bg_color = Color(theme.glow, 0.25 + 0.3 * squash)
	halo.set_corner_radius_all(int(thick / 2.0 + 4.0))
	halo.anti_aliasing = true
	halo.draw(c.get_canvas_item(), rect.grow(4.0))
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color.WHITE
	pill.set_corner_radius_all(int(thick / 2.0))
	pill.border_color = Color(theme.world_accent, 0.95)
	pill.set_border_width_all(2)
	pill.anti_aliasing = true
	pill.draw(c.get_canvas_item(), rect)
	# Chevrons pointing back into the room: it bounces you.
	var dir := 1.0 if h.top else -1.0
	var mid := (x0 + x1) / 2.0
	var cy := y + thick / 2.0
	for i: int in [-1, 0, 1]:
		var cx := mid + i * 16.0
		var pts := PackedVector2Array(
			[
				Vector2(cx - 5.0, cy - dir * 2.0),
				Vector2(cx, cy + dir * 2.5),
				Vector2(cx + 5.0, cy - dir * 2.0),
			]
		)
		c.draw_polyline(pts, theme.world_accent, 2.0, true)
