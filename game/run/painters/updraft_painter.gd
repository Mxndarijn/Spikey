extends RefCounted
## Updraft: a soft glowing column with chevrons drifting up. Safe, so it uses
## the world's glow, never the spike colour.

const ROWS := 8
const SPEED := 70.0


static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float) -> void:
	var x0 := HazardLayer.px(h.x0)
	var x1 := HazardLayer.px(h.x1)
	var top := HazardLayer.px(SimConfig.KILL_TOP)
	var bottom := HazardLayer.px(SimConfig.KILL_BOTTOM)
	var w := x1 - x0
	c.draw_rect(Rect2(x0, top, w, bottom - top), Color(theme.glow, 0.10))
	# Soft edges: two thin lines at the band's sides.
	c.draw_line(Vector2(x0, top), Vector2(x0, bottom), Color(theme.glow, 0.30), 2.0, true)
	c.draw_line(Vector2(x1, top), Vector2(x1, bottom), Color(theme.glow, 0.30), 2.0, true)
	var span := bottom - top
	var cx := (x0 + x1) / 2.0
	for i in ROWS:
		var y := bottom - fposmod(time * SPEED + i * span / ROWS, span)
		var fade := clampf((y - top) / 60.0, 0.0, 1.0) * clampf((bottom - y) / 60.0, 0.0, 1.0)
		var col := Color(theme.glow, 0.55 * fade)
		var half := w * 0.18
		var pts := PackedVector2Array(
			[Vector2(cx - half, y + 10), Vector2(cx, y), Vector2(cx + half, y + 10)]
		)
		c.draw_polyline(pts, col, 3.0, true)
