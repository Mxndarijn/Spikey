extends RefCounted
## Crate Drop (and Winter Gift Stack, skin "gift"): stacked crates and the one
## falling, in spike colour with lighter planks; a pulsing marker under the
## ceiling shows where the next crate falls. Gift stacks carry a coin on top.

const COIN := preload("res://assets/ui/coin.svg")
const COIN_SIZE := 26.0


static func paint(c: CanvasItem, h: Hazard, theme: ThemeDef, time: float) -> void:
	var size := HazardLayer.px(h.CRATE)
	var gift: bool = h.gifts or h.skin == "gift"
	for col in h.COLS:
		var n: int = h.heights[col]
		var x := HazardLayer.px(h.col_left(col))
		for i in n:
			var y := HazardLayer.px(h.FLOOR) - size * (i + 1)
			_crate(c, Rect2(x, y, size, size), theme, gift)
		if h.coins[col] == 1:
			var p := HazardLayer.at(h.col_center(col), h.coin_y(col))
			p.y += sin(time * 4.0 + col) * 2.0
			var s := Vector2(COIN_SIZE, COIN_SIZE)
			c.draw_texture_rect(COIN, Rect2(p - s / 2.0, s), false)
	if h.col < 0:
		return
	var cx := HazardLayer.px(h.col_left(h.col))
	if h.warn_left > 0:
		# Marker: a chevron under the ceiling and a dashed drop line.
		var pulse := 0.55 + 0.35 * sin(time * 12.0)
		var mid := cx + size / 2.0
		var top := HazardLayer.px(SimConfig.KILL_TOP) + 6.0
		var land := HazardLayer.px(h.stack_top(h.col))
		c.draw_dashed_line(
			Vector2(mid, top + 14.0), Vector2(mid, land), Color(theme.spike, pulse * 0.45), 2.0, 8.0
		)
		var chev := PackedVector2Array(
			[Vector2(mid - 10.0, top), Vector2(mid, top + 10.0), Vector2(mid + 10.0, top)]
		)
		c.draw_polyline(chev, Color(theme.spike, pulse), 3.0, true)
		c.draw_rect(Rect2(cx, land - 3.0, size, 3.0), Color(theme.spike, pulse * 0.6), true)
		return
	_crate(c, Rect2(cx, HazardLayer.px(h.y), size, size), theme, gift)


static func _crate(c: CanvasItem, r: Rect2, theme: ThemeDef, gift: bool) -> void:
	HazardLayer.rock_box(c, r, theme)
	var edge := Color(theme.spike_edge, 0.75)
	if gift:
		# Ribbon cross and a bow.
		var mid := r.get_center()
		c.draw_rect(Rect2(mid.x - 3.0, r.position.y, 6.0, r.size.y), edge, true)
		c.draw_rect(Rect2(r.position.x, mid.y - 3.0, r.size.x, 6.0), edge, true)
		var bow_y := r.position.y + 2.0
		c.draw_circle(Vector2(mid.x - 5.0, bow_y), 4.0, edge, true, -1.0, true)
		c.draw_circle(Vector2(mid.x + 5.0, bow_y), 4.0, edge, true, -1.0, true)
		return
	# Wooden crate: a frame and a diagonal brace.
	var inner := r.grow(-5.0)
	c.draw_rect(inner, edge, false, 2.0, true)
	c.draw_line(inner.position, inner.end, edge, 2.0, true)
