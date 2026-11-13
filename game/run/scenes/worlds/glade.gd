extends WorldScene
## Mushroom Glade: a night forest lit by its own mushrooms. Tall trunks, vines
## with glowing blossoms hanging from the ceiling, fireflies down both sides,
## big mushrooms and ferns on three dark hills.

const TRUNK := Color("#17424D")
const VINE := Color("#2C6E62")
## Where the vines' leaves and blossoms are measured from (just under the spikes).
const VINE_TOP := 30.0
const BLOSSOM_PINK := Color("#FF7EB6")
const BLOSSOM_GOLD := Color("#FFC27A")
const BLOSSOM_SHINE := Color(1, 1, 1, 0.7)
const FIREFLY := Color("#FFF2A8")
const FIREFLY_HALO := Color("#FFF2A8", 0.22)
const STEM := Color("#E9DCC8")
const CAP_RED := Color("#E8605A")
const CAP_RED_FAR := Color("#C7566A")
const CAP_VIOLET := Color("#A57BFF")
const CAP_VIOLET_FAR := Color("#8E6AD8")
const CAP_TEAL := Color("#5FD9C4")
const SPOT_CREAM := Color("#FFE9D6")
const SPOT_LILAC := Color("#EBDDFF")
const SPOT_MINT := Color("#E4FFF8")
const FERN := Color("#1F5F5A")
const FERN_NEAR := Color("#1A504E")
const DARK := Color("#000000")
const LCG_MUL := 16807
const LCG_MOD := 2147483647


func paint(pen: ScenePen, t: ThemeDef) -> void:
	var sky := t.sky_mid
	var far := SceneGround.new(522, 14, 1.0, 1.2, t.hill_far, 0)
	var mid := SceneGround.new(564, 11, 1.4, 3.0, t.hill_mid, 1)
	# Lower than the other worlds' front hill would put the pale stems behind
	# the floor spikes.
	var near := SceneGround.new(596, 6, 1.2, 0.6, t.hill_near, 2)
	SceneProps.night_stars(pen, 11, 26, 200)
	# Tree trunks, a little wider at the foot: (x, width).
	for d: Vector2 in [Vector2(44, 15), Vector2(92, 9), Vector2(276, 10), Vector2(306, 18)]:
		pen.fill(
			PackedVector2Array(
				[
					Vector2(d.x, 0),
					Vector2(d.x + d.y, 0),
					Vector2(d.x + d.y + 4, 640),
					Vector2(d.x - 4, 640)
				]
			),
			TRUNK
		)
	_vine(pen, 66, 96, BLOSSOM_PINK)
	_vine(pen, 292, 128, BLOSSOM_GOLD)
	_vine(pen, 248, 52, BLOSSOM_PINK)
	_fireflies(pen)
	far.paint(pen)
	# Far mushrooms fade toward the sky: (x, 0 red or 1 violet).
	for d: Vector2 in [Vector2(120, 0), Vector2(196, 1), Vector2(238, 0)]:
		var cap := (CAP_VIOLET_FAR if d.y > 0 else CAP_RED_FAR).lerp(sky, 0.35)
		_mushroom(
			pen, d.x, far.y(d.x) + 2, 0.5, cap, SPOT_CREAM.lerp(sky, 0.35), STEM.lerp(sky, 0.45)
		)
	mid.paint(pen)
	SceneProps.shadow(pen, 72, mid.y(72) + 2, 14, mid)
	_mushroom(pen, 72, mid.y(72) + 2, 1.6, CAP_RED, SPOT_CREAM, STEM)
	SceneProps.shadow(pen, 296, mid.y(296) + 2, 11, mid)
	_mushroom(pen, 296, mid.y(296) + 2, 1.25, CAP_VIOLET, SPOT_LILAC, STEM)
	_fern(pen, 128, mid.y(128) + 2, 0.9, FERN)
	_fern(pen, 246, mid.y(246) + 2, 0.75, FERN)
	near.paint(pen)
	# Small mushrooms: (x, size, 0 teal or 1 red).
	for d: Vector3 in [Vector3(160, 0.62, 0), Vector3(182, 0.42, 0), Vector3(228, 0.5, 1)]:
		var red := d.z > 0
		_mushroom(
			pen,
			d.x,
			minf(near.y(d.x) + 2, 604.0),
			d.y,
			CAP_RED if red else CAP_TEAL,
			SPOT_CREAM if red else SPOT_MINT,
			STEM
		)
	for x: float in [108.0, 330.0, 36.0]:
		_fern(pen, x, near.y(x) + 2, 0.8 if x > 40 else 0.7, FERN_NEAR)


## A vine hanging from the ceiling, `length` long, with three leaves and a
## glowing blossom at its end.
static func _vine(pen: ScenePen, x: float, length: float, blossom: Color) -> void:
	# From the top of the room, behind the ceiling band, so it meets the band
	# between the spikes; `length` is measured from VINE_TOP as before.
	var end := VINE_TOP + length
	pen.stroke(ScenePath.at(x, 0).q(x + 12, end / 2.0, x, end).done(), VINE, 3)
	for k in range(1, 4):
		pen.ellipse(Vector2(x + 7, VINE_TOP + k * length / 4.0), 5, 2.6, VINE, 40)
	pen.circle(Vector2(x, end + 4), 5, blossom)
	pen.circle(Vector2(x - 1.4, end + 2.6), 1.5, BLOSSOM_SHINE)


## Sixteen fireflies down both sides, clear of the walls and the middle.
static func _fireflies(pen: ScenePen) -> void:
	var state := 5
	var rolls := PackedFloat32Array()
	for i in 48:
		state = state * LCG_MUL % LCG_MOD
		rolls.append(float(state) / LCG_MOD)
	for i in 16:
		var x := (38.0 if i % 2 == 1 else 252.0) + rolls[i * 3] * 70.0
		var p := Vector2(x, 250.0 + rolls[i * 3 + 1] * 220.0)
		var big := rolls[i * 3 + 2] > 0.5
		pen.circle(p, 4.5 if big else 3.0, FIREFLY_HALO)
		pen.circle(p, 1.9 if big else 1.3, FIREFLY)


## A mushroom: a stem with a shaded side, a spotted cap over its dark underside.
static func _mushroom(
	pen: ScenePen, x: float, b: float, s: float, cap: Color, spot: Color, stem: Color
) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.fill(ScenePath.at(-5.5, 1).q(-3, -16, -4.5, -30).l(4.5, -30).q(3, -16, 6.5, 1).done(), stem)
	pen.fill(
		ScenePath.at(1, 1).q(2, -16, 1, -30).l(4.5, -30).q(3, -16, 6.5, 1).done(),
		stem.lerp(DARK, 0.14)
	)
	pen.ellipse(Vector2(0, -29), 24, 5.5, cap.lerp(DARK, 0.28))
	var dome := ScenePath.at(-24, -29).q(-23, -54, 0, -54).q(23, -54, 24, -29)
	pen.fill(dome.q(0, -35, -24, -29).done(), cap)
	for d: Vector3 in [
		Vector3(-10, -41, 4), Vector3(5, -47, 3), Vector3(13, -38, 3.4), Vector3(-1, -37, 2.2)
	]:
		pen.circle(Vector2(d.x, d.y), d.z, spot)
	pen.pop()


## A fern: five pointed fronds fanning out from one root.
static func _fern(pen: ScenePen, x: float, b: float, s: float, col: Color) -> void:
	for d: Vector2 in [
		Vector2(-58, 20), Vector2(-24, 26), Vector2(8, 27), Vector2(38, 22), Vector2(64, 16)
	]:
		var l := d.y
		pen.push(ScenePen.place(x, b, d.x, s, s))
		var p := ScenePath.at(0, 0).q(-l * 0.18, -l * 0.6, 0, -l)
		pen.fill(p.q(l * 0.3, -l * 0.5, 0, 0).done(), col)
		pen.pop()


func portal_touch_colors(t: ThemeDef) -> Array[Color]:
	return [t.particle]


func draw_portal_touch(p: PortalPen, _t: ThemeDef, cols: Array[Color]) -> void:
	PortalPainter.touch_sparks(p, cols)
