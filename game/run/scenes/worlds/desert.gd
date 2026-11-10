extends RefCounted
## Desert Dusk (Worlds v4): a big low sun, birds, two flat-topped mesas with
## bands of rock, cacti and rocks on two dunes and a tumbleweed.

const WEED := Color("#7C4F7A", 0.8)
const WEED_BALL := Color("#7C4F7A", 0.27)


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var mid := SceneGround.new(526, 18, 0.9, 0.2, t.hill_mid, 1)
	var near := SceneGround.new(584, 12, 1.1, 2.6, t.hill_near, 2)
	SceneProps.sun(pen, 250, 420, 82, t)
	SceneProps.birds(pen, [Vector2(80, 210), Vector2(100, 222), Vector2(300, 250)], t.prop)
	var mesa := ScenePath.at(0, 640).v(430).h(40).l(52, 402).h(120).l(132, 430).h(170).v(640)
	pen.fill(mesa.done(), t.hill_far)
	mesa = ScenePath.at(230, 640).v(470).l(244, 446).h(330).l(344, 470).h(360).v(640)
	pen.fill(mesa.done(), t.hill_far)
	# Bands of darker rock across both mesas: (left top, right top, left bottom,
	# right bottom) x, then top and bottom y.
	var strata := t.hill_far.lerp(t.prop, 0.14)
	for d: Array in [
		[47.7, 124.3, 45.1, 126.9, 412, 418],
		[0, 170, 0, 170, 452, 460],
		[0, 170, 0, 170, 486, 491],
		[239.3, 334.7, 235.8, 338.2, 454, 460],
		[230, 360, 230, 360, 490, 497],
	]:
		pen.fill(
			PackedVector2Array(
				[Vector2(d[0], d[4]), Vector2(d[1], d[4]), Vector2(d[3], d[5]), Vector2(d[2], d[5])]
			),
			strata
		)
	mid.paint(pen)
	SceneProps.put(pen, mid, [58, 210], SceneProps.p_cactus, sky, t.prop, 9)
	var rock := t.hill_mid.lerp(t.spike, 0.2)
	SceneProps.put(pen, mid, [300], SceneProps.p_rock, sky, rock, 9)
	near.paint(pen)
	SceneProps.put(pen, near, [72, 312], SceneProps.p_cactus, sky, t.prop, 11)
	rock = t.hill_near.lerp(t.spike, 0.2)
	SceneProps.put(pen, near, [150, 250], SceneProps.p_rock, sky, rock, 10)
	_tumbleweed(pen, near)


## A tumbleweed resting on the near dune: a faint ball of brush with curved
## twigs across it and a few poking out.
static func _tumbleweed(pen: ScenePen, near: SceneGround) -> void:
	var x := 196.0
	var r := 10.0
	SceneProps.shadow(pen, x, near.y(x) + 2, 9, near)
	pen.push(ScenePen.place(x, near.y(x) - 9))
	pen.circle(Vector2.ZERO, r * 0.97, WEED_BALL)
	pen.ring(Vector2.ZERO, r, WEED, 1.5)
	# Twigs: (from angle, to angle, how far it bows).
	for d: Vector3 in [
		Vector3(0.3, 2.9, 0.5),
		Vector3(1.1, 3.9, -0.4),
		Vector3(1.9, 5.2, 0.35),
		Vector3(2.6, 5.9, -0.5),
		Vector3(3.4, 0.9, 0.3),
		Vector3(4.3, 1.6, -0.35),
		Vector3(5.0, 2.2, 0.45),
	]:
		var a := Vector2.from_angle(d.x) * r
		var b := Vector2.from_angle(d.y) * r
		var bow := Vector2(-(b.y - a.y), b.x - a.x) * d.z
		pen.stroke(ScenePath.at(a.x, a.y).q(bow.x, bow.y, b.x, b.y).done(), WEED, 1.25)
	for angle: float in [0.7, 2.2, 3.7, 5.5]:
		var from := Vector2.from_angle(angle) * r * 0.8
		var to := Vector2.from_angle(angle + 0.15) * r * 1.28
		pen.line(from.x, from.y, to.x, to.y, WEED, 1.25)
	pen.pop()
