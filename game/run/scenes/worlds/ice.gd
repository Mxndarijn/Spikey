extends WorldScene
## Ice Cavern (Worlds v4): pale ice walls, icicles (short near the score),
## snowy pines on a far drift, two crystals and a penguin with its chick in front.


func _init() -> void:
	mote_kind = "snow"
	mote_count = 12
	mote_band = Vector2(200, 470)


func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(552, 6, 1.0, 0.3, t.hill_mid, 1)
	var near := SceneGround.new(596, 7, 1.4, 2.0, t.hill_near, 2)
	# Cave walls.
	var wall := Color(t.hill_far, 0.55)
	pen.fill(ScenePath.at(0, 0).h(70).q(40, 200, 54, 640).h(0).done(), wall)
	pen.fill(ScenePath.at(360, 0).h(290).q(326, 220, 300, 640).h(360).done(), wall)
	# Icicles: (x, length, half width).
	for d: Vector3 in [
		Vector3(40, 70, 9),
		Vector3(76, 104, 11),
		Vector3(112, 46, 8),
		Vector3(150, 30, 7),
		Vector3(190, 36, 7),
		Vector3(232, 30, 7),
		Vector3(268, 108, 12),
		Vector3(314, 70, 9),
	]:
		var p := ScenePath.at(d.x - d.z, 26).q(d.x - d.z * 0.4, 26 + d.y * 0.7, d.x, 26 + d.y)
		p.q(d.x + d.z * 0.4, 26 + d.y * 0.7, d.x + d.z, 26)
		pen.fill(p.done(), t.cloud)
	far.paint(pen)
	var pines := [100, 124, 214, 236, 262]
	SceneProps.put(pen, far, pines, SceneProps.p_pine, sky, t.prop, 8)
	for x: int in pines:
		SceneProps.p_snowcap(pen, x, far.y(x) + 2, far.scale())
	near.paint(pen)
	# Crystals: (x, size).
	for d: Vector2 in [Vector2(58, 1.2), Vector2(300, 1.4)]:
		var b := near.y(d.x) + 2
		SceneProps.shadow(pen, d.x, b, 20 * d.y, near)
		SceneProps.p_crystal(pen, d.x, b, d.y, t.hill_far, t.prop)
	# A penguin and its chick, facing each other.
	var pb := near.y(150) + 2
	SceneProps.shadow(pen, 150, pb, 10, near)
	SceneProps.p_penguin(pen, 150, pb, 0.92)
	pb = near.y(181) + 2
	SceneProps.shadow(pen, 181, pb, 6, near)
	SceneProps.p_penguin(pen, 181, pb, 0.56, true, true)


func portal_touch_colors(_t: ThemeDef) -> Array[Color]:
	return [Color.WHITE]


func draw_portal_touch(p: PortalPen, _t: ThemeDef, cols: Array[Color]) -> void:
	PortalPainter.touch_shards(p, cols)
