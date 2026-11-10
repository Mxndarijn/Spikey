extends WorldScene
## Star Station (Worlds v4): stars, a ringed planet, a satellite and two
## asteroids over a big curved moon with craters, a little flag and a lander.

const RING := Color("#6B5BC8")
const PLANET := Color("#7A6BD6")
const PLANET_HI := Color("#9688E4")
const SAT_BODY := Color("#B9B3E8")
const SAT_PANEL := Color("#4A6BD6")
const SAT_LINE := Color("#241A63")
const SAT_EYE := Color("#7DE2FF")
const ROCK := Color("#4A3EA0")
const CRATER_LINE := Color("#3D3190")
# The art uses the spike colour #C9D3E6 for the pole; one step off it.
const POLE := Color("#C8D2E5")
const FLAG := Color("#FF5A7A")
const FLAG_SHADOW := Color(0, 0, 0, 0.2)
const LANDER_LEG := Color("#8E84D8")
const LANDER_FOIL := Color("#FFC93C")
const LANDER_FOIL_SHADE := Color("#E8A21A")
const STAR := Color("#FFFFFF")
const SCORE := Rect2(110, 90, 140, 95)

# The moon's surface: a big circle.
const MOON_R := 660.0
const MOON_C := Vector2(180, 1200)


func paint(pen: ScenePen, t: ThemeDef) -> void:
	_stars(pen)
	_planet(pen)
	_satellite(pen)
	for d: Vector3 in [Vector3(40, 330, 10), Vector3(310, 380, 7)]:
		var x := d.x
		var y := d.y
		var r := d.z
		var pts := PackedVector2Array(
			[
				Vector2(x - r, y),
				Vector2(x - r * 0.4, y - r),
				Vector2(x + r * 0.7, y - r * 0.8),
				Vector2(x + r, y + r * 0.2),
				Vector2(x + r * 0.2, y + r),
			]
		)
		pen.fill(pts, ROCK)
	pen.circle(MOON_C, MOON_R, t.hill_far)
	for d: Vector2 in [Vector2(70, 22), Vector2(226, 15), Vector2(300, 11), Vector2(150, 9)]:
		var c := Vector2(d.x, _surf(d.x) + 14 + d.y * 0.4)
		pen.ellipse(c, d.y, d.y * 0.32, t.hill_near)
		pen.stroke(ScenePen.ellipse_points(c, d.y, d.y * 0.32, 0, 0, PI), CRATER_LINE, 2, false)
	var fx := 280.0
	var fb := _surf(fx) + 2
	pen.stroke(PackedVector2Array([Vector2(fx, fb), Vector2(fx, fb - 34)]), POLE, 2.4, false)
	(
		pen
		. fill(
			PackedVector2Array(
				[
					Vector2(fx, fb - 34),
					Vector2(fx + 16, fb - 34),
					Vector2(fx + 12, fb - 29),
					Vector2(fx + 16, fb - 24),
					Vector2(fx, fb - 24),
				]
			),
			FLAG
		)
	)
	pen.ellipse(Vector2(fx, fb + 1), 7, 1.6, FLAG_SHADOW)
	_lander(pen, 112, _surf(112) + 2, 0.95)


## A small moon lander: gold foil body on three legs, a cabin and a dish.
static func _lander(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.ellipse(Vector2(0, 1), 17, 2.4, FLAG_SHADOW)
	for d: Vector2 in [Vector2(-8, -15), Vector2(8, 15), Vector2(0, 0)]:
		pen.line(d.x, -9, d.y, 0, LANDER_LEG, 2)
		pen.line(d.y - 3, 0, d.y + 3, 0, LANDER_LEG, 2.4)
	pen.fill(
		PackedVector2Array([Vector2(-11, -9), Vector2(-8, -21), Vector2(8, -21), Vector2(11, -9)]),
		LANDER_FOIL
	)
	pen.fill(
		PackedVector2Array(
			[Vector2(-11, -9), Vector2(-9.6, -14), Vector2(9.6, -14), Vector2(11, -9)]
		),
		LANDER_FOIL_SHADE
	)
	pen.rect(-6, -29, 12, 9, SAT_BODY, 3)
	pen.circle(Vector2(1, -24.5), 2.4, SAT_EYE)
	pen.line(6, -27, 13, -33, LANDER_LEG, 1.6)
	pen.fill(ScenePath.at(9.5, -37).a(5, false, false, 16.5, -30).done(), SAT_BODY)
	pen.pop()


## Like SceneProps.stars (40 above y 520, none near the planet's old spot),
## but none in front of the wall spikes or in the score area: white stars
## would be too close to the light spike colour.
static func _stars(pen: ScenePen) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40:
		var p := Vector2(rng.randf_range(10, 350), rng.randf_range(40, 520))
		var r: float = [1.0, 1.3, 1.7][rng.randi() % 3]
		var a := rng.randf_range(0.35, 0.85)
		if p.distance_to(Vector2(262, 170)) < 80:
			continue
		if p.x - r < 31 or p.x + r > 329 or SCORE.grow(r).has_point(p):
			continue
		pen.circle(p, r, Color(STAR, a))


static func _surf(x: float) -> float:
	return MOON_C.y - sqrt(MOON_R * MOON_R - (x - MOON_C.x) ** 2)


## The ringed planet; the front (lower) half of the ring goes over the planet.
static func _planet(pen: ScenePen) -> void:
	var c := Vector2(262, 170)
	pen.push(ScenePen.place(16, 54) * ScenePen.turn_about(-18, 262, 170))
	var back := ScenePen.ellipse_points(c, 96, 22)
	back.append(back[0])
	pen.stroke(back, RING, 7, false)
	pen.circle(c, 50, PLANET)
	pen.stroke(ScenePath.at(222, 146).q(262, 132, 302, 146).done(), PLANET_HI, 8)
	pen.stroke(ScenePen.ellipse_points(c, 96, 22, 0, 0, PI), RING, 7, false)
	pen.pop()


static func _satellite(pen: ScenePen) -> void:
	pen.push(ScenePen.place(92, 236, -12))
	pen.rect(-10, -8, 20, 16, SAT_BODY, 4)
	pen.rect(-38, -5, 24, 10, SAT_PANEL)
	pen.rect(14, -5, 24, 10, SAT_PANEL)
	pen.stroke(PackedVector2Array([Vector2(-26, -5), Vector2(-26, 5)]), SAT_LINE, 1.5, false)
	pen.stroke(PackedVector2Array([Vector2(26, -5), Vector2(26, 5)]), SAT_LINE, 1.5, false)
	pen.circle(Vector2.ZERO, 3, SAT_EYE)
	pen.pop()


func portal_touch_colors(_t: ThemeDef) -> Array[Color]:
	return [Color.WHITE]


func draw_portal_touch(p: PortalPen, _t: ThemeDef, cols: Array[Color]) -> void:
	PortalPainter.touch_stars(p, cols)
