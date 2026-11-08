extends RefCounted
## Lava Forge (Worlds v4): a wide volcano with a glowing crater, a smoke plume
## and lava running down its slopes, rock hills in front and a lava lake with
## stepping stones at the bottom.

const ROCK := Color("#7A2E2C")
const CRATER_ROCK := Color("#5A2024")
# The art's middle hill is #5A2024; it runs behind the lowest wall spikes, so it
# is a lighter warm rock here (3:1 against the spike).
const MID_ROCK := Color("#A84A3E")
const ROCK_DARK := Color("#3A1418")
const ROCK_HI := Color("#B04A40")
const STONE_HI := Color("#6A2A2E")
const MOLTEN := Color("#FFD27A")
const MOLTEN_DEEP := Color("#FFA94D")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	# Smoke plume from the crater, drifting right, below the score.
	for c: Vector3 in [
		Vector3(206, 300, 20),
		Vector3(226, 284, 24),
		Vector3(252, 270, 22),
		Vector3(280, 262, 18),
		Vector3(300, 252, 14),
	]:
		pen.circle(Vector2(c.x, c.y), c.z, t.cloud)
	_volcano(pen)
	# Dark rock hill in front, with two boulders.
	var mid := SceneGround.new(556, 12, 1.4, 0.4, MID_ROCK, 1)
	mid.paint(pen)
	SceneProps.put(pen, mid, [42, 316], SceneProps.p_rock, sky, ROCK_DARK, 12, [ROCK_HI])
	_lake(pen)


static func _volcano(pen: ScenePen) -> void:
	# The cone's feet end under the middle hill, just inside the walls (the art
	# runs them off screen, behind the lowest wall spikes).
	var cone := ScenePath.at(30.5, 600).v(550).q(75, 500, 120, 420).l(160, 330)
	cone.q(180, 316, 200, 330).l(240, 420).q(285, 500, 329.5, 550).v(600)
	pen.fill(cone.done(), ROCK)
	var lip := ScenePath.at(160, 330).q(180, 316, 200, 330).q(190, 340, 180, 340)
	lip.q(170, 340, 160, 330)
	pen.fill(lip.done(), MOLTEN)
	var notch := ScenePath.at(150, 352).l(160, 330).q(170, 344, 180, 342).l(172, 364)
	pen.fill(notch.done(), CRATER_ROCK)
	# Lava running down the slopes.
	var left := ScenePath.at(168, 338).q(150, 380, 140, 420).q(128, 470, 96, 520).done()
	pen.stroke(left, MOLTEN_DEEP, 9)
	pen.stroke(left, MOLTEN, 4)
	var right := ScenePath.at(192, 338).q(206, 390, 222, 430).q(240, 480, 272, 520).done()
	pen.stroke(right, MOLTEN_DEEP, 7)
	pen.stroke(right, MOLTEN, 3)
	# Blobs thrown up from the crater.
	for c: Vector3 in [
		Vector3(170, 304, 4), Vector3(188, 296, 5), Vector3(204, 310, 3.5), Vector3(156, 318, 3)
	]:
		pen.circle(Vector2(c.x, c.y), c.z, MOLTEN)


static func _lake(pen: ScenePen) -> void:
	var lake := ScenePath.at(0, 586).q(90, 576, 180, 586).q(270, 596, 360, 584).v(640).h(0)
	pen.fill(lake.done(), MOLTEN_DEEP)
	for y: float in [600.0, 616.0]:
		var wave := ScenePath.at(0, y)
		for x in range(0, 360, 30):
			wave.q(x + 15, y - 3 if x % 60 >= 30 else y + 3, x + 30, y)
		pen.stroke(wave.done(), MOLTEN, 3, false)
	for d: Vector2 in [Vector2(70, 30), Vector2(150, 24), Vector2(226, 32), Vector2(300, 26)]:
		pen.ellipse(Vector2(d.x, 598), d.y / 2.0, 7, ROCK_DARK)
		pen.ellipse(Vector2(d.x - 3, 595), d.y / 4.0, 2.5, STONE_HI)
