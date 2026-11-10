extends HazardPainter
## Beam Gates: emitter pairs on both walls. A dashed line flickers while a beam
## warms up; a live beam is a bright bar in spike colour with a light core.

const BeamHazard := preload("res://sim/hazards/beam.gd")

const EMITTER := Vector2(10.0, 22.0)


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BeamHazard
	var theme := look.theme
	var time := look.time
	var w := HazardLayer.px(SimConfig.WORLD_W)
	for i in h.rows.size():
		var y := HazardLayer.px(h.rows[i])
		var st: int = h.state(i)
		var lit := 0.0
		if st == h.State.WARN:
			var warn: float = h.warn_progress(i) / float(SimTrig.ONE)
			# Flickers faster as the beam is about to fire.
			var flick := 0.5 + 0.5 * sin(time * (14.0 + 30.0 * warn))
			var col := Color(theme.spike, (0.3 + 0.5 * warn) * (0.5 + 0.5 * flick))
			c.draw_dashed_line(
				Vector2(EMITTER.x, y), Vector2(w - EMITTER.x, y), col, 2.0, 10.0, true, true
			)
			lit = warn
		elif st == h.State.ON:
			var half := HazardLayer.px(h.HALF_H)
			var wobble := 1.0 + sin(time * 40.0 + i) * 0.08
			var outer := Rect2(0, y - half * 1.8 * wobble, w, half * 3.6 * wobble)
			c.draw_rect(outer, Color(theme.spike, 0.3), true)
			c.draw_rect(Rect2(0, y - half, w, half * 2.0), theme.spike, true)
			c.draw_line(Vector2(0, y), Vector2(w, y), Color(theme.spike_edge, 0.9), 2.0, true)
			lit = 1.0
		_emitter(c, Vector2(0, y), 1.0, theme, lit)
		_emitter(c, Vector2(w, y), -1.0, theme, lit)


static func _emitter(c: CanvasItem, at: Vector2, dir: float, theme: ThemeDef, lit: float) -> void:
	var x := at.x if dir > 0.0 else at.x - EMITTER.x
	var r := Rect2(x, at.y - EMITTER.y / 2.0, EMITTER.x, EMITTER.y)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(theme.world_accent, 0.9)
	box.set_corner_radius_all(3)
	box.border_color = Color(Color.WHITE, 0.6)
	box.set_border_width_all(1)
	box.anti_aliasing = true
	box.draw(c.get_canvas_item(), r)
	var lens := Vector2(at.x + dir * EMITTER.x, at.y)
	c.draw_circle(lens, 4.0, Color(theme.spike, 0.35 + 0.65 * lit), true, -1.0, true)
