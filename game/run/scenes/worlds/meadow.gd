extends RefCounted
## Windmill Meadow: a plain sunny day. A small sun and two clouds, a barn and
## round trees on the far hill, a windmill and a fence on the middle one, two
## sheep, grass tufts and flowers up front.

const TOWER := Color("#F7EBD8")
const TOWER_SHADE := Color("#E6D4B8")
const ROOF := Color("#C9584A")
const WOOD := Color("#8A5A44")
const SAIL := Color("#FFFFFF")
const BARN := Color("#D9584A")
const BARN_ROOF := Color("#B8433A")
const BARN_TRIM := Color("#FFF4E2")
const FENCE := Color("#B98A5E")
const DARK := Color("#000000")
const WOOL := Color("#FFFFFF")
const SHEEP_FACE := Color("#3B3F5C")
const DAISY := Color("#FFFFFF")
const BUTTERCUP := Color("#FFE066")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(486, 14, 1.1, 0.6, t.hill_far, 0)
	var mid := SceneGround.new(534, 13, 1.4, 2.2, t.hill_mid, 1)
	var near := SceneGround.new(588, 9, 1.0, 4.0, t.hill_near, 2)
	SceneProps.sky_sun(pen, 288, 232, 26, t)
	SceneProps.cloud(pen, 22, 252, 96, t.cloud)
	SceneProps.cloud(pen, 212, 322, 84, t.cloud)
	SceneProps.birds(pen, [Vector2(70, 200), Vector2(90, 212)], t.prop)
	far.paint(pen)
	SceneProps.put(pen, far, [34, 52, 160, 178, 318], SceneProps.p_round, sky, t.prop)
	_barn(pen, 104, far.y(104) + 2, 0.72)
	mid.paint(pen)
	SceneProps.shadow(pen, 254, mid.y(254) + 2, 12, mid)
	_windmill(pen, 254, mid.y(254) + 2, 1.05)
	var wood := SceneProps.shade(FENCE, mid, sky)
	SceneProps.p_fence(pen, 44, 116, mid, wood, wood.lerp(DARK, 0.12))
	SceneProps.put(pen, mid, [150, 320], SceneProps.p_round, sky, t.prop, 8)
	near.paint(pen)
	SceneProps.shadow(pen, 116, near.y(116) + 2, 12, near)
	_sheep(pen, 116, near.y(116) + 2, 1.0, false)
	SceneProps.shadow(pen, 146, near.y(146) + 2, 9, near)
	_sheep(pen, 146, near.y(146) + 2, 0.75, true)
	var grass := t.hill_near.lerp(t.spike, 0.2)
	SceneProps.put(pen, near, [40, 228, 322], SceneProps.p_tuft, sky, grass, 0)
	var stem := t.hill_near.lerp(t.spike, 0.3)
	SceneProps.put(pen, near, [76, 262], SceneProps.p_flower, sky, DAISY, 0, [stem])
	SceneProps.put(pen, near, [196, 290], SceneProps.p_flower, sky, BUTTERCUP, 0, [stem])


## A windmill: a cream tower with a shaded side, a red cap and four sails.
static func _windmill(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.fill(
		PackedVector2Array([Vector2(-9, 1), Vector2(-6, -40), Vector2(6, -40), Vector2(9, 1)]),
		TOWER
	)
	pen.fill(
		PackedVector2Array([Vector2(0, 1), Vector2(0, -40), Vector2(6, -40), Vector2(9, 1)]),
		TOWER_SHADE
	)
	pen.fill(ScenePath.at(-8.5, -39).q(0, -53, 8.5, -39).done(), ROOF)
	pen.fill(ScenePath.at(-3, 1).v(-7).a(3, false, true, 3, -7).v(1).done(), WOOD)
	pen.circle(Vector2(0, -25), 2.4, WOOD)
	for k in 4:
		pen.push(ScenePen.place(0, -43, 22 + k * 90))
		pen.line(0, 0, 27, 0, WOOD, 1.6)
		pen.rect(7, -6.5, 20, 6, SAIL)
		pen.pop()
	pen.circle(Vector2(0, -43), 2.6, WOOD)
	pen.pop()


static func _barn(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.rect(-14, -18, 28, 19, BARN)
	pen.fill(
		PackedVector2Array(
			[Vector2(-17, -17), Vector2(-9, -29), Vector2(9, -29), Vector2(17, -17)]
		),
		BARN_ROOF
	)
	pen.rect(-5, -11, 10, 12, BARN_TRIM)
	pen.line(-5, -11, 5, 1, BARN, 1.4)
	pen.line(5, -11, -5, 1, BARN, 1.4)
	pen.circle(Vector2(0, -22), 2.6, BARN_TRIM)
	pen.pop()


## A sheep: four puffs of wool, a dark face with an ear, two legs.
static func _sheep(pen: ScenePen, x: float, b: float, s: float, flip: bool) -> void:
	pen.push(ScenePen.place(x, b, 0.0, -s if flip else s, s))
	pen.rect(-6.5, -6, 2.6, 6.5, SHEEP_FACE, 1)
	pen.rect(4, -6, 2.6, 6.5, SHEEP_FACE, 1)
	for d: Vector3 in [
		Vector3(-5, -11.5, 6.5), Vector3(1.5, -14, 7), Vector3(7, -11, 6), Vector3(0, -9, 6.5)
	]:
		pen.circle(Vector2(d.x, d.y), d.z, WOOL)
	pen.ellipse(Vector2(12.5, -13.5), 4.4, 5, SHEEP_FACE)
	pen.ellipse(Vector2(9.5, -17), 2.6, 1.4, SHEEP_FACE, -30)
	pen.circle(Vector2(13.6, -14.5), 1, WOOL)
	pen.pop()
