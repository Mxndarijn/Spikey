extends RefCounted
## Orchard Drop's falling coins: the coin art, swaying a little as it falls.

const COIN := preload("res://assets/ui/coin.svg")
const SIZE := 28.0


static func paint(c: CanvasItem, h: Hazard, _theme: ThemeDef, time: float) -> void:
	for i in h.xs.size():
		if not h.live[i]:
			continue
		var sway := sin(time * 3.0 + i * 1.3) * 2.0
		var p := HazardLayer.at(h.xs[i], h.ys[i]) + Vector2(sway, 0)
		c.draw_texture_rect(COIN, Rect2(p - Vector2(SIZE, SIZE) / 2.0, Vector2(SIZE, SIZE)), false)
