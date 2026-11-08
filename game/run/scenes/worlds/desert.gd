extends RefCounted
## Desert Dusk (Worlds v4): a big low sun, birds, two flat-topped mesas,
## cacti and rocks on two dunes and a tumbleweed.

const WEED := Color("#7C4F7A", 0.8)


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
	mid.paint(pen)
	SceneProps.put(pen, mid, [58, 210], SceneProps.p_cactus, sky, t.prop, 9)
	var rock := t.hill_mid.lerp(t.spike, 0.2)
	SceneProps.put(pen, mid, [300], SceneProps.p_rock, sky, rock, 9)
	near.paint(pen)
	SceneProps.put(pen, near, [72, 312], SceneProps.p_cactus, sky, t.prop, 11)
	rock = t.hill_near.lerp(t.spike, 0.2)
	SceneProps.put(pen, near, [150, 250], SceneProps.p_rock, sky, rock, 10)
	_tumbleweed(pen, near)


## A see-through tumbleweed resting on the near dune.
static func _tumbleweed(pen: ScenePen, near: SceneGround) -> void:
	var x := 196.0
	var y := near.y(x) - 7
	SceneProps.shadow(pen, x, near.y(x) + 2, 8, near)
	pen.ring(Vector2(x, y), 9, WEED, 2)
	pen.stroke(PackedVector2Array([Vector2(x - 7, y - 6), Vector2(x + 7, y + 6)]), WEED, 2, false)
	pen.stroke(PackedVector2Array([Vector2(x - 6, y + 5), Vector2(x + 6, y - 5)]), WEED, 2, false)
	pen.stroke(PackedVector2Array([Vector2(x, y - 9), Vector2(x, y + 9)]), WEED, 2, false)
