class_name SceneProps
extends RefCounted
## The props of the flat room scenes (design canvas "Worlds v4"): each one is
## drawn standing on (x, b) at scale s, b being the ground surface sunk 2 px.
## Fixed colours are constants here so tests can check that none of them is a
## world's spike colour (only spikes may use that).

const SHADOW := Color(0, 0, 0, 0.13)
const WHITE := Color("#FFFFFF")
const FLOWER_EYE := Color("#FFF3B0")
const LOLLY_SWIRL := Color(1, 1, 1, 0.9)
const GUM_SHINE := Color(1, 1, 1, 0.8)
const SHELL_LINE := Color(1, 1, 1, 0.6)
const SHELL_HINGE := Color("#F2A9BC")
const CUPCAKE_CUP := Color("#B69CFF")
const CUPCAKE_LINE := Color("#9C82EE")
const CHERRY := Color("#FF5A7A")
const CHERRY_STEM := Color("#8E2F4A")
const CHERRY_SHINE := Color(1, 1, 1, 0.8)
const FROSTING_SHADE := Color("#F6C6DB")
const SPRINKLES := [Color("#7FD3FF"), Color("#FFD23F"), Color("#7FE3B5"), Color("#FF6FA8")]
const LOLLY_STICK_SHADOW := Color(0, 0, 0, 0.13)
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
const SCARF_TAIL := Color("#258B41")
const SNOW_SHADE := Color("#CFE2F1")
const HAT_BAND := Color("#A3B4CC")
const TWIG := Color("#6E3A2E")
const LIGHTS := [
	Color("#FF5A5A"), Color("#FFD23F"), Color("#7FD3FF"), Color("#FF5A5A"), Color("#7FE3B5")
]
const TREE_STAR := Color("#FFD23F")
const PENGUIN := Color("#1E2A44")
const PENGUIN_FLIPPER := Color("#31426B")
const CHICK := Color("#8FA3BF")
const CHICK_CAP := Color("#5E7190")
const CHICK_FLIPPER := Color("#7388A6")
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


## A sun whose ring takes the colour of the sky behind it, so it sits right
## in every time of day.
static func sky_sun(pen: ScenePen, x: float, y: float, r: float, t: ThemeDef) -> void:
	pen.circle(Vector2(x, y), r + 18.0, pen.sky_at(y).lerp(t.glow, 0.45))
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


## Like stars(), for worlds with light spikes: none behind the wall spikes,
## where a white star would sit too close to the spike colour.
static func night_stars(
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
		if p.x - r < 31 or p.x + r > 329 or WorldScenes.SCORE_ZONE.grow(r).has_point(p):
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


## A three-lobed bush with a few lighter leaves (`hi`).
static func p_bush(
	pen: ScenePen, x: float, b: float, s: float, c: Color, hi: Variant = null
) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	var p := ScenePath.at(-17, 1).a(8.5, false, true, -7, -9.5)
	pen.fill(p.a(9.5, false, true, 9, -11).a(8.5, false, true, 17, 1).done(), c)
	if hi != null:
		pen.ellipse(Vector2(-7, -5.5), 3.4, 1.7, hi, -30)
		pen.ellipse(Vector2(3, -10), 3.8, 1.8, hi, -18)
		pen.ellipse(Vector2(10, -4.5), 3.2, 1.6, hi, 20)
	pen.pop()


## A grass tuft: five tapered blades fanning out from one root.
static func p_tuft(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	# Each blade: (where it roots, its tip x, its tip y).
	for d: Vector3 in [
		Vector3(-3.6, -9, -6.4),
		Vector3(-1.8, -4.5, -11),
		Vector3(0, 1, -13.7),
		Vector3(2.3, 6.4, -9.6),
		Vector3(4.1, 10, -5),
	]:
		var mid := (d.x + d.y) / 2.0
		var p := ScenePath.at(d.x - 2, 0).q(mid - 2.3, d.z * 0.55, d.y, d.z)
		pen.fill(p.q(mid + 2.3, d.z * 0.45, d.x + 2, 0).done(), c)
	pen.pop()


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


## A scallop shell: a fan with five ribs and a small hinge.
static func p_shell(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.fill(ScenePath.at(-4, 0).l(-13, -7).a(13.5, false, true, 13, -7).l(4, 0).done(), c)
	for deg: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var a := deg_to_rad(deg)
		pen.line(0, 0, sin(a) * 12, -cos(a) * 12, SHELL_LINE, 1.3)
	pen.rect(-5, -1.5, 10, 3, SHELL_HINGE, 1.5)
	pen.pop()


## A lollipop: a white stick and a disc with a spiral swirl.
static func p_lolly(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.rect(-1.6, -26, 3.2, 27, WHITE, 1.6)
	pen.circle(Vector2(0, -34), 11, c)
	var swirl := PackedVector2Array()
	for i in 41:
		var a := i / 40.0 * 4.2 * PI
		var r := 0.6 + i / 40.0 * 8.2
		swirl.append(Vector2(cos(a) * r, -34 + sin(a) * r))
	pen.stroke(swirl, LOLLY_SWIRL, 2.3)
	pen.pop()


static func p_gumdrop(pen: ScenePen, x: float, b: float, s: float, c: Color) -> void:
	var p := ScenePath.at(x - 9 * s, b + 1).q(x - 9 * s, b - 14 * s, x, b - 14 * s)
	p.q(x + 9 * s, b - 14 * s, x + 9 * s, b + 1)
	pen.fill(p.done(), c)
	pen.circle(Vector2(x - 3 * s, b - 8 * s), 1.4 * s, GUM_SHINE)


## A cupcake: a pleated cup, three piped tiers of frosting, sprinkles, a cherry.
static func p_cupcake(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.fill(
		PackedVector2Array(
			[Vector2(-13, 0), Vector2(-10.5, -16), Vector2(10.5, -16), Vector2(13, 0)]
		),
		CUPCAKE_CUP
	)
	# Pleats: (bottom left, top left, top right, bottom right) x.
	for d: Vector4 in [
		Vector4(-9.4, -7.6, -4.6, -5.6), Vector4(-1.9, -1.5, 1.5, 1.9), Vector4(5.6, 4.6, 7.6, 9.4)
	]:
		pen.fill(
			PackedVector2Array(
				[Vector2(d.x, 0), Vector2(d.y, -16), Vector2(d.z, -16), Vector2(d.w, 0)]
			),
			CUPCAKE_LINE
		)
	# Frosting tiers: (half width, top, height), each over its own shade.
	for d: Vector3 in [Vector3(14.5, -24, 10), Vector3(10.5, -31, 9), Vector3(6.5, -37, 8)]:
		pen.rect(-d.x, d.y + 2, d.x * 2, d.z, FROSTING_SHADE, d.z / 2.0)
		pen.rect(-d.x, d.y, d.x * 2, d.z, WHITE, d.z / 2.0)
	# Sprinkles: (x, y, turn).
	var dots := [Vector3(-7, -20, -20), Vector3(5, -19, 25), Vector3(-2, -27, 15)]
	dots.append(Vector3(6, -26.6, -30))
	for i in dots.size():
		var d: Vector3 = dots[i]
		pen.ellipse(Vector2(d.x, d.y), 2.0, 0.9, SPRINKLES[i], d.z)
	pen.stroke(ScenePath.at(0, -41).q(1, -46, 5, -47).done(), CHERRY_STEM, 1.4)
	pen.circle(Vector2(0, -40), 4, CHERRY)
	pen.circle(Vector2(-1.2, -41.3), 1, CHERRY_SHINE)
	pen.pop()


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


## A snowman of three balls, each over a shade so it reads on white snow, with
## coal buttons, a scarf with a tail, a top hat and forked twig arms.
static func p_snowman(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.circle(Vector2(-1, -12), 13.5, SNOW_SHADE)
	pen.circle(Vector2(1, -13), 12.5, WHITE)
	for side: float in [-1.0, 1.0]:
		pen.line(side * 12, -27, side * 24, -37.5, TWIG, 2)
		pen.line(side * 19, -33, side * 20, -39.5, TWIG, 2)
		pen.line(side * 19, -33, side * 25, -32.5, TWIG, 2)
	pen.circle(Vector2(-0.8, -29.5), 10, SNOW_SHADE)
	pen.circle(Vector2(1, -30.5), 9.2, WHITE)
	pen.circle(Vector2(-0.6, -43.5), 7.6, SNOW_SHADE)
	pen.circle(Vector2(1, -44.2), 7, WHITE)
	for y: float in [-31.0, -25.5, -14.0]:
		pen.circle(Vector2(1.5, y), 1.4, SNOWMAN_COAL)
	pen.rect(-8, -39.5, 17, 4.6, SCARF, 2.3)
	pen.rect(4, -38, 4.6, 11, SCARF_TAIL, 2.2)
	pen.circle(Vector2(-1.6, -45.5), 1.3, SNOWMAN_COAL)
	pen.circle(Vector2(4, -45.5), 1.3, SNOWMAN_COAL)
	pen.fill(
		PackedVector2Array([Vector2(1.5, -43.6), Vector2(10.5, -42), Vector2(1.5, -40.6)]), CARROT
	)
	pen.rect(-9, -52, 20, 3, SNOWMAN_COAL, 1.5)
	pen.rect(-5.5, -61, 13, 10, SNOWMAN_COAL, 2)
	pen.rect(-5.5, -55, 13, 2.4, HAT_BAND)
	pen.pop()


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


## A penguin with a head, a white face and belly, a flipper and two feet.
## `chick` is a grey young one; `flip` faces it left.
static func p_penguin(
	pen: ScenePen, x: float, b: float, s: float, chick: bool = false, flip: bool = false
) -> void:
	pen.push(ScenePen.place(x, b, 0.0, -s if flip else s, s))
	pen.ellipse(Vector2(-3.5, -1.2), 4.6, 2.1, BEAK)
	pen.ellipse(Vector2(5, -1.2), 4.6, 2.1, BEAK)
	pen.ellipse(Vector2(0, -15), 11, 15, CHICK if chick else PENGUIN)
	pen.circle(Vector2(1.5, -31), 9, CHICK_CAP if chick else PENGUIN)
	pen.ellipse(Vector2(3, -13), 7.4, 11.5, WHITE)
	pen.circle(Vector2(4.6, -30), 5.6, WHITE)
	pen.circle(Vector2(6.2, -31.4), 1.5, PENGUIN)
	pen.fill(
		PackedVector2Array([Vector2(9.6, -30.5), Vector2(16.5, -28.5), Vector2(9.6, -26.2)]), BEAK
	)
	pen.ellipse(Vector2(-10.4, -15.2), 3.3, 9.5, CHICK_FLIPPER if chick else PENGUIN_FLIPPER, 14)
	pen.pop()
