extends RefCounted
## Jungle Canopy (Worlds v4): a leafy canopy with hanging vines, soft light
## spots, a parrot, round trees and bushes on three hills, big front leaves
## and pink flowers.

const PARROT := Color("#FF5A5A")
## Close to the art's eye colour, which is the jungle spike colour.
const PARROT_EYE := Color("#142D22")
const BEAK := Color("#FFD23F")
const PARROT_TAIL := Color("#3FA9F5")
const FLOWER := Color("#FF6FA8")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(536, 8, 2.4, 1.0, t.hill_far, 0)
	var mid := SceneGround.new(570, 9, 1.6, 2.6, t.hill_mid, 1)
	var near := SceneGround.new(604, 6, 1.2, 0.4, t.hill_near, 2)
	# Soft light spots.
	for p: Vector2 in [Vector2(120, 230), Vector2(250, 300), Vector2(70, 360)]:
		pen.circle(p, 14, Color(t.glow, 0.5))
	# The canopy along the ceiling.
	var i := 0
	for x in range(-10, 380, 34):
		var odd := i % 2 == 1
		var col := t.hill_mid if odd else t.hill_near
		SceneProps.leaf(pen, x, 34 + (i % 2) * 12, 40, 18, 20 if odd else -25, col)
		i += 1
	# Hanging vines with small leaves: (x, length).
	for v: Vector2 in [Vector2(46, 170), Vector2(318, 120)]:
		pen.stroke(ScenePath.at(v.x, 30).q(v.x + 14, 30 + v.y / 2, v.x, 30 + v.y).done(), t.prop, 3)
		for k in 3:
			SceneProps.leaf(pen, v.x + 7, 50 + k * v.y / 3, 9, 5, 50, t.hill_near)
	_parrot(pen, 320, 152)
	far.paint(pen)
	SceneProps.put(pen, far, range(10, 360, 26), SceneProps.p_round, sky, t.prop)
	mid.paint(pen)
	var bush := t.hill_mid.lerp(t.spike, 0.2)
	var bush_leaf := SceneProps.shade(t.hill_far.lerp(t.hill_mid, 0.5), mid, sky)
	SceneProps.put(pen, mid, [30, 96, 170, 250, 330], SceneProps.p_bush, sky, bush, 16, [bush_leaf])
	near.paint(pen)
	# Big leaves leaning in from both sides: (x, length, turn).
	var big := t.hill_near.lerp(t.spike, 0.12)
	for d: Vector3 in [
		Vector3(18, 64, 28), Vector3(46, 52, 58), Vector3(338, 68, -30), Vector3(310, 50, -58)
	]:
		var b := near.y(d.x) + 4
		_big_leaf(pen, d.x, b - d.y * 0.7, d.y, d.z, big, t.hill_mid)
	SceneProps.put(pen, near, [86, 120, 236, 276], SceneProps.p_flower, sky, FLOWER, 0, [t.prop])


## A pointed leaf `l` long each way from (x, y), turned `deg`, with a midrib
## and four pairs of side veins in `vein`.
static func _big_leaf(
	pen: ScenePen, x: float, y: float, l: float, deg: float, col: Color, vein: Color
) -> void:
	var w := l * 0.46
	pen.push(ScenePen.place(x, y, deg))
	var p := ScenePath.at(0, l).c(-w * 1.45, l * 0.45, -w * 1.15, -l * 0.5, 0, -l)
	pen.fill(p.c(w * 1.15, -l * 0.5, w * 1.45, l * 0.45, 0, l).done(), col)
	pen.line(0, l * 0.92, 0, -l * 0.82, vein, 2.2)
	for k: float in [0.55, 0.2, -0.15, -0.48]:
		for side: float in [-1.0, 1.0]:
			var tip := Vector2(side * w * (0.72 - absf(k) * 0.35), l * (k - 0.26))
			var v := ScenePath.at(0, l * k).q(side * w * 0.35, l * (k - 0.08), tip.x, tip.y)
			pen.stroke(v.done(), vein, 2.2)
	pen.pop()


static func _parrot(pen: ScenePen, x: float, y: float) -> void:
	pen.push(ScenePen.place(x, y))
	pen.ellipse(Vector2.ZERO, 7, 11, PARROT)
	pen.circle(Vector2(2, -10), 5.5, PARROT)
	pen.circle(Vector2(4, -11), 1.5, PARROT_EYE)
	pen.fill(PackedVector2Array([Vector2(7, -10), Vector2(11, -7), Vector2(7, -6)]), BEAK)
	pen.fill(ScenePath.at(-5, 2).q(-9, 14, -3, 22).l(0, 10).done(), PARROT_TAIL)
	pen.pop()
