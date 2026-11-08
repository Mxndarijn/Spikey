extends RefCounted
## Sugar Rush (Worlds v4): icing dripping from the ceiling, pink clouds, an
## iced far hill with lollipops, gumdrops and a cupcake in front.

const ICING := Color("#FFFFFF")
const CLOUD := Color("#FFE1EE")
const LOLLY_PINK := Color("#FF6FA8")
const LOLLY_BLUE := Color("#7FD3FF")
const GUMDROPS := [Color("#7FD3FF"), Color("#B69CFF"), Color("#FFD23F"), Color("#7FE3B5")]


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(526, 24, 1.3, 0.4, t.hill_far, 1)
	var near := SceneGround.new(584, 12, 1.6, 2.0, t.hill_near, 2)
	# Icing dripping off the ceiling, a long drip every third one.
	var drip := ScenePath.at(0, 0).h(360).v(40)
	for x in range(360, 0, -30):
		var long := floori(x / 30.0) % 3 == 0
		drip.q(x - 10, 40, x - 14, 40 + (24 if long else 10))
		drip.q(x - 20, 40 + (30 if long else 14), x - 26, 40)
	pen.fill(drip.h(0).done(), ICING)
	SceneProps.cloud(pen, 30, 236, 110, CLOUD)
	SceneProps.cloud(pen, 222, 300, 116, CLOUD)
	far.paint(pen)
	# A wavy icing line along the far hill.
	var icing := PackedVector2Array([Vector2(-10, far.y(-10) + 6)])
	for x in range(-4, 371, 9):
		icing.append(Vector2(x, far.y(x) + (11 if posmod(floori(x / 18.0), 2) == 1 else 4)))
	pen.stroke(icing, ICING, 8)
	SceneProps.put(pen, far, [60, 300], SceneProps.p_lolly, sky, LOLLY_PINK, 6)
	SceneProps.put(pen, far, [180], SceneProps.p_lolly, sky, LOLLY_BLUE, 6)
	near.paint(pen)
	var xs := [40, 84, 290, 330]
	for k in xs.size():
		SceneProps.put(pen, near, [xs[k]], SceneProps.p_gumdrop, sky, GUMDROPS[k], 9)
	var b := near.y(220) + 2
	SceneProps.shadow(pen, 220, b, 15, near)
	SceneProps.p_cupcake(pen, 220, b, 1.0)
