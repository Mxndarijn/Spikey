extends HazardPainter
## Saw King: a huge saw with a face in the middle column, its blades on a ring
## around it. A dashed ring shows where it lands (or how far its blades will
## swing) before it moves. All in spike colour; the face is cut in paper. When
## it breaks it falls and fades.

const BossSaw := preload("res://sim/hazards/boss_saw.gd")

const TEETH := 12
const R := 42.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BossSaw
	var theme := look.theme
	BossBar.draw(c, h, look)
	var x := HazardLayer.px(h.KING_X)
	var y := HazardLayer.px(h.king_y)
	var spin := h.angle / float(SimTrig.TURN) * TAU
	if h.telling and h.down_at < 0:
		var reach := HazardLayer.px(h.KING_R) + 10.0
		if h.phase == 2:
			reach = HazardLayer.px(h.ring_max() + h.BLADE_R) + 10.0
		elif h.phase == 3:
			reach = HazardLayer.px(h.RING_HOP + h.BLADE_R) + 10.0
		var col := Color(theme.spike, 0.45 + 0.3 * sin(look.time * 22.0))
		_dashed_circle(c, Vector2(x, HazardLayer.px(h.to_y)), reach, col)
	var gone := BossBar.down_time(h)
	var a := clampf(1.0 - gone / 0.9, 0.0, 1.0)
	if a <= 0.0:
		return
	y += gone * gone * 500.0
	if h.ring >= h.RING_SHOW:
		for i in h.blades:
			var b := Vector2(HazardLayer.px(h.blade_x[i]), HazardLayer.px(h.blade_y[i]))
			_saw(c, b, 10.0, spin * 3.0, 7, theme, a)
	_saw(c, Vector2(x, y), R, spin, TEETH, theme, a)
	if h.down_at >= 0:
		return
	var eye := UiTokens.PANEL
	var px := 2.0
	if look.sim != null:
		px = 2.0 if look.sim.state.x > h.KING_X else -2.0
	for s in [-1.0, 1.0]:
		var e := Vector2(x + s * 11.0, y - 2.0)
		c.draw_circle(e, 5.5, eye, true, -1.0, true)
		c.draw_circle(e + Vector2(px, 1.0), 2.4, theme.spike, true, -1.0, true)
		c.draw_line(Vector2(x + s * 19.0, y - 12.0), Vector2(x + s * 6.0, y - 8.0), eye, 3.0, true)


static func _saw(
	c: CanvasItem, at: Vector2, r: float, rot: float, teeth: int, theme: ThemeDef, a: float
) -> void:
	var pts := PackedVector2Array()
	for i in teeth * 2:
		var ang := rot + i * PI / teeth
		var rr := r * 1.24 if i % 2 == 0 else r
		pts.append(at + Vector2(cos(ang), sin(ang)) * rr)
	c.draw_colored_polygon(pts, Color(theme.spike, a))
	c.draw_circle(at, r * 0.66, Color(theme.spike_edge, a), true, -1.0, true)
	c.draw_circle(at, r * 0.52, Color(theme.spike, a), true, -1.0, true)


static func _dashed_circle(c: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	var n := maxi(16, int(r / 6.0))
	for i in n:
		if i % 2 == 1:
			continue
		var a0 := i * TAU / n
		var a1 := (i + 1) * TAU / n
		c.draw_line(
			at + Vector2(cos(a0), sin(a0)) * r, at + Vector2(cos(a1), sin(a1)) * r, col, 3.0, true
		)
