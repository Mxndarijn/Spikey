extends HazardPainter
## A coin placed by the room: the coin art, bobbing gently.

const CoinPickupHazard := preload("res://sim/hazards/coin_pickup.gd")

const COIN := preload("res://assets/ui/coin.svg")
const SIZE := 28.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as CoinPickupHazard
	var time := look.time
	if not h.visible():
		return
	var p := HazardLayer.at(h.x, h.y) + Vector2(0, sin(time * 4.0 + h.x * 0.001) * 3.0)
	if look.skin == "egg":
		# Egg Hunt: a golden egg instead of a coin.
		c.draw_set_transform(p, 0.0, Vector2(0.78, 1.0))
		c.draw_circle(Vector2.ZERO, SIZE * 0.5, UiTokens.COIN_EDGE)
		c.draw_circle(Vector2.ZERO, SIZE * 0.42, UiTokens.COIN)
		c.draw_set_transform(Vector2.ZERO)
		c.draw_circle(p + Vector2(-3, -5), 2.5, Color(1, 1, 1, 0.7))
		return
	c.draw_texture_rect(COIN, Rect2(p - Vector2(SIZE, SIZE) / 2.0, Vector2(SIZE, SIZE)), false)
