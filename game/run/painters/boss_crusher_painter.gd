extends HazardPainter
## The Crusher: a spiked press as wide as the cage (at rest it is the ceiling)
## and, from phase 2, a spiked floor plate. A dashed line shows where the
## teeth will stop (the press shakes before a slam); crates show their column
## dashed before they fall. All in spike colour; the face is cut in paper.

const BossCrusher := preload("res://sim/hazards/boss_crusher.gd")

const BODY := 46.0
const TEETH_N := 9


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BossCrusher
	var theme := look.theme
	var time := look.time
	BossBar.draw(c, h, look)
	var w := HazardLayer.px(SimConfig.WORLD_W)
	var teeth := HazardLayer.px(h.TEETH)
	if h.telling and h.down_at < 0:
		var flick := 0.6 + 0.3 * sin(time * 24.0)
		var col := Color(theme.spike, flick)
		if h.phase == 1:
			_dash(c, HazardLayer.px(h.slam_y) + teeth, w, col)
		elif h.jaw:
			var half := HazardLayer.px(h.lane_half())
			var lane := HazardLayer.px(h.lane_to)
			_dash(c, lane - half, w, col)
			_dash(c, lane + half, w, col)
	for i in 2:
		_crate(c, h, i, look)
	var shake := 0.0
	if h.telling and h.phase == 1 and h.down_at < 0:
		shake = sin(time * 55.0) * 2.0
	_press(c, HazardLayer.px(h.press_y), shake, w, teeth, theme, h.down_at >= 0)
	_plate(c, HazardLayer.px(h.plate_y), w, teeth, theme)


func _dash(c: CanvasItem, y: float, w: float, col: Color) -> void:
	c.draw_dashed_line(Vector2(8.0, y), Vector2(w - 8.0, y), col, 3.0, 10.0, true, true)


func _press(
	c: CanvasItem, bottom: float, x: float, w: float, teeth: float, theme: ThemeDef, broken: bool
) -> void:
	var top := bottom - BODY
	if top > 0.0:
		c.draw_rect(Rect2(80.0 + x, 0.0, 12.0, top), theme.spike_edge, true)
		c.draw_rect(Rect2(268.0 + x, 0.0, 12.0, top), theme.spike_edge, true)
	c.draw_rect(Rect2(-4.0 + x, top, w + 8.0, BODY), theme.spike, true)
	c.draw_rect(Rect2(-4.0 + x, top, w + 8.0, 6.0), theme.spike_edge, true)
	var step := w / TEETH_N
	for i in TEETH_N:
		var base := Vector2(x + step * (i + 0.5), bottom)
		BossBar.tooth(c, base, Vector2(0.0, 1.0), step / 2.0, teeth, theme)
	if bottom < 40.0:
		return
	var eye := UiTokens.PANEL if not broken else Color(UiTokens.PANEL, 0.4)
	var y := bottom - 34.0
	c.draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(146 + x, y),
				Vector2(170 + x, y + 6),
				Vector2(170 + x, y + 16),
				Vector2(146 + x, y + 12)
			]
		),
		eye
	)
	c.draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(214 + x, y),
				Vector2(190 + x, y + 6),
				Vector2(190 + x, y + 16),
				Vector2(214 + x, y + 12)
			]
		),
		eye
	)


func _plate(c: CanvasItem, top: float, w: float, teeth: float, theme: ThemeDef) -> void:
	if top - teeth >= HazardLayer.px(SimConfig.WORLD_H):
		return
	c.draw_rect(Rect2(-4.0, top, w + 8.0, 700.0 - top), theme.spike, true)
	c.draw_rect(Rect2(-4.0, top + 8.0, w + 8.0, 4.0), theme.spike_edge, true)
	var step := w / TEETH_N
	for i in TEETH_N:
		BossBar.tooth(
			c, Vector2(step * (i + 0.5), top), Vector2(0.0, -1.0), step / 2.0, teeth, theme
		)


func _crate(c: CanvasItem, h: BossCrusher, i: int, look: HazardLook) -> void:
	var st: int = h.crate[i]
	if st == h.Crate.NONE:
		return
	var theme := look.theme
	var x := HazardLayer.px(h.crate_x[i])
	var half := HazardLayer.px(h.CRATE_HALF)
	if st == h.Crate.MARK:
		var top := HazardLayer.px(h.press_y + h.TEETH)
		var bottom := HazardLayer.px(h.plate_y - h.TEETH)
		var col := Color(theme.spike, 0.6 + 0.3 * sin(look.time * 24.0))
		c.draw_dashed_line(
			Vector2(x - half, top), Vector2(x - half, bottom), col, 2.0, 8.0, true, true
		)
		c.draw_dashed_line(
			Vector2(x + half, top), Vector2(x + half, bottom), col, 2.0, 8.0, true, true
		)
	var y := HazardLayer.px(h.crate_y[i])
	var r := Rect2(x - half, y - half, half * 2.0, half * 2.0)
	UiTheme.flat(theme.spike, 4, 0).draw(c.get_canvas_item(), r)
	c.draw_rect(Rect2(r.position.x, y - 3.0, r.size.x, 6.0), theme.spike_edge, true)


## The floor spikes under the plate are inside its teeth: they sink away.
func floor_sink(hazard: Hazard, _left: float, _right: float) -> float:
	var h := hazard as BossCrusher
	var line := h.plate_y - h.BITE
	return 1.0 if line <= SimConfig.KILL_BOTTOM else 0.0
