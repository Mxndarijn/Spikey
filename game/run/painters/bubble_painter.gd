extends HazardPainter
## Bubble (Bubble Lift): a clear wobbling bubble with a white rim and shine.
## Safe, so never in the spike colour. A carrying bubble glows brighter.
## Coin Bubbles: a coin floats inside (dimmed until it can be taken).
## Spiky Bubbles: a solid spiked ball in the spike colour with no clear rim,
## so it never reads as a safe bubble; while it waits under the floor its
## spike tips peek up and pulse where it will rise.

const BubbleHazard := preload("res://sim/hazards/bubble.gd")

const COIN := preload("res://assets/ui/coin.svg")
const COIN_SIZE := 24.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BubbleHazard
	if h.spiked:
		_paint_spiked(c, h, look)
		return
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.x, h.y)
	var r := HazardLayer.px(h.radius)
	var wobble := sin(time * 5.0 + h.lane * 1.7) * 0.05
	c.draw_set_transform(center, 0.0, Vector2(1.0 + wobble, 1.0 - wobble))
	var fill := Color(theme.glow, 0.32 if h.carrying else 0.16)
	c.draw_circle(Vector2.ZERO, r, fill)
	c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.75), 2.0, true)
	if h.has_coin:
		var tint := Color(1, 1, 1, 1.0 if h.coin_in_reach() else 0.45)
		var half := Vector2(COIN_SIZE, COIN_SIZE) / 2.0
		c.draw_texture_rect(COIN, Rect2(-half, half * 2.0), false, tint)
	# Shine.
	c.draw_arc(Vector2.ZERO, r * 0.7, PI * 1.1, PI * 1.45, 12, Color(1, 1, 1, 0.8), 3.0, true)
	c.draw_circle(Vector2(r * 0.35, -r * 0.45), r * 0.1, Color(1, 1, 1, 0.85))
	c.draw_set_transform(Vector2.ZERO)


func _paint_spiked(c: CanvasItem, h: BubbleHazard, look: HazardLook) -> void:
	var time := look.time
	var r := HazardLayer.px(h.radius)
	var spin := time * 1.5 + h.lane
	if h.wait > 0:
		# The warning: its top peeks over the floor line, rising and pulsing.
		var k := 1.0 - float(h.wait) / h.WARN
		var floor_y := HazardLayer.px(SimConfig.KILL_BOTTOM)
		var peek := Vector2(HazardLayer.px(h.x), floor_y + r * (1.0 - 0.6 * k))
		var pulse := 0.55 + 0.45 * absf(sin(time * 9.0))
		c.draw_circle(
			Vector2(peek.x, floor_y), r * (1.1 + 0.3 * k), Color(look.theme.spike, 0.18 * pulse)
		)
		HazardLayer.spiky_ball(c, peek, r, look, spin)
		return
	HazardLayer.spiky_ball(c, HazardLayer.at(h.x, h.y), r, look, spin)
