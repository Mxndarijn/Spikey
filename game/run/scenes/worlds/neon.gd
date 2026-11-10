extends WorldScene
## Neon City (Worlds v4): stars and a crescent moon over two layers of lit
## towers with neon signs, an elevated train, and a wet street with lamps.

## Neon's spikes are hot pink, so a Match my world portal's rim glows cyan.
const NEON_RING := Color("4FE3FF")

const MOON := Color("#E9E1FF")
const FAR_TOWER := Color("#2E1466")
const FAR_WINDOW := Color("#5B3AA6")
const MID_TOWER := Color("#22104F")
const CYAN := Color("#7DE2FF")
const GOLD := Color("#FFD27A")
const YELLOW := Color("#FFD23F")
const BEACON := Color("#FF5A5A")
# The art's pink is the spike colour #FF4FD8; one step off it.
const PINK := Color("#FF5CDA")
const TRACK := Color("#120838")
const CAR := Color("#3A1A70")
const STREET := Color("#170838")


func paint(pen: ScenePen, _t: ThemeDef) -> void:
	_stars(pen, 4, 22, 220, Vector3(180, 136, 110))
	pen.circle(Vector2(300, 230), 22, MOON)
	pen.circle(Vector2(309, 224), 19, pen.sky_at(224))
	_layer(pen, 430, FAR_TOWER, [FAR_WINDOW], 101, Vector4(70, 150, 22, 40))
	_layer(pen, 470, MID_TOWER, [CYAN, GOLD, FAR_WINDOW], 202, Vector4(50, 120, 28, 48))
	_signs(pen)
	_train(pen)
	_street(pen)


## A row of towers from wall to wall on `base`; size is (min h, max h, min w, max w).
## Windows and beacons stay out from behind the wall spikes.
static func _layer(
	pen: ScenePen, base: int, col: Color, win: Array[Color], seed_value: int, size: Vector4
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x := -6
	while x < 366:
		var w := rng.randi_range(int(size.z), int(size.w))
		var h := rng.randi_range(int(size.x), int(size.y))
		pen.rect(x, base - h, w, h + 200, col)
		if rng.randf() < 0.4:
			var ax := x + w / 2.0
			pen.line(ax, base - h, ax, base - h - 14, col, 2)
			if _clear(ax - 1.8, ax + 1.8):
				pen.circle(Vector2(ax, base - h - 15), 1.8, BEACON)
		for wy in range(base - h + 10, base - 4, 12):
			for wx in range(x + 5, x + w - 6, 9):
				if rng.randf() < 0.38:
					var c: Color = win[rng.randi() % win.size()]
					if _clear(wx, wx + 4):
						pen.rect(wx, wy, 4, 5, c, 1)
		x += w + rng.randi_range(0, 3)


## True when x0..x1 is between the wall spike strips.
static func _clear(x0: float, x1: float) -> bool:
	return x0 >= 30 and x1 <= 330


static func _signs(pen: ScenePen) -> void:
	# Heart: the art has it at x 30, behind the left wall spikes; 10 px inward.
	var x := 40.0
	var y := 400.0
	var heart := ScenePath.at(x, y + 6).q(x - 10, y - 2, x - 6, y - 8).q(x - 2, y - 13, x, y - 8)
	heart.q(x + 2, y - 13, x + 6, y - 8).q(x + 10, y - 2, x, y + 6)
	pen.stroke(heart.done(), PINK, 2.6)
	x = 300.0
	y = 392.0
	var bolt := PackedVector2Array(
		[
			Vector2(x + 4, y - 10),
			Vector2(x - 4, y + 2),
			Vector2(x + 2, y + 2),
			Vector2(x - 2, y + 12),
			Vector2(x + 8, y - 2),
			Vector2(x + 2, y - 2),
			Vector2(x + 4, y - 10),
		]
	)
	pen.stroke(bolt, YELLOW, 2.4)
	x = 250.0
	y = 420.0
	var box := ScenePen.rect_points(x, y, 26, 12, 3)
	box.append(box[0])
	pen.stroke(box, CYAN, 2.4, false)
	pen.line(x + 6, y + 6, x + 20, y + 6, CYAN, 2)


## The elevated track, its pillars and a three-car train.
static func _train(pen: ScenePen) -> void:
	pen.rect(0, 482, 360, 6, TRACK)
	for x in range(20, 360, 60):
		pen.rect(x, 488, 6, 40, TRACK)
	for k in 3:
		var x := 150 + k * 46
		pen.rect(x, 458, 42, 22, CAR, 8 if k == 0 else 4)
		for wx in range(x + 6, x + 38, 9):
			pen.rect(wx, 463, 6, 7, GOLD, 1.5)
		pen.rect(x, 474, 42, 3, PINK)


static func _street(pen: ScenePen) -> void:
	pen.rect(0, 528, 360, 112, STREET)
	# Puddle glints; the art has them at y 604 / 612, 10 px higher here so they
	# stay off the floor spikes.
	for d: Vector3 in [
		Vector3(30, 26, 0), Vector3(110, 18, 1), Vector3(204, 30, 2), Vector3(296, 22, 0)
	]:
		var c: Color = [PINK, CYAN, GOLD][int(d.z)]
		pen.rect(d.x, 594, d.y, 3, Color(c, 0.55), 1.5)
		pen.rect(d.x + 4, 602, d.y - 8, 3, Color(c, 0.35), 1.5)
	for x: float in [60.0, 300.0]:
		SceneProps.p_lamp(pen, x, 529, 0.9, CAR, CYAN)


## Like SceneProps.stars, but none behind the wall spikes (bright on dark).
static func _stars(pen: ScenePen, seed_value: int, n: int, y1: float, avoid: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var p := Vector2(rng.randf_range(10, 350), rng.randf_range(40, y1))
		var r: float = [1.0, 1.3, 1.7][rng.randi() % 3]
		var a := rng.randf_range(0.35, 0.85)
		if p.distance_to(Vector2(avoid.x, avoid.y)) < avoid.z:
			continue
		if p.y + r > 62 and (p.x - r < 30 or p.x + r > 330):
			continue
		pen.circle(p, r, Color(1, 1, 1, a))


func portal_touch_colors(_t: ThemeDef) -> Array[Color]:
	return [NEON_RING]


func draw_portal_touch(p: PortalPen, _t: ThemeDef, cols: Array[Color]) -> void:
	PortalPainter.touch_glow_ring(p, cols)
