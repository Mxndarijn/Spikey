extends HazardPainter
## Bouncer (Bramble Ball and its variants; Pumpkin Bounce skin): a spiked ball
## that rolls as it flies. Splitting Bramble shakes before it splits, Curious
## Bramble has an eye that looks toward the bird's height and Rev-Up Bramble
## shows its speed level as dots.

const BouncerHazard := preload("res://sim/hazards/bouncer.gd")
const SplittingBouncer := preload("res://sim/hazards/splitting_bouncer.gd")
const RevvingBouncer := preload("res://sim/hazards/revving_bouncer.gd")
const CuriousBouncer := preload("res://sim/hazards/curious_bouncer.gd")

const EYE_WHITE := Color("#FFFFFF")


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as BouncerHazard
	var theme := look.theme
	var time := look.time
	var center := HazardLayer.at(h.x, h.y)
	var r := HazardLayer.px(h.radius)
	var pumpkin := look.skin == "pumpkin"
	var spin := time * 2.0 * signf(h.vx)
	if h is SplittingBouncer:
		var s := h as SplittingBouncer
		if s.is_split():
			var o := s.other
			var oc := HazardLayer.at(o.x, o.y)
			var orad := HazardLayer.px(o.radius)
			if pumpkin:
				_pumpkin(c, oc, orad, theme)
			else:
				HazardLayer.spiky_ball(c, oc, orad, look, spin)
		elif s.warn > 0:
			# The warning: it shakes harder as the split comes closer.
			var k := float(s.warn) / s.WARN
			center += Vector2(sin(time * 60.0), cos(time * 75.0)) * 3.0 * k
			r *= 1.0 + 0.08 * k
	elif h is RevvingBouncer:
		var rv := h as RevvingBouncer
		spin *= 1.0 + 0.5 * rv.level
		_speed_dots(c, center, r, rv.level, rv.MAX_LEVEL, theme)
	if pumpkin:
		_pumpkin(c, center, r, theme)
		return
	HazardLayer.spiky_ball(c, center, r, look, spin)
	if h is CuriousBouncer:
		var eye := center
		c.draw_circle(eye, r * 0.34, EYE_WHITE)
		var pupil := eye + Vector2(0, r * 0.14 * (h as CuriousBouncer).look)
		c.draw_circle(pupil, r * 0.16, theme.spike)


## Ribbed pumpkin in the spike colour, with a small stem.
static func _pumpkin(c: CanvasItem, center: Vector2, r: float, theme: ThemeDef) -> void:
	for i in 3:
		var w := r * (1.0 - i * 0.25)
		c.draw_set_transform(center, 0.0, Vector2(w / r, 1.0))
		c.draw_circle(Vector2.ZERO, r, theme.spike if i == 0 else Color(theme.spike_edge, 0.35))
	c.draw_set_transform(Vector2.ZERO)
	var stem := r * 0.3
	c.draw_rect(
		Rect2(center + Vector2(-stem / 2, -r - stem), Vector2(stem, stem * 1.3)), theme.spike_edge
	)


## One dot per speed level under the ball: filled up to `level`.
func _speed_dots(
	c: CanvasItem, center: Vector2, r: float, level: int, top: int, theme: ThemeDef
) -> void:
	var gap := 6.0
	var left := center.x - gap * (top - 1) / 2.0
	for i in top:
		var p := Vector2(left + gap * i, center.y + r + 9.0)
		var col := theme.spike_edge if i < level else Color(theme.spike_edge, 0.3)
		c.draw_circle(p, 2.2, col)
