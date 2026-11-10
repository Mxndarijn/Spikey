extends HazardPainter
## Gate (Shutter Gates): a rock bar above and below a sliding gap, with teeth
## on the gap edges so the deadly lips read clearly.

const GateHazard := preload("res://sim/hazards/gate.gd")

const TEETH := 3
const TOOTH := 6.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as GateHazard
	var theme := look.theme
	var half := HazardLayer.px(h.HALF_W)
	var cx := HazardLayer.px(h.x)
	var top := HazardLayer.px(h.TOP)
	var bottom := HazardLayer.px(h.BOTTOM)
	var gap_top := HazardLayer.px(h.gap_top())
	var gap_bottom := HazardLayer.px(h.gap_bottom())
	HazardLayer.rock_box(c, Rect2(cx - half, top, half * 2.0, gap_top - top), look)
	HazardLayer.rock_box(c, Rect2(cx - half, gap_bottom, half * 2.0, bottom - gap_bottom), look)
	_teeth(c, cx, half, gap_top, 1.0, theme)
	_teeth(c, cx, half, gap_bottom, -1.0, theme)


## A row of small spikes along a gap edge at y, pointing into the gap (dir).
static func _teeth(
	c: CanvasItem, cx: float, half: float, y: float, dir: float, theme: ThemeDef
) -> void:
	var w := half * 2.0 / TEETH
	for i in TEETH:
		var x0 := cx - half + i * w
		var pts := PackedVector2Array(
			[Vector2(x0, y - dir), Vector2(x0 + w, y - dir), Vector2(x0 + w / 2.0, y + dir * TOOTH)]
		)
		c.draw_colored_polygon(pts, theme.spike)
		pts.append(pts[0])
		c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_line(Vector2(cx - half, y), Vector2(cx + half, y), theme.spike_edge, 1.5, true)
