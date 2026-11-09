extends RefCounted
## Cloud Kingdom: above the weather. Three banks of cloud instead of hills, a
## castle rising out of the middle one, a rainbow behind them, two balloons.

const RAINBOW := [
	Color("#FF9FB2"), Color("#FFC98A"), Color("#FFEE9A"), Color("#A9E5BD"), Color("#A5CFFF")
]
const BIRD := Color("#8FA9D6")
const BASKET := Color("#B7814F")
const ROPE := Color("#8A5A44")
const BALLOON_PINK := Color("#FF8FA8")
const BALLOON_PINK_GORE := Color("#FFD9E2")
const BALLOON_GOLD := Color("#FFC93C")
const BALLOON_GOLD_GORE := Color("#FFEDB0")
const WALL := Color("#DCD5F8")
const TURRET_ROOF := Color("#FF8FA8")
const WINDOW := Color("#8E84D8")
const PENNANT := Color("#FFC93C")
## The seed's own number sequence, so the puffs stand the same on every phone.
const LCG_MUL := 16807
const LCG_MOD := 2147483647


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var far := SceneGround.new(506, 12, 1.0, 0.8, t.hill_far, 0)
	var mid := SceneGround.new(552, 11, 1.3, 2.5, t.hill_mid, 1)
	var near := SceneGround.new(600, 7, 1.1, 4.4, t.hill_near, 2)
	SceneProps.sky_sun(pen, 292, 236, 24, t)
	SceneProps.cloud(pen, 196, 304, 78, t.cloud)
	for i in RAINBOW.size():
		pen.ring(Vector2(84, 566), 150 - i * 7, RAINBOW[i], 7.2)
	_balloon(pen, 62, 262, 0.95, BALLOON_PINK, BALLOON_PINK_GORE)
	_balloon(pen, 306, 372, 0.62, BALLOON_GOLD, BALLOON_GOLD_GORE)
	SceneProps.birds(pen, [Vector2(150, 222), Vector2(168, 232)], BIRD)
	_bank(pen, far, 7)
	_castle(pen, 262, mid.y(262) + 8, 1.45, t.prop)
	_bank(pen, mid, 19)
	_bank(pen, near, 43)


## A bank of cloud: the ground curve with round puffs along its top.
static func _bank(pen: ScenePen, g: SceneGround, seed_value: int) -> void:
	g.paint(pen)
	var state := seed_value
	var x := -14.0
	while x < 380.0:
		state = state * LCG_MUL % LCG_MOD
		var r := 13.0 + float(state) / LCG_MOD * 12.0
		pen.circle(Vector2(x, g.y(x) + r * 0.35), r, g.col)
		state = state * LCG_MUL % LCG_MOD
		x += 26.0 + float(state) / LCG_MOD * 14.0


## A hot-air balloon centred on (x, y): envelope with a lighter gore, a basket.
static func _balloon(pen: ScenePen, x: float, y: float, s: float, col: Color, gore: Color) -> void:
	pen.push(ScenePen.place(x, y, 0.0, s, s))
	pen.line(-5, 19, -3.5, 25, ROPE, 1.1)
	pen.line(5, 19, 3.5, 25, ROPE, 1.1)
	pen.rect(-4.5, 24, 9, 6.5, BASKET, 1.6)
	var p := ScenePath.at(-17, -5).a(17, true, true, 17, -5).q(13, 10, 5, 19).l(-5, 19)
	pen.fill(p.q(-13, 10, -17, -5).done(), col)
	p = ScenePath.at(-6, -21).q(-10, -3, -3, 19).l(3, 19).q(10, -3, 6, -21)
	pen.fill(p.q(0, -23, -6, -21).done(), gore)
	pen.pop()


## A castle: a keep with battlements between two turrets with pennants.
static func _castle(pen: ScenePen, x: float, b: float, s: float, shade: Color) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.rect(-20, -36, 11, 37, WALL)
	pen.rect(9, -46, 11, 47, shade)
	pen.rect(-10, -26, 20, 27, WALL)
	pen.rect(0, -26, 10, 27, shade)
	for mx: float in [-10.0, -2.0, 6.0]:
		pen.rect(mx, -31, 4, 5.5, WALL)
	pen.fill(
		PackedVector2Array([Vector2(-22.5, -36), Vector2(-14.5, -53), Vector2(-6.5, -36)]),
		TURRET_ROOF
	)
	pen.fill(
		PackedVector2Array([Vector2(6.5, -46), Vector2(14.5, -65), Vector2(22.5, -46)]), TURRET_ROOF
	)
	# Pennants: (x, top of the pole).
	for d: Vector2 in [Vector2(-14.5, -61), Vector2(14.5, -73)]:
		pen.line(d.x, d.y + 8, d.x, d.y, WINDOW, 1.2)
		pen.fill(
			PackedVector2Array(
				[Vector2(d.x, d.y), Vector2(d.x + 6.5, d.y + 2.5), Vector2(d.x, d.y + 5)]
			),
			PENNANT
		)
	pen.fill(ScenePath.at(-3.5, 1).v(-8).a(3.5, false, true, 3.5, -8).v(1).done(), WINDOW)
	pen.rect(-16.5, -28, 4, 6.5, WINDOW, 2)
	pen.rect(12.5, -36, 4, 6.5, WINDOW, 2)
	pen.rect(-2, -21, 4, 6, WINDOW, 2)
	pen.pop()
