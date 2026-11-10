extends RefCounted
## Deep Sea (Worlds v4): wavy light at the surface, light rays, small fish, a
## jellyfish, a sandy floor with corals, sea weed, a starfish, shells and bubbles.

const SAND_FAR := Color("#E9D9A8")
const SAND_NEAR := Color("#D9C38C")
const LIGHT := Color("#FFFFFF")
const RAY := Color(1, 1, 1, 0.08)
const BUBBLE := Color(1, 1, 1, 0.6)
const JELLY := Color("#FFB3E6")
const JELLY_BELL := Color("#FFB3E6BF")
const CORAL_FAR := Color("#FF9AA2")
const CORAL := Color("#FF7A8A")
const STARFISH := Color("#FFB347")
const SHELL := Color("#FFC9D6")
const SHELL_PALE := Color("#FFDDE5")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(562, 8, 1.3, 0.8, SAND_FAR, 1)
	var near := SceneGround.new(600, 6, 1.6, 2.4, SAND_NEAR, 2)
	# Wavy light under the surface: (y, opacity).
	for w: Vector2 in [Vector2(30, 0.35), Vector2(62, 0.22)]:
		var p := ScenePath.at(0, w.x)
		for x in range(0, 360, 30):
			p.q(x + 15, w.x + (8 if floori(x / 30.0) % 2 == 1 else -8), x + 30, w.x)
		pen.fill(p.v(0).h(0).done(), Color(LIGHT, w.y))
	# Light rays: (x, width).
	for r: Vector2 in [Vector2(40, 40), Vector2(150, 26), Vector2(250, 50)]:
		pen.fill(ScenePath.at(r.x, 0).h(r.x + r.y).l(r.x + r.y + 70, 540).h(r.x + 40).done(), RAY)
	# Fish: (x, y, size), facing left when the size is negative.
	for f: Vector3 in [Vector3(80, 210, 1.0), Vector3(100, 228, 0.6), Vector3(290, 380, -0.8)]:
		pen.push(ScenePen.place(f.x, f.y, 0, f.z, absf(f.z)))
		pen.ellipse(Vector2.ZERO, 14, 7, t.hill_near)
		pen.fill(
			PackedVector2Array([Vector2(-12, 0), Vector2(-22, -7), Vector2(-22, 7)]), t.hill_near
		)
		pen.circle(Vector2(7, -2), 1.6, LIGHT)
		pen.pop()
	_jelly(pen, 64, 284)
	far.paint(pen)
	SceneProps.put(pen, far, [120, 150, 214], SceneProps.p_weed, sky, t.prop, 0)
	SceneProps.put(pen, far, [250], SceneProps.p_coral, sky, CORAL_FAR, 8)
	near.paint(pen)
	SceneProps.put(pen, near, [40, 300], SceneProps.p_coral, sky, CORAL, 12)
	# Lighter than the art's weed colour so the floor and wall spikes stay readable.
	var weed := t.prop.lerp(t.hill_near, 0.65)
	SceneProps.put(pen, near, [70, 86, 330, 346], SceneProps.p_weed, sky, weed, 0)
	SceneProps.put(pen, near, [180], SceneProps.p_starfish, sky, STARFISH, 8)
	# One scallop big enough to read, and a small pale one.
	SceneProps.put(pen, near, [236], SceneProps.p_shell, sky, SHELL, 13)
	SceneProps.shadow(pen, 131, near.y(131) + 2, 8, near)
	SceneProps.p_shell(pen, 131, near.y(131) + 2, 0.7, SHELL_PALE)
	# Bubbles: (x, y, r).
	for b: Vector3 in [
		Vector3(80, 500, 4),
		Vector3(76, 460, 5),
		Vector3(84, 414, 3.5),
		Vector3(330, 480, 5),
		Vector3(326, 432, 3.5),
	]:
		pen.ring(Vector2(b.x, b.y), b.z, BUBBLE, 2)


## A jellyfish: a see-through bell with a wavy rim and three tentacles.
static func _jelly(pen: ScenePen, x: float, y: float) -> void:
	pen.push(ScenePen.place(x, y))
	var bell := ScenePen.ellipse_points(Vector2.ZERO, 18, 16, 0, PI, TAU)
	var rim := ScenePath.at(18, 0).q(12, 4, 6, 0).q(0, 4, -6, 0).q(-12, 4, -18, 0).done()
	bell.append_array(rim.slice(1))
	pen.fill(bell, JELLY_BELL)
	pen.stroke(ScenePath.at(-10, 2).q(-14, 16, -8, 30).done(), JELLY, 2.5)
	pen.stroke(ScenePath.at(0, 3).q(4, 18, -2, 34).done(), JELLY, 2.5)
	pen.stroke(ScenePath.at(10, 2).q(14, 16, 8, 28).done(), JELLY, 2.5)
	pen.pop()
