extends RefCounted
## Palm Cove: a beach day. Flat sea to the horizon with an island and a
## sailboat, two palms on the sand, a beach umbrella, a sandcastle, a starfish
## and shells up front.

const BIRD := Color("#4E8FA8")
const ISLAND := Color("#62C29A")
const FOAM := Color("#FFFFFF")
const TRUNK := Color("#B7814F")
const TRUNK_RING := Color("#9A6A3E")
const FROND := Color("#2F9E62")
const FROND_DARK := Color("#278753")
const FROND_LIGHT := Color("#45B57A")
const COCONUT := Color("#8A5A44")
const COCONUT_DARK := Color("#754A38")
const SAIL := Color("#FFFFFF")
const JIB := Color("#FFE3C8")
const HULL := Color("#E2574C")
const HULL_TRIM := Color("#FFF4E2")
const MAST := Color("#8A5A44")
const UMBRELLA := Color("#FF7A5C")
const UMBRELLA_STRIPE := Color("#FFFFFF")
const CASTLE := Color("#D6B26C")
const CASTLE_TOWER := Color("#C9A45C")
const CASTLE_DOOR := Color("#A9844A")
const STARFISH := Color("#FF9A6B")
const SHELL := Color("#FFC9D6")
const SHELL_WHITE := Color("#FFFFFF")
## Where the sea meets the sky.
const HORIZON := 484.0


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var mid := SceneGround.new(552, 9, 1.2, 1.0, t.hill_mid, 1)
	var near := SceneGround.new(598, 6, 1.4, 3.0, t.hill_near, 2)
	SceneProps.sky_sun(pen, 74, 228, 26, t)
	SceneProps.cloud(pen, 222, 256, 92, t.cloud)
	SceneProps.birds(pen, [Vector2(280, 300), Vector2(298, 310)], BIRD)
	pen.fill(ScenePath.at(36, HORIZON + 2).q(92, 430, 158, HORIZON + 2).done(), ISLAND)
	_palm(pen, 84, 462, 0.5, false)
	_palm(pen, 108, 468, 0.42, true)
	pen.rect(0, HORIZON, 360, 640 - HORIZON, t.hill_far)
	# Short lines of light on the water: (x, y, length).
	for d: Vector3 in [
		Vector3(40, 498, 34),
		Vector3(130, 508, 26),
		Vector3(214, 496, 30),
		Vector3(290, 512, 34),
		Vector3(80, 524, 28),
		Vector3(236, 528, 30),
	]:
		pen.line(d.x, d.y, d.x + d.z, d.y, sky, 2.4)
	_boat(pen, 252, 490, 0.85)
	pen.stroke(mid.surface(-10, 370, 6, 1), FOAM, 5)
	mid.paint(pen)
	SceneProps.shadow(pen, 56, mid.y(56) + 2, 14, mid)
	_palm(pen, 56, mid.y(56) + 2, 1.5, false)
	SceneProps.shadow(pen, 308, mid.y(308) + 2, 11, mid)
	_palm(pen, 308, mid.y(308) + 2, 1.15, true)
	near.paint(pen)
	SceneProps.shadow(pen, 206, near.y(206) + 2, 15, near)
	_umbrella(pen, 206, near.y(206) + 2, 1.0)
	SceneProps.shadow(pen, 126, near.y(126) + 2, 16, near)
	_sandcastle(pen, 126, near.y(126) + 2, 1.0)
	SceneProps.p_starfish(pen, 268, near.y(268) + 3, 1.0, STARFISH)
	SceneProps.p_shell(pen, 170, near.y(170) + 2, 0.7, SHELL)
	SceneProps.p_shell(pen, 300, near.y(300) + 2, 0.55, SHELL_WHITE)


## A palm: a curved trunk with rings, six fronds and two coconuts.
static func _palm(pen: ScenePen, x: float, b: float, s: float, flip: bool) -> void:
	pen.push(ScenePen.place(x, b, 0.0, -s if flip else s, s))
	pen.stroke(ScenePath.at(0, 1).q(7, -28, -2, -54).done(), TRUNK, 5)
	for d: Vector2 in [Vector2(-1, -12), Vector2(0, -24), Vector2(-1, -36), Vector2(-3, -46)]:
		pen.line(d.x, d.y, d.x + 5, d.y, TRUNK_RING, 1.3)
	# Fronds: (turn, length, shade 0 to 2).
	for d: Vector3 in [
		Vector3(-150, 25, 0),
		Vector3(205, 22, 1),
		Vector3(-35, 27, 0),
		Vector3(10, 23, 1),
		Vector3(-100, 24, 2),
		Vector3(-70, 24, 2),
	]:
		var l := d.y
		pen.push(ScenePen.place(-2, -55, d.x))
		var p := ScenePath.at(0, 0).q(l * 0.5, -l * 0.5, l, l * 0.16)
		pen.fill(p.q(l * 0.5, -l * 0.14, 0, 0).done(), [FROND, FROND_DARK, FROND_LIGHT][int(d.z)])
		pen.pop()
	pen.circle(Vector2(-4, -52), 2.6, COCONUT)
	pen.circle(Vector2(0.6, -51.4), 2.4, COCONUT_DARK)
	pen.pop()


## A sailboat sitting on the water line at y.
static func _boat(pen: ScenePen, x: float, y: float, s: float) -> void:
	pen.push(ScenePen.place(x, y, 0.0, s, s))
	pen.line(0, -6, 0, -38, MAST, 1.6)
	pen.fill(PackedVector2Array([Vector2(1.5, -36), Vector2(1.5, -9), Vector2(18, -9)]), SAIL)
	pen.fill(PackedVector2Array([Vector2(-1.5, -30), Vector2(-1.5, -9), Vector2(-13, -9)]), JIB)
	pen.fill(
		PackedVector2Array([Vector2(-16, -6), Vector2(16, -6), Vector2(11, 2), Vector2(-11, 2)]),
		HULL
	)
	pen.rect(-16, -7, 32, 2.4, HULL_TRIM, 1)
	pen.pop()


## A beach umbrella, leaning a little: a striped half dome on a white pole.
static func _umbrella(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, -10, s, s))
	pen.line(0, 1, 0, -34, UMBRELLA_STRIPE, 2)
	pen.fill(ScenePen.ellipse_points(Vector2(0, -32), 22, 20, 0, PI, TAU), UMBRELLA)
	pen.fill(ScenePen.ellipse_points(Vector2(0, -32), 11, 20, 0, PI, TAU), UMBRELLA_STRIPE)
	pen.circle(Vector2(0, -52.5), 1.8, UMBRELLA_STRIPE)
	pen.pop()


static func _sandcastle(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.rect(-13, -10, 26, 11, CASTLE)
	pen.rect(-16, -17, 9, 18, CASTLE_TOWER)
	pen.rect(7, -17, 9, 18, CASTLE_TOWER)
	pen.rect(-5, -21, 10, 12, CASTLE)
	for mx: float in [-16.0, -10.0, 7.0, 13.0]:
		pen.rect(mx, -20, 3, 3.5, CASTLE_TOWER)
	pen.fill(ScenePath.at(-2.5, 1).v(-5).a(2.5, false, true, 2.5, -5).v(1).done(), CASTLE_DOOR)
	pen.line(0, -21, 0, -31, MAST, 1.1)
	pen.fill(PackedVector2Array([Vector2(0, -31), Vector2(7, -28.5), Vector2(0, -26)]), UMBRELLA)
	pen.pop()
