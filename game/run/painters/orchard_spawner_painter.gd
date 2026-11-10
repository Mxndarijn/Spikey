extends HazardPainter
## Orchard Drop's falling coins: the coin art, swaying a little as it falls.

const OrchardSpawnerHazard := preload("res://sim/hazards/orchard_spawner.gd")

const COIN := preload("res://assets/ui/coin.svg")
const SIZE := 28.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as OrchardSpawnerHazard
	var time := look.time
	for i in h.xs.size():
		if not h.live[i]:
			continue
		var sway := sin(time * 3.0 + i * 1.3) * 2.0
		var p := HazardLayer.at(h.xs[i], h.ys[i]) + Vector2(sway, 0)
		c.draw_texture_rect(COIN, Rect2(p - Vector2(SIZE, SIZE) / 2.0, Vector2(SIZE, SIZE)), false)
