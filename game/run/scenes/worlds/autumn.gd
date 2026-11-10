extends WorldScene
## Autumn (Worlds v4): a low sun and a cloud, a pine ridge, orange round trees
## on the middle hill, pumpkins and grass tufts up front.

## Leaves on a Match my world portal's rim.
const RIM_LEAVES: Array[Color] = [Color("E2603A"), Color("F2A23A"), Color("C9452F")]

const PINE_TINT := Color("#7A3A1E")
const LEAVES := Color("#E2603A")
const TRUNK := Color("#6B3A22")


func _init() -> void:
	mote_kind = "leaves"
	mote_count = 12
	mote_band = Vector2(196, 470)


func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(486, 12, 1.2, 0.4, t.hill_far, 0)
	var mid := SceneGround.new(532, 12, 1.5, 2.4, t.hill_mid, 1)
	var near := SceneGround.new(588, 9, 1.1, 4.2, t.hill_near, 2)
	SceneProps.sun(pen, 64, 214, 40, t)
	SceneProps.cloud(pen, 256, 238, 92, t.cloud)
	far.paint(pen)
	var pines: Array = range(8, 362, 22)
	SceneProps.put(pen, far, pines, SceneProps.p_pine, sky, t.prop.lerp(PINE_TINT, 0.3))
	mid.paint(pen)
	# The edge trees stand 8 and 12 px further in (art: 24 and 340) so their
	# dark trunks stay clear of the wall spikes.
	var trees := [32, 68, 112, 250, 296, 328]
	SceneProps.put(pen, mid, trees, SceneProps.p_round, sky, LEAVES, 10, [TRUNK])
	near.paint(pen)
	for d: Vector2 in [Vector2(60, 1.2), Vector2(86, 0.85), Vector2(300, 1.0)]:
		var b := near.y(d.x) + 2
		SceneProps.shadow(pen, d.x, b, 13 * d.y, near)
		SceneProps.p_pumpkin(pen, d.x, b, d.y)
	var grass := t.hill_near.lerp(t.spike, 0.2)
	SceneProps.put(pen, near, [140, 220, 340], SceneProps.p_tuft, sky, grass, 0)


func portal_touch_colors(_t: ThemeDef) -> Array[Color]:
	return RIM_LEAVES


func draw_portal_touch(p: PortalPen, _t: ThemeDef, cols: Array[Color]) -> void:
	PortalPainter.touch_leaves(p, cols)
