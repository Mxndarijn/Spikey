extends HazardPainter
## Echo: the shadow bird in the spike colour (it kills), with a light eye. The
## echo also shows the path it will fly next (the bird's last second) as faint
## dots, so the danger is visible a second ahead. The mirror shows the room's
## point it turns round
## (the room's middle side to side, at the height drawn for it).

const EchoHazard := preload("res://sim/hazards/echo.gd")

const BODY := 12.0
const DOT_EVERY := 5


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as EchoHazard
	var theme := look.theme
	if h.mode == EchoHazard.Mode.ECHO:
		var n := h.xs.size()
		for k in range(0, n, DOT_EVERY):
			var i := (h.head + k) % n
			c.draw_circle(HazardLayer.at(h.xs[i], h.ys[i]), 2.5, Color(theme.spike, 0.3))
	else:
		var mid := Vector2(RoomView.W / 2.0, HazardLayer.px(h.pivot_y))
		c.draw_rect(Rect2(mid - Vector2(4, 4), Vector2(8, 8)), Color(theme.spike, 0.4))
	if not h.shown:
		return
	var p := HazardLayer.at(h.x, h.y)
	var f := float(h.facing)
	c.draw_circle(p, BODY, theme.spike)
	c.draw_circle(p + Vector2(-4.0 * f, 2.0), 6.0, theme.spike_edge)
	c.draw_colored_polygon(
		PackedVector2Array(
			[p + Vector2(10.0 * f, -3), p + Vector2(17.0 * f, 1), p + Vector2(10.0 * f, 4)]
		),
		theme.spike_edge
	)
	c.draw_circle(p + Vector2(5.0 * f, -4.0), 2.5, Color.WHITE)
	if look.ink:
		c.draw_arc(p, BODY, 0.0, TAU, 24, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W, true)
