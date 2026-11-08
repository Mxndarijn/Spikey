extends RefCounted
## Haunted Moon (Worlds v4): a crescent moon, stars and bats, a haunted house
## on the far hill crest, bare trees, a ghost, graves in the fog and a lit
## pumpkin up front.

const GRAVE := Color("#4A3A7A")
const WINDOW := Color("#FFD27A")
const GHOST := Color(1, 1, 1, 0.72)
const FOG := Color(1, 1, 1, 0.11)

# The art has the moon at (66, 214); its bright edge then sits behind the wall
# spikes, so moon and cut-out move 10 px inward (and 18 px down, off the score).
const MOON := Vector2(76, 232)
const CUT := Vector2(96, 220)


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(512, 28, 0.9, 2.6, t.hill_far, 0)
	var mid := SceneGround.new(566, 12, 1.4, 0.4, t.hill_mid, 1)
	var near := SceneGround.new(606, 6, 1.2, 2.0, t.hill_near, 2)
	_stars(pen, 13, 22, 360, Vector3(96, 160, 90))
	SceneProps.sun(pen, MOON.x, MOON.y, 46, t)
	# The crescent's cut-out is drawn in the ring colour, as in the art.
	pen.circle(CUT, 40, t.sun_ring)
	# Bats; the art's first bat (220, 130) sat on the score, so it is lower.
	for d: Vector3 in [Vector3(224, 206, 1.0), Vector3(260, 170, 0.7), Vector3(300, 120, 0.8)]:
		_bat(pen, d.x, d.y, d.z, t.prop)
	far.paint(pen)
	var crest := 160
	for x in range(160, 340, 2):
		if far.y(x) < far.y(crest):
			crest = x
	# The crest is at x 334; the house stops short of the wall so its lit
	# windows stay out from behind the wall spikes.
	crest = mini(crest, 317)
	SceneProps.p_house(pen, crest, far.y(crest) + 3, 0.9, t.prop, WINDOW)
	SceneProps.put(pen, far, [40, 70], SceneProps.p_bare, sky, t.prop)
	_ghost(pen, 64, 300, t.sky_mid)
	mid.paint(pen)
	for x: float in [40.0, 76.0, 110.0, 146.0]:
		var b := mid.y(x) + 3
		SceneProps.shadow(pen, x, b, 8 * mid.scale(), mid)
		SceneProps.p_grave(pen, x, b, mid.scale(), GRAVE, mid.slope(x) * 0.6)
	SceneProps.put(pen, mid, [312], SceneProps.p_bare, sky, t.prop)
	for f: Vector3 in [Vector3(520, 220, 20), Vector3(548, 160, 170), Vector3(580, 260, 60)]:
		pen.rect(f.z, f.x, f.y, 13, FOG, 6.5)
	near.paint(pen)
	var px := 204.0
	# Sunk 2 px it would dip into the floor spikes; it sits on the surface.
	var pb := minf(near.y(px) + 2, 605.0)
	SceneProps.shadow(pen, px, pb, 14, near)
	SceneProps.p_pumpkin(pen, px, pb, 1.15, true)


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


## A bat at (x, y), two wings meeting at the body, scaled by s.
static func _bat(pen: ScenePen, x: float, y: float, s: float, col: Color) -> void:
	for d: float in [-1.0, 1.0]:
		var p := ScenePath.at(x, y).q(x + d * 6 * s, y - 6 * s, x + d * 14 * s, y - 2 * s)
		p.q(x + d * 10 * s, y + 2 * s, x + d * 8 * s, y + 6 * s)
		p.q(x + d * 6 * s, y + 2 * s, x, y)
		pen.fill(p.done(), col)


static func _ghost(pen: ScenePen, x: float, y: float, eye: Color) -> void:
	var p := ScenePath.at(x - 12, y + 14).v(y - 2).a(12, false, true, x + 12, y - 2).v(y + 14)
	p.l(x + 8, y + 10).l(x + 4, y + 14).l(x, y + 10).l(x - 4, y + 14).l(x - 8, y + 10)
	pen.fill(p.done(), GHOST)
	pen.circle(Vector2(x - 4, y), 2, eye)
	pen.circle(Vector2(x + 4, y), 2, eye)
