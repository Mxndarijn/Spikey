extends RefCounted
## Sunset Glow (Worlds v4): a big low sun behind three hills, clouds and birds,
## round trees, a wooden fence on the middle hill, grass tufts and flowers.

const WOOD := Color("#9A4E5E")
const FLOWER := Color("#FFF2CC")
const DARK := Color("#000000")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(478, 16, 1.1, 0.6, t.hill_far, 0)
	var mid := SceneGround.new(528, 14, 1.4, 2.2, t.hill_mid, 1)
	var near := SceneGround.new(584, 10, 1.0, 4.0, t.hill_near, 2)
	SceneProps.sun(pen, 186, 486, 86, t)
	SceneProps.cloud(pen, 18, 236, 100, t.cloud)
	SceneProps.cloud(pen, 250, 300, 96, t.cloud)
	SceneProps.birds(pen, [Vector2(60, 178), Vector2(82, 190), Vector2(300, 214)], t.prop)
	far.paint(pen)
	SceneProps.put(pen, far, [28, 46, 64, 250, 268, 330], SceneProps.p_round, sky, t.prop)
	mid.paint(pen)
	var wood := SceneProps.shade(WOOD, mid, sky)
	SceneProps.p_fence(pen, 128, 218, mid, wood, wood.lerp(DARK, 0.15))
	SceneProps.put(pen, mid, [36, 300, 322], SceneProps.p_round, sky, t.prop)
	near.paint(pen)
	var grass := t.hill_near.lerp(t.spike, 0.22)
	SceneProps.put(pen, near, [22, 46, 312, 338], SceneProps.p_tuft, sky, grass, 0)
	var stem := t.hill_near.lerp(t.spike, 0.3)
	SceneProps.put(pen, near, [70, 286], SceneProps.p_flower, sky, FLOWER, 0, [stem])
