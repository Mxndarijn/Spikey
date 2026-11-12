extends HazardPainter
## The Watcher: an eye in the ceiling over beam emitters down both walls. Rows
## about to fire flicker as dashed lines; live beams are bars in spike colour.
## The gaze marks a dashed lane, the spike on its wall glows, then the dart
## flies along it. When the boss breaks the eye shuts and fades.

const BossWatcher := preload("res://sim/hazards/boss_watcher.gd")
const BeamPainter := preload("res://game/run/painters/beam_painter.gd")

const EYE := Vector2(180.0, 20.0)
const EYE_R := 26.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BossWatcher
	var theme := look.theme
	var time := look.time
	var fade := clampf(1.0 - BossBar.down_time(h) / 0.6, 0.0, 1.0)
	BossBar.draw(c, h, look)
	var w := HazardLayer.px(SimConfig.WORLD_W)
	for i in h.ROWS.size():
		var y := HazardLayer.px(h.ROWS[i])
		var lit := (h.lit >> i) & 1 == 1 and h.down_at < 0
		var glow := 0.0
		if lit and h.beam == h.Beam.WARN:
			var warn := h.beam_t / float(h.TELL)
			var flick := 0.5 + 0.5 * sin(time * (14.0 + 30.0 * warn))
			var col := Color(theme.spike, (0.3 + 0.5 * warn) * (0.5 + 0.5 * flick))
			c.draw_dashed_line(Vector2(12.0, y), Vector2(w - 12.0, y), col, 2.0, 10.0, true, true)
			glow = warn
		elif lit and h.beam == h.Beam.ON:
			var half := HazardLayer.px(h.HALF_H)
			c.draw_rect(Rect2(0.0, y - half * 1.8, w, half * 3.6), Color(theme.spike, 0.3), true)
			c.draw_rect(Rect2(0.0, y - half, w, half * 2.0), theme.spike, true)
			c.draw_line(Vector2(0.0, y), Vector2(w, y), Color(theme.spike_edge, 0.9), 2.0, true)
			glow = 1.0
		BeamPainter._emitter(c, Vector2(0.0, y), 1.0, theme, glow * fade)
		BeamPainter._emitter(c, Vector2(w, y), -1.0, theme, glow * fade)
	_dart(c, h, look)
	_eye(c, h, look, fade)


func _dart(c: CanvasItem, h: BossWatcher, look: HazardLook) -> void:
	if h.dart == h.Dart.NONE:
		return
	var theme := look.theme
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var y := HazardLayer.px(h.dart_lane)
	var dir := -1.0 if h.dart_side == 1 else 1.0
	var wall := w if h.dart_side == 1 else 0.0
	if h.dart == h.Dart.MARK:
		var g := clampf(h.dart_t / float(h.TELL), 0.0, 1.0)
		var flash := 0.5 + 0.5 * sin(look.time * (16.0 + 20.0 * g))
		var lane := Color(theme.spike, (0.3 + 0.45 * g) * (0.55 + 0.45 * flash))
		c.draw_dashed_line(Vector2(12.0, y), Vector2(w - 12.0, y), lane, 2.0, 10.0, true, true)
		var halo := Color(theme.spike_edge, 0.25 + 0.5 * g * flash)
		c.draw_circle(Vector2(wall + dir * 8.0, y), 14.0 + 4.0 * g, halo, true, -1.0, true)
		BossBar.tooth(c, Vector2(wall, y), Vector2(dir, 0.0), 15.0, 26.0 + 8.0 * g, theme)
	else:
		var tip := HazardLayer.px(h.dart_x)
		var back := tip - dir * HazardLayer.px(h.DART_LEN)
		BossBar.tooth(
			c,
			Vector2(back, y),
			Vector2(dir, 0.0),
			10.0,
			tip - back if dir > 0.0 else back - tip,
			theme
		)


func _eye(c: CanvasItem, h: BossWatcher, look: HazardLook, fade: float) -> void:
	if fade <= 0.0:
		return
	var theme := look.theme
	var spike := Color(theme.spike, fade)
	for i in 10:
		var a := i / 10.0 * TAU
		var d := Vector2(cos(a), sin(a))
		BossBar.tooth(c, EYE + d * (EYE_R - 4.0), d, 7.0, 14.0, theme)
	c.draw_circle(EYE, EYE_R, spike, true, -1.0, true)
	var open := 0.25 if h.phase == 1 else 1.0
	if h.down_at >= 0:
		open = 0.0
	if h.dart == h.Dart.MARK:
		open = 1.0
	if open <= 0.05:
		c.draw_line(
			EYE + Vector2(-16.0, 0.0),
			EYE + Vector2(16.0, 0.0),
			Color(UiTokens.PANEL, fade),
			3.0,
			true
		)
		return
	var white := PackedVector2Array()
	for i in 24:
		var a := i / 24.0 * TAU
		white.append(EYE + Vector2(cos(a) * 18.0, sin(a) * 15.0 * open))
	c.draw_colored_polygon(white, Color(UiTokens.PANEL, fade))
	var look_x := 0.0
	if look.sim != null:
		look_x = clampf((HazardLayer.px(look.sim.state.x) - EYE.x) / 30.0, -7.0, 7.0)
	c.draw_circle(
		EYE + Vector2(look_x, 2.0 * open), 6.0 * minf(1.0, open + 0.3), spike, true, -1.0, true
	)
