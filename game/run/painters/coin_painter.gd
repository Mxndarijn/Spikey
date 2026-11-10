extends HazardPainter
## A coin placed by the room: the coin art, bobbing gently.

const CoinPickupHazard := preload("res://sim/hazards/coin_pickup.gd")

const COIN := preload("res://assets/ui/coin.svg")
const SIZE := 28.0
## Egg Hunt's golden egg is drawn this much bigger (its pickup reach is a coin's).
const GOLD_SCALE := 1.3


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as CoinPickupHazard
	var time := look.time
	if not h.visible():
		return
	var p := HazardLayer.at(h.x, h.y) + Vector2(0, sin(time * 4.0 + h.x * 0.001) * 3.0)
	if look.skin == "egg":
		# Egg Hunt: a golden egg instead of a coin. The one worth more (golden
		# egg variant) is bigger, glows and sparkles.
		var k := 1.0
		if h.value > 1:
			k = GOLD_SCALE
			var pulse := 0.5 + 0.5 * sin(time * 3.0)
			c.draw_set_transform(p, 0.0, Vector2(0.78, 1.0))
			c.draw_circle(Vector2.ZERO, SIZE * (0.75 + 0.08 * pulse), Color(UiTokens.COIN, 0.25))
			c.draw_set_transform(Vector2.ZERO)
		c.draw_set_transform(p, 0.0, Vector2(0.78, 1.0))
		c.draw_circle(Vector2.ZERO, SIZE * 0.5 * k, UiTokens.COIN_EDGE)
		c.draw_circle(Vector2.ZERO, SIZE * 0.42 * k, UiTokens.COIN)
		c.draw_set_transform(Vector2.ZERO)
		c.draw_circle(p + Vector2(-3, -5) * k, 2.5 * k, Color(1, 1, 1, 0.7))
		if h.value > 1:
			_sparkles(c, p, time)
		return
	c.draw_texture_rect(COIN, Rect2(p - Vector2(SIZE, SIZE) / 2.0, Vector2(SIZE, SIZE)), false)


## Three small four-point stars turning round a golden egg.
static func _sparkles(c: CanvasItem, p: Vector2, time: float) -> void:
	for i in 3:
		var a := time * 1.5 + i * TAU / 3.0
		var at := p + Vector2(cos(a) * 20.0, sin(a) * 24.0)
		var r := 2.5 + 1.5 * (0.5 + 0.5 * sin(time * 5.0 + i * 2.0))
		var pts := PackedVector2Array()
		for j in 8:
			var rr := r if j % 2 == 0 else r * 0.35
			var aa := j * PI / 4.0
			pts.append(at + Vector2(cos(aa), sin(aa)) * rr)
		c.draw_colored_polygon(pts, UiTokens.ON_SCRIM)
