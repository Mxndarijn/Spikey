class_name SceneProps
extends RefCounted
## The props of the flat room scenes (design canvas "Worlds v4"): each one is
## drawn standing on (x, b) at scale s, b being the ground surface sunk 2 px.
## Fixed colours are constants here so tests can check that none of them is a
## world's spike colour (only spikes may use that).

const SHADOW := Color(0, 0, 0, 0.13)
const WHITE := Color("#FFFFFF")
const FLOWER_EYE := Color("#FFF3B0")
const LOLLY_SWIRL := Color(1, 1, 1, 0.7)
const GUM_SHINE := Color(1, 1, 1, 0.8)
const SHELL_LINE := Color(1, 1, 1, 0.5)
const CUPCAKE_CUP := Color("#B69CFF")
const CUPCAKE_LINE := Color("#9C82EE")
const CHERRY := Color("#FF5A7A")
const PUMPKIN := Color("#F28C28")
const PUMPKIN_RIB := Color("#D9701E")
const PUMPKIN_STEM := Color("#3A5A2A")
const PUMPKIN_FACE := Color("#FFE08A")
const GRAVE_CROSS := Color("#2B1D58")
const CABIN_WALL := Color("#8A4A3A")
const CABIN_ROOF := Color("#6E3A2E")
const CABIN_DOOR := Color("#4A2A20")
const WINDOW_LIGHT := Color("#FFD27A")
const SNOWMAN_COAL := Color("#1E2A44")
const CARROT := Color("#FF9A3C")
const SCARF := Color("#2FA84F")
const TWIG := Color("#6E3A2E")
const LIGHTS := [
	Color("#FF5A5A"), Color("#FFD23F"), Color("#7FD3FF"), Color("#FF5A5A"), Color("#7FE3B5")
]
const TREE_STAR := Color("#FFD23F")
const PENGUIN := Color("#1E2A44")
const BEAK := Color("#FF9F43")


## Far things fade toward the sky; near things keep their colour.
static func shade(col: Color, g: SceneGround, sky: Color) -> Color:
	match g.depth:
		0:
			return col.lerp(sky, 0.5)
		1:
			return col.lerp(sky, 0.18)
	return col


## A small contact shadow under a prop (none on far hills).
static func shadow(pen: ScenePen, x: float, b: float, w: float, g: SceneGround) -> void:
	if g.depth == 0 or w <= 0.0:
		return
	pen.ellipse(Vector2(x, b + 1.0), w, w * 0.22, SHADOW)


## Stands `fn(pen, x, b, s, c, ...extra)` on the ground at each x, sunk 2 px
## so it never floats, scaled and faded for the layer's depth.
static func put(
	pen: ScenePen,
	g: SceneGround,
	xs: Array,
	fn: Callable,
	sky: Color,
	col: Color,
	shadow_w: float = 10.0,
	extra: Array = []
) -> void:
	var s := g.scale()
	var c := shade(col, g, sky)
	for xv: Variant in xs:
		var x := float(xv)
		var b := g.y(x) + 2.0
		shadow(pen, x, b, shadow_w * s, g)
		fn.callv([pen, x, b, s, c] + extra)


# ---------------------------------------------------------------- sky things


static func sun(pen: ScenePen, x: float, y: float, r: float, t: ThemeDef) -> void:
	pen.circle(Vector2(x, y), r + 18.0, t.sun_ring)
	pen.circle(Vector2(x, y), r, t.glow)


static func cloud(pen: ScenePen, x: float, y: float, w: float, col: Color) -> void:
	var h := w * 0.26
	pen.rect(x, y - h, w, h, col, h / 2.0)
	pen.circle(Vector2(x + w * 0.32, y - h), w * 0.17, col)
	pen.circle(Vector2(x + w * 0.56, y - h * 1.15), w * 0.22, col)
	pen.circle(Vector2(x + w * 0.76, y - h * 0.85), w * 0.13, col)


static func birds(pen: ScenePen, pts: Array, col: Color) -> void:
	for p: Vector2 in pts:
		pen.stroke(
			(
				ScenePath
				. at(p.x - 7, p.y)
				. q(p.x - 3, p.y - 5, p.x, p.y)
				. q(p.x + 3, p.y - 5, p.x + 7, p.y)
				. done()
			),
			col,
			2.2
		)


## `n` small white stars above y1, kept `avoid.z` px from (avoid.x, avoid.y).
static func stars(
	pen: ScenePen, seed_value: int, n: int, y1: float, avoid: Vector3 = Vector3(-999, -999, 0)
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var p := Vector2(rng.randf_range(10, 350), rng.randf_range(40, y1))
		var r: float = [1.0, 1.3, 1.7][rng.randi() % 3]
		var a := rng.randf_range(0.35, 0.85)
		if p.distance_to(Vector2(avoid.x, avoid.y)) < avoid.z:
			continue
		pen.circle(p, r, Color(1, 1, 1, a))


## A leaf (an ellipse `w` wide and `l` long) turned `deg` degrees.
static func leaf(
	pen: ScenePen, x: float, y: float, l: float, w: float, deg: float, col: Color
) -> void:
	pen.ellipse(Vector2(x, y), w, l, col, deg)


# ---------------------------------------------------------------- props


static func p_round(
	pen: ScenePen, x: float, b: float, s: float, c: Color, c2: Variant = null
) -> void:
	pen.rect(x - 2 * s, b - 16 * s, 4 * s, 16 * s, c if c2 == null else c2, 2 * s)
	pen.circle(Vector2(x, b - 22 * s), 10 * s, c)
	pen.circle(Vector2(x - 6 * s, b - 16 * s), 6.5 * s, c)
	pen.circle(Vector2(x + 6 * s, b - 17 * s), 6 * s, c)


static func p_pine(
	pen: ScenePen, x: float, b: float, s: float, c: Color, trunk: Variant = null
) -> void:
	pen.rect(x - 1.6 * s, b - 6 * s, 3.2 * s, 6 * s, c if trunk == null else trunk)
	var pts := PackedVector2Array()
	for p: Vector2 in [
		Vector2(0, -36),
		Vector2(9, -22),
		Vector2(5, -22),
		Vector2(12, -12),
		Vector2(7, -12),
		Vector2(14, -5),
		Vector2(-14, -5),
		Vector2(-7, -12),
		Vector2(-12, -12),
		Vector2(-5, -22),
		Vector2(-9, -22),
	]:
		pts.append(Vector2(x, b) + p * s)
	pen.fill(pts, c)


static func p_snowcap(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.fill(
		(
			ScenePath
			. at(x, b - 36 * s)
			. l(x + 5 * s, b - 28 * s)
			. q(x, b - 26 * s, x - 5 * s, b - 28 * s)
			. done()
		),
		WHITE
	)


static func p_bush(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	var p := ScenePath.at(x - 12 * s, b).a(7 * s, false, true, x - 3 * s, b - 9 * s)
	p.a(8 * s, false, true, x + 9 * s, b - 6 * s).a(5 * s, false, true, x + 13 * s, b)
	pen.fill(p.done(), c)


static func p_tuft(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	var p := ScenePath.at(x - 6 * s, b).q(x - 6 * s, b - 8 * s, x - 10 * s, b - 13 * s)
	p.q(x - 2 * s, b - 8 * s, x, b - 17 * s).q(x + 2 * s, b - 8 * s, x + 10 * s, b - 13 * s)
	p.q(x + 6 * s, b - 8 * s, x + 6 * s, b)
	pen.fill(p.done(), c)


static func p_flower(pen: ScenePen, x: float, b: float, s: float, c: Color, stem: Color) -> void:
	pen.line(x, b, x, b - 12 * s, stem, 1.8 * s)
	for k in 5:
		var a := k * TAU / 5.0
		pen.circle(Vector2(x + cos(a) * 3.2 * s, b - 14 * s + sin(a) * 3.2 * s), 2.6 * s, c)
	pen.circle(Vector2(x, b - 14 * s), 1.6 * s, FLOWER_EYE)


## A wooden fence along the ground from x0 to x1: two rails, pointed posts.
static func p_fence(
	pen: ScenePen, x0: float, x1: float, g: SceneGround, c: Color, c2: Color
) -> void:
	for dy: float in [13.0, 6.0]:
		pen.stroke(g.surface(x0, x1, 18, dy), c2, 4)
	var x := x0
	while x <= x1 + 0.01:
		var b := g.y(x) + 2
		(
			pen
			. fill(
				PackedVector2Array(
					[
						Vector2(x - 3, b),
						Vector2(x - 3, b - 20),
						Vector2(x, b - 24),
						Vector2(x + 3, b - 20),
						Vector2(x + 3, b),
					]
				),
				c
			)
		)
		x += 18


static func p_cactus(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.rect(x - 4 * s, b - 30 * s, 8 * s, 30 * s, c, 4 * s)
	pen.rect(x - 13 * s, b - 22 * s, 5.5 * s, 12 * s, c, 2.75 * s)
	pen.rect(x - 13 * s, b - 14 * s, 10 * s, 4.5 * s, c, 2.25 * s)
	pen.rect(x + 7.5 * s, b - 26 * s, 5.5 * s, 10 * s, c, 2.75 * s)
	pen.rect(x + 3 * s, b - 19 * s, 10 * s, 4.5 * s, c, 2.25 * s)


static func p_rock(
	pen: ScenePen, x: float, b: float, s: float, c: Color, hi: Variant = null
) -> void:
	var p := ScenePath.at(x - 13 * s, b + 1).q(x - 12 * s, b - 10 * s, x - 2 * s, b - 13 * s)
	p.q(x + 11 * s, b - 12 * s, x + 14 * s, b + 1)
	pen.fill(p.done(), c)
	if hi != null:
		pen.stroke(
			(
				ScenePath
				. at(x - 8 * s, b - 7 * s)
				. q(x - 4 * s, b - 11 * s, x + 2 * s, b - 11 * s)
				. done()
			),
			hi,
			2 * s
		)


static func p_crystal(pen: ScenePen, x: float, b: float, s: float, c: Color, c2: Color) -> void:
	for d: Vector3 in [Vector3(-11, 30, 7), Vector3(0, 48, 9), Vector3(11, 26, 6)]:
		var xx := x + d.x * s
		var hh := d.y * s
		var ww := d.z * s
		(
			pen
			. fill(
				PackedVector2Array(
					[
						Vector2(xx - ww, b + 1),
						Vector2(xx - ww, b - hh + ww),
						Vector2(xx, b - hh),
						Vector2(xx + ww, b - hh + ww),
						Vector2(xx + ww, b + 1),
					]
				),
				c
			)
		)
		pen.fill(
			PackedVector2Array(
				[
					Vector2(xx, b - hh),
					Vector2(xx + ww, b - hh + ww),
					Vector2(xx + ww, b + 1),
					Vector2(xx, b + 1)
				]
			),
			c2
		)


static func p_coral(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.line(x, b, x, b - 22 * s, c, 6 * s)
	pen.stroke(
		ScenePath.at(x, b - 10 * s).q(x - 12 * s, b - 14 * s, x - 12 * s, b - 28 * s).done(),
		c,
		6 * s
	)
	pen.stroke(
		ScenePath.at(x, b - 14 * s).q(x + 11 * s, b - 18 * s, x + 11 * s, b - 34 * s).done(),
		c,
		6 * s
	)


static func p_weed(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	var p := ScenePath.at(x, b).q(x - 7 * s, b - 10 * s, x, b - 20 * s).q(
		x + 7 * s, b - 30 * s, x, b - 40 * s
	)
	pen.stroke(p.done(), c, 4.5 * s)


static func p_starfish(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		var r := (7.0 if k % 2 == 0 else 3.0) * s
		pts.append(Vector2(x + cos(a) * r, b - 4 * s + sin(a) * r * 0.6))
	pen.fill(pts, c)
	pts.append(pts[0])
	pen.stroke(pts, c, 1.5, false)


static func p_shell(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.fill(ScenePath.at(x - 7 * s, b).a(7 * s, false, true, x + 7 * s, b).done(), c)
	pen.line(x, b, x, b - 6 * s, SHELL_LINE, 1.2)
	pen.line(x, b, x - 4 * s, b - 5 * s, SHELL_LINE, 1.2)
	pen.line(x, b, x + 4 * s, b - 5 * s, SHELL_LINE, 1.2)


static func p_lolly(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.rect(x - 1.4 * s, b - 22 * s, 2.8 * s, 22 * s, WHITE, 1)
	pen.circle(Vector2(x, b - 28 * s), 9 * s, c)
	pen.stroke(
		ScenePath.at(x - 5 * s, b - 28 * s).a(5 * s, true, true, x, b - 23 * s).done(),
		LOLLY_SWIRL,
		2.4 * s,
		false
	)


static func p_gumdrop(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	var p := ScenePath.at(x - 9 * s, b + 1).q(x - 9 * s, b - 14 * s, x, b - 14 * s)
	p.q(x + 9 * s, b - 14 * s, x + 9 * s, b + 1)
	pen.fill(p.done(), c)
	pen.circle(Vector2(x - 3 * s, b - 8 * s), 1.4 * s, GUM_SHINE)


static func p_cupcake(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.fill(
		PackedVector2Array(
			[
				Vector2(x - 13 * s, b),
				Vector2(x - 10 * s, b - 15 * s),
				Vector2(x + 10 * s, b - 15 * s),
				Vector2(x + 13 * s, b)
			]
		),
		CUPCAKE_CUP
	)
	pen.line(x - 6 * s, b, x - 5 * s, b - 15 * s, CUPCAKE_LINE, 1.6 * s)
	pen.line(x, b, x, b - 15 * s, CUPCAKE_LINE, 1.6 * s)
	pen.line(x + 6 * s, b, x + 5 * s, b - 15 * s, CUPCAKE_LINE, 1.6 * s)
	var p := ScenePath.at(x - 12 * s, b - 15 * s).q(x - 14 * s, b - 26 * s, x - 5 * s, b - 27 * s)
	p.q(x, b - 36 * s, x + 6 * s, b - 27 * s).q(x + 15 * s, b - 26 * s, x + 12 * s, b - 15 * s)
	pen.fill(p.done(), WHITE)
	pen.circle(Vector2(x, b - 35 * s), 3.6 * s, CHERRY)


static func p_pumpkin(pen: ScenePen, x: float, b: float, s: float, lit: bool = false) -> void:
	var r := 10 * s
	pen.ellipse(Vector2(x, b - r * 0.9), r * 1.25, r * 0.95, PUMPKIN)
	for side: float in [-1.0, 1.0]:
		var p := ScenePath.at(x + side * r * 0.45, b - r * 1.8).q(
			x + side * r * 0.6, b - r * 0.9, x + side * r * 0.45, b
		)
		pen.stroke(p.done(), PUMPKIN_RIB, 1.4 * s, false)
	pen.stroke(
		(
			ScenePath
			. at(x, b - r * 1.8)
			. q(x + 2 * s, b - r * 1.8 - 5 * s, x + 5 * s, b - r * 1.8 - 6 * s)
			. done()
		),
		PUMPKIN_STEM,
		2.2 * s
	)
	if lit:
		for ex: float in [x - r * 0.55, x + r * 0.05]:
			(
				pen
				. fill(
					PackedVector2Array(
						[
							Vector2(ex, b - r * 1.15),
							Vector2(ex + r * 0.25, b - r * 1.5),
							Vector2(ex + r * 0.5, b - r * 1.15),
						]
					),
					PUMPKIN_FACE
				)
			)
		var mouth := ScenePath.at(x - r * 0.6, b - r * 0.6).q(
			x, b - r * 0.6 + r * 0.45, x + r * 0.6, b - r * 0.6
		)
		pen.fill(mouth.done(), PUMPKIN_FACE)


static func p_grave(
	pen: ScenePen, x: float, b: float, s: float, c: Color, tilt: float = 0.0
) -> void:
	pen.push(ScenePen.turn_about(tilt, x, b))
	var p := (
		ScenePath
		. at(x - 8 * s, b + 1)
		. v(b - 14 * s)
		. a(8 * s, false, true, x + 8 * s, b - 14 * s)
		. v(b + 1)
	)
	pen.fill(p.done(), c)
	pen.line(x, b - 18 * s, x, b - 8 * s, GRAVE_CROSS, 1.8 * s)
	pen.line(x - 3.5 * s, b - 14.5 * s, x + 3.5 * s, b - 14.5 * s, GRAVE_CROSS, 1.8 * s)
	pen.pop()


static func p_bare(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.line(x, b + 1, x, b - 30 * s, c, 3.4 * s)
	pen.line(x, b - 14 * s, x - 10 * s, b - 25 * s, c, 3.4 * s)
	pen.line(x, b - 20 * s, x + 9 * s, b - 32 * s, c, 3.4 * s)
	pen.line(x - 6 * s, b - 20 * s, x - 12 * s, b - 22 * s, c, 3.4 * s)


static func p_house(pen: ScenePen, x: float, b: float, s: float, c: Color, win: Color) -> void:
	(
		pen
		. fill(
			PackedVector2Array(
				[
					Vector2(x - 18 * s, b + 2),
					Vector2(x - 18 * s, b - 34 * s),
					Vector2(x - 24 * s, b - 34 * s),
					Vector2(x + 2 * s, b - 62 * s),
					Vector2(x + 28 * s, b - 36 * s),
					Vector2(x + 22 * s, b - 36 * s),
					Vector2(x + 22 * s, b + 2),
				]
			),
			c
		)
	)
	pen.fill(
		PackedVector2Array(
			[
				Vector2(x + 12 * s, b - 48 * s),
				Vector2(x + 12 * s, b - 70 * s),
				Vector2(x + 20 * s, b - 70 * s),
				Vector2(x + 20 * s, b - 40 * s)
			]
		),
		c
	)
	pen.rect(x - 10 * s, b - 28 * s, 9 * s, 11 * s, win, 1.5)
	pen.rect(x + 6 * s, b - 16 * s, 8 * s, 10 * s, win, 1.5)
	pen.circle(Vector2(x + 2 * s, b - 46 * s), 3.5 * s, win)


static func p_cabin(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.rect(x - 18 * s, b - 22 * s, 36 * s, 23 * s, CABIN_WALL)
	var roof := PackedVector2Array(
		[Vector2(x - 24 * s, b - 20 * s), Vector2(x, b - 40 * s), Vector2(x + 24 * s, b - 20 * s)]
	)
	pen.fill(roof, CABIN_ROOF)
	pen.stroke(roof, WHITE, 6 * s)
	pen.rect(x + 8 * s, b - 46 * s, 6 * s, 12 * s, CABIN_ROOF)
	pen.rect(x - 12 * s, b - 16 * s, 9 * s, 8 * s, WINDOW_LIGHT, 1)
	pen.rect(x + 3 * s, b - 15 * s, 8 * s, 15 * s, CABIN_DOOR, 1)


static func p_snowman(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.circle(Vector2(x, b - 14 * s), 15 * s, WHITE)
	pen.circle(Vector2(x, b - 37 * s), 10 * s, WHITE)
	pen.circle(Vector2(x - 3.5 * s, b - 39 * s), 1.5 * s, SNOWMAN_COAL)
	pen.circle(Vector2(x + 3.5 * s, b - 39 * s), 1.5 * s, SNOWMAN_COAL)
	pen.fill(
		PackedVector2Array(
			[Vector2(x, b - 36 * s), Vector2(x + 8 * s, b - 34 * s), Vector2(x, b - 32.6 * s)]
		),
		CARROT
	)
	pen.rect(x - 11 * s, b - 29 * s, 22 * s, 4.5 * s, SCARF, 2)
	pen.rect(x - 8 * s, b - 56 * s, 16 * s, 10 * s, SNOWMAN_COAL, 2)
	pen.rect(x - 12 * s, b - 47 * s, 24 * s, 3 * s, SNOWMAN_COAL, 1.5)
	pen.line(x - 13 * s, b - 18 * s, x - 24 * s, b - 28 * s, TWIG, 2 * s)
	pen.line(x + 13 * s, b - 18 * s, x + 23 * s, b - 30 * s, TWIG, 2 * s)


## Fairy lights and a star for a pine at (x, b).
static func p_lights(pen: ScenePen, x: float, b: float, s: float) -> void:
	for k in LIGHTS.size():
		pen.circle(Vector2(x + (k - 2) * 4.5 * s, b - (7 + k * 5) * s), 1.8 * s, LIGHTS[k])
	var pts := PackedVector2Array([Vector2(x, b - 40 * s)])
	for d: Vector2 in [
		Vector2(2, 4),
		Vector2(4, 0.5),
		Vector2(-3, 3),
		Vector2(1, 4),
		Vector2(-4, -2),
		Vector2(-4, 2),
		Vector2(1, -4),
		Vector2(-3, -3),
		Vector2(4, -0.5),
	]:
		pts.append(pts[pts.size() - 1] + d * s)
	pen.fill(pts, TREE_STAR)


static func p_lamp(pen: ScenePen, x: float, b: float, s: float, c: Color, bulb: Color) -> void:
	pen.stroke(
		ScenePath.at(x, b + 1).v(b - 40 * s).q(x, b - 46 * s, x + 8 * s, b - 46 * s).done(),
		c,
		2.6 * s
	)
	pen.rect(x + 6 * s, b - 47 * s, 8 * s, 3.4 * s, bulb, 1.7)


static func p_penguin(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.ellipse(Vector2(x, b - 15 * s), 10 * s, 15 * s, PENGUIN)
	pen.ellipse(Vector2(x + 2 * s, b - 12 * s), 6.5 * s, 11 * s, WHITE)
	pen.circle(Vector2(x + 3 * s, b - 25 * s), 1.6 * s, PENGUIN)
	pen.fill(
		PackedVector2Array(
			[
				Vector2(x + 7 * s, b - 23 * s),
				Vector2(x + 13 * s, b - 21.5 * s),
				Vector2(x + 7 * s, b - 20 * s)
			]
		),
		BEAK
	)
	pen.stroke(
		ScenePath.at(x - 9 * s, b - 18 * s).q(x - 15 * s, b - 12 * s, x - 12 * s, b - 6 * s).done(),
		PENGUIN,
		3.5 * s
	)
	pen.line(x - 4 * s, b, x + 1 * s, b, BEAK, 2.5 * s)
	pen.line(x + 3 * s, b, x + 8 * s, b, BEAK, 2.5 * s)
