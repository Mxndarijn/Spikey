extends RefCounted
## Any world without its own scene (a new paid or seasonal world): its own sun,
## two clouds and three rolling hills with round trees, all from its tokens.


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(478, 16, 1.1, 0.6, t.hill_far, 0)
	var mid := SceneGround.new(528, 14, 1.4, 2.2, t.hill_mid, 1)
	var near := SceneGround.new(584, 10, 1.0, 4.0, t.hill_near, 2)
	SceneProps.sun(pen, 284, 256, 40, t)
	if not t.night:
		SceneProps.cloud(pen, 18, 250, 100, t.cloud)
		SceneProps.cloud(pen, 236, 330, 96, t.cloud)
	far.paint(pen)
	SceneProps.put(pen, far, [28, 46, 64, 250, 268, 320], SceneProps.p_round, sky, t.prop)
	mid.paint(pen)
	SceneProps.put(pen, mid, [48, 300], SceneProps.p_round, sky, t.prop)
	near.paint(pen)
