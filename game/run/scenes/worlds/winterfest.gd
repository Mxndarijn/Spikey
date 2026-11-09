extends RefCounted
## Winter Fest (Worlds v4): snowy hills with pines and a cabin far off, pines
## with fairy lights on a pale drift, and a snowman up front.

# A shade off white, so the snowman, the cabin's roof and the snow caps stand out.
const SNOW := Color("#EAF3FA")
const TRUNK := Color("#6E3A2E")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(504, 22, 1.0, 1.4, t.hill_far, 0)
	var mid := SceneGround.new(556, 14, 1.4, 3.2, SNOW, 1)
	var near := SceneGround.new(600, 10, 1.6, 0.6, t.hill_mid, 2)
	far.paint(pen)
	SceneProps.put(pen, far, [30, 54, 78, 300, 324], SceneProps.p_pine, sky, t.prop)
	var cx := 250.0
	SceneProps.p_cabin(pen, cx, far.y(cx) + 3, 0.95)
	mid.paint(pen)
	for d: Vector2 in [Vector2(52, 1.4), Vector2(100, 1.0)]:
		_lit_pine(pen, mid, d.x, d.y, t.prop)
	near.paint(pen)
	var sx := 196.0
	var sb := near.y(sx) + 2
	SceneProps.shadow(pen, sx, sb, 16, near)
	SceneProps.p_snowman(pen, sx, sb, 0.95)
	# The art has this pine at x 320; its branches then reach behind the right
	# wall spikes, so it stands 9 px inward.
	_lit_pine(pen, near, 311, 1.3, t.prop)


static func _lit_pine(pen: ScenePen, g: SceneGround, x: float, s: float, col: Color) -> void:
	var b := g.y(x) + 2
	SceneProps.shadow(pen, x, b, 14 * s if g.depth == 1 else 16, g)
	SceneProps.p_pine(pen, x, b, s, col, TRUNK)
	SceneProps.p_lights(pen, x, b, s)
