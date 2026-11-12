extends HazardPainter
## Gate (Shutter Gates): a rock bar above and below a sliding gap, each ending
## in a spike tip at the gap so the deadly lips read clearly. The bars come out
## of the ceiling and floor behind their spike rows (the spikes are drawn again
## over each bar). The tip is one two-tone spike as wide as the bar, inside the
## bar's hitbox: the drawing ends exactly where the gap starts.

const GateHazard := preload("res://sim/hazards/gate.gd")

const TEETH := 1
const TOOTH := 12.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as GateHazard
	var half := HazardLayer.px(h.HALF_W)
	var cx := HazardLayer.px(h.x)
	var gap_top := HazardLayer.px(h.gap_top())
	var gap_bottom := HazardLayer.px(h.gap_bottom())
	_bar(c, cx, half, 0.0, gap_top - TOOTH, look)
	_bar(c, cx, half, gap_bottom + TOOTH, RoomView.H, look)
	_teeth(c, cx, half, gap_top - TOOTH, 1.0, look)
	_teeth(c, cx, half, gap_bottom + TOOTH, -1.0, look)
	_edge_spikes_over(c, cx, half, look)


## A square-ended bar from y0 to y1 with a lighter edge down its left side.
static func _bar(
	c: CanvasItem, cx: float, half: float, y0: float, y1: float, look: HazardLook
) -> void:
	if y1 - y0 < 0.5:
		return
	var theme := look.theme
	var r := Rect2(cx - half, y0, half * 2.0, y1 - y0)
	c.draw_rect(r, RoomView.INK_SPIKE if look.ink else theme.spike)
	var lit := RoomView.INK_SPIKE_EDGE if look.ink else theme.spike_edge
	c.draw_rect(Rect2(r.position.x, y0, 3.0, r.size.y), Color(lit, 0.8))
	if look.ink:
		c.draw_rect(r, HazardLayer.INK_EDGE, false, HazardLayer.INK_LINE_W)


## The tip at a gap edge: TEETH two-tone spikes filling the bar's width, from
## `y` pointing `dir` (1 = down) into the gap, TOOTH deep.
static func _teeth(
	c: CanvasItem, cx: float, half: float, y: float, dir: float, look: HazardLook
) -> void:
	var w := half * 2.0 / TEETH
	for i in TEETH:
		var base := Vector2(cx - half + w * (i + 0.5), y)
		RoomView.paint_spike(c, base, Vector2(0, dir), w / 2.0, TOOTH, look.theme, look.ink)


## The ceiling and floor spikes in front of the bar's column, drawn again so
## the bar passes behind them.
static func _edge_spikes_over(c: CanvasItem, cx: float, half: float, look: HazardLook) -> void:
	var left := 0.0
	var right := RoomView.W
	if look.sim != null:
		left = HazardLayer.px(look.sim.room.inset(0))
		right = RoomView.W - HazardLayer.px(look.sim.room.inset(1))
	for s in RoomView.edge_row(left, right):
		if absf(s.x - cx) >= s.y + half:
			continue
		var depth := RoomView.EDGE_SPIKE_DEPTH
		var theme := look.theme
		RoomView.paint_spike(
			c, Vector2(s.x, RoomView.BAND), Vector2(0, 1), s.y, depth, theme, look.ink
		)
		var floor_base := Vector2(s.x, RoomView.H - RoomView.BAND)
		RoomView.paint_spike(c, floor_base, Vector2(0, -1), s.y, depth, theme, look.ink)
