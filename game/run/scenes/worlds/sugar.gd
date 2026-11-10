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
	# Icing over the far hill, dripping down it in scallops: every third drip is
	# long, the one after it short.
	var icing := ScenePath.at(-10, far.y(-10) - 4)
	for x in range(-4, 371, 6):
		icing.l(x, far.y(x) - 4)
	var nth := 0
	for x in range(370, -10, -22):
		var deep := 34.0 if nth % 3 == 1 else (15.0 if nth % 3 == 2 else 22.0)
		icing.q(x - 11, far.y(x - 11) + deep, x - 22, far.y(x - 22) + 5)
		nth += 1
	pen.fill(icing.done(), ICING)
	SceneProps.put(pen, far, [60, 300], SceneProps.p_lolly, sky, LOLLY_PINK, 7)
	SceneProps.put(pen, far, [180], SceneProps.p_lolly, sky, LOLLY_BLUE, 7)
	near.paint(pen)
	var xs := [40, 84, 290, 330]
	for k in xs.size():
		SceneProps.put(pen, near, [xs[k]], SceneProps.p_gumdrop, sky, GUMDROPS[k], 9)
	var b := near.y(220) + 2
	SceneProps.shadow(pen, 220, b, 16, near)
	SceneProps.p_cupcake(pen, 220, b, 1.05)
