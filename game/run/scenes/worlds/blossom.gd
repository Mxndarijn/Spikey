extends RefCounted
## Blossom (Worlds v4): a blossom branch in the top-left corner, white round
## trees on the far hill, a small blossom tree, grass tufts and flowers.

const BRANCH := Color("#7A3A5E")
const PETAL := Color("#FFFFFF")
const FAR_TRUNK := Color("#B8869E")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(520, 16, 1.0, 1.2, t.hill_far, 0)
	var mid := SceneGround.new(560, 14, 1.3, 3.0, t.hill_mid, 1)
	var near := SceneGround.new(600, 8, 1.2, 0.6, t.hill_near, 2)
	# The art's branch starts at the wall (0, 214); it starts at x 34 instead (the
	# same curve, cut) so the dark wood stays clear of the wall spikes.
	var main := ScenePath.at(34, 209.7).q(61.6, 210.9, 82, 230).q(100, 250, 96, 280)
	pen.stroke(main.done(), BRANCH, 8)
	pen.stroke(ScenePath.at(40, 206).q(52, 184, 76, 178).done(), BRANCH, 8)
	pen.stroke(ScenePath.at(82, 230).q(104, 222, 118, 236).done(), BRANCH, 8)
	for d: Vector3 in [
		Vector3(76, 178, 14),
		Vector3(96, 280, 15),
		Vector3(118, 236, 13),
		Vector3(20, 202, 12),
		Vector3(60, 222, 11),
		Vector3(98, 254, 10),
	]:
		_bloom(pen, d.x, d.y, d.z, t.prop)
	far.paint(pen)
	SceneProps.put(pen, far, [40, 70, 250, 310], SceneProps.p_round, sky, PETAL, 10, [FAR_TRUNK])
	mid.paint(pen)
	var tx := 290.0
	var tb := mid.y(tx) + 2
	SceneProps.shadow(pen, tx, tb, 20, mid)
	pen.stroke(ScenePath.at(tx, tb).q(tx - 4, tb - 30, tx + 2, tb - 52).done(), BRANCH, 6)
	pen.stroke(ScenePath.at(tx, tb - 30).q(tx - 16, tb - 40, tx - 26, tb - 50).done(), BRANCH, 6)
	for d: Vector3 in [
		Vector3(2, -60, 16), Vector3(-24, -56, 13), Vector3(16, -48, 12), Vector3(-10, -70, 11)
	]:
		_bloom(pen, tx + d.x, tb + d.y, d.z, t.prop)
	near.paint(pen)
	var grass := t.hill_near.lerp(t.spike, 0.18)
	SceneProps.put(pen, near, [30, 56, 200, 336], SceneProps.p_tuft, sky, grass, 0)
	var stem := t.hill_near.lerp(t.spike, 0.3)
	SceneProps.put(pen, near, [120, 156], SceneProps.p_flower, sky, PETAL, 0, [stem])


## One blossom: five white petals round a centre of colour `c`.
static func _bloom(pen: ScenePen, x: float, y: float, r: float, c: Color) -> void:
	for k in 5:
		var a := k * TAU / 5.0
		pen.circle(Vector2(x + cos(a) * r * 0.55, y + sin(a) * r * 0.55), r * 0.5, PETAL)
	pen.circle(Vector2(x, y), r * 0.25, c)
