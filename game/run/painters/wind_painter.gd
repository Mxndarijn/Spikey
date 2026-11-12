extends HazardPainter
## Crosswind: a faint band with streaks blowing across it and chevrons that
## point the way. Safe, so it uses the world's glow, never the spike colour.
## Gusty: faint slow streaks while the gust is coming, none while calm.

const WindHazard := preload("res://sim/hazards/wind.gd")

const STREAKS := 9
const SPEED := 260.0
const SLOW := 60.0
const STREAK_LEN := 26.0
const MARGIN := 34.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as WindHazard
	var on := h.blowing()
	var warn := h.warning()
	_band(c, h.a_y0, h.a_y1, h.a_dir, on, warn, look)
	if h.b_dir != 0:
		_band(c, h.b_y0, h.b_y1, h.b_dir, on, warn, look)


func _band(
	c: CanvasItem, y0: int, y1: int, dir: int, on: bool, warn: bool, look: HazardLook
) -> void:
	var glow := look.theme.glow
	# Streaks and chevrons in the world's ink (white in night worlds): glow on
	# a light sky was nearly invisible, so the way it blows did not read.
	var ink := look.theme.ink
	var top := HazardLayer.px(y0)
	var bottom := HazardLayer.px(y1)
	var w := RoomView.W - MARGIN * 2.0
	c.draw_rect(Rect2(MARGIN, top, w, bottom - top), Color(glow, 0.14 if on else 0.06))
	if not on and not warn:
		return
	var speed := SPEED if on else SLOW
	var alpha := 0.35 if on else 0.15
	for i in STREAKS:
		var lane := top + 8.0 + (bottom - top - 16.0) * fposmod(i * 0.618, 1.0)
		var x := MARGIN + fposmod(look.time * speed * dir + i * w / STREAKS, w)
		var tail := clampf(x - dir * STREAK_LEN, MARGIN, MARGIN + w)
		c.draw_line(Vector2(x, lane), Vector2(tail, lane), Color(ink, alpha), 3.0, true)
	# Two chevrons at the windward side show which way it blows.
	var cx := MARGIN + 18.0 if dir > 0 else MARGIN + w - 18.0
	var cy := (top + bottom) / 2.0
	for k in 2:
		var x := cx + dir * k * 12.0
		var pts := PackedVector2Array(
			[Vector2(x, cy - 8.0), Vector2(x + dir * 9.0, cy), Vector2(x, cy + 8.0)]
		)
		c.draw_polyline(pts, Color(ink, 0.55 if on else 0.3), 3.0, true)
