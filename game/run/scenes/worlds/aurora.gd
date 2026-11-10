extends WorldScene
## Aurora Bay: polar night. Three ribbons of light across the sky, snow peaks,
## pines and an igloo with a lit door on the middle drift, a polar bear with
## her cub and snow mounds up front.

# Faint enough that the pale spikes stay readable where a ribbon runs behind
# the wall slots.
const RIBBON_GREEN := Color("#5CF2B0", 0.24)
const RIBBON_BLUE := Color("#7DE2FF", 0.2)
const RIBBON_VIOLET := Color("#B58CFF", 0.22)
const SNOW_CAP := Color("#8FB8D8")
const ICE := Color("#9CC6E6")
const ICE_LINE := Color("#7CAFD6")
const ICE_PORCH := Color("#B7D8F0")
const LAMP := Color("#FFD27A")
const FUR := Color("#EAF4FB")
const FUR_SHADE := Color("#C9DCEC")
const BEAR_NOSE := Color("#122C47")


func _init() -> void:
	mote_kind = "snow"
	mote_count = 14
	mote_band = Vector2(330, 540)


func paint(pen: ScenePen, t: ThemeDef) -> void:
	var mid := SceneGround.new(558, 10, 1.2, 1.6, t.hill_mid, 1)
	# A little high, so the bears' pale feet stay above the floor spikes.
	var near := SceneGround.new(595, 7, 1.5, 0.4, t.hill_near, 2)
	SceneProps.night_stars(pen, 31, 44, 420)
	_ribbon(pen, 204, 32, RIBBON_GREEN, 0.4)
	_ribbon(pen, 258, 26, RIBBON_BLUE, 1.9)
	_ribbon(pen, 304, 22, RIBBON_VIOLET, 3.1)
	var peaks := ScenePath.at(-10, 640).v(500).l(40, 462).l(84, 494).l(138, 440).l(196, 492)
	pen.fill(peaks.l(236, 470).l(286, 428).l(336, 480).l(370, 462).v(640).done(), t.hill_far)
	for cap: Array in [
		[
			Vector2(138, 440),
			Vector2(152, 453),
			Vector2(140, 456),
			Vector2(130, 451),
			Vector2(124, 454)
		],
		[
			Vector2(286, 428),
			Vector2(300, 442),
			Vector2(290, 446),
			Vector2(280, 440),
			Vector2(273, 441)
		],
		[Vector2(40, 462), Vector2(50, 470), Vector2(40, 474), Vector2(31, 469)],
	]:
		pen.fill(PackedVector2Array(cap), SNOW_CAP)
	mid.paint(pen)
	for d: Vector2 in [Vector2(44, 0.85), Vector2(66, 0.65), Vector2(150, 0.75), Vector2(326, 0.8)]:
		SceneProps.p_pine(pen, d.x, mid.y(d.x) + 2, d.y, t.prop)
	SceneProps.shadow(pen, 252, mid.y(252) + 2, 22, mid)
	_igloo(pen, 252, mid.y(252) + 2, 1.0)
	near.paint(pen)
	SceneProps.shadow(pen, 118, near.y(118) + 2, 17, near)
	_bear(pen, 118, near.y(118) + 2, 1.0, false)
	SceneProps.shadow(pen, 160, near.y(160) + 2, 9, near)
	_bear(pen, 160, near.y(160) + 2, 0.5, true)
	# Snow mounds: (x, half width).
	for d: Vector2 in [Vector2(214, 15), Vector2(300, 20), Vector2(48, 12)]:
		var foot := near.y(d.x) + 3
		var mound := ScenePath.at(d.x - d.y, foot).q(d.x, near.y(d.x) - d.y * 0.55, d.x + d.y, foot)
		pen.fill(mound.done(), t.hill_far)


## A ribbon of light across the room: a wavy band `h` thick with its top near y.
static func _ribbon(pen: ScenePen, y: float, h: float, col: Color, phase: float) -> void:
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for x in range(0, 361, 12):
		var u := x / 360.0 * PI
		var wave := sin(u * 2.4 + phase) * 12.0 + sin(u * 5.2 + phase * 2.0) * 5.0
		top.append(Vector2(x, y + wave))
		bottom.append(Vector2(x, y + wave * 0.5 + h))
	bottom.reverse()
	top.append_array(bottom)
	pen.fill(top, col)


## An igloo: a dome of ice blocks with a porch and a lit doorway.
static func _igloo(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	pen.fill(ScenePen.ellipse_points(Vector2(0, 1), 23, 22, 0, PI, TAU), ICE)
	# Block lines: (x0, y0, x1, y1).
	for d: Vector4 in [
		Vector4(-21.5, -7, 21.5, -7),
		Vector4(-15.5, -15, 15.5, -15),
		Vector4(-8, -7, -8, 1),
		Vector4(6, -7, 6, 1),
		Vector4(-1, -15, -1, -7),
		Vector4(-13, -15, -13, -7),
		Vector4(11, -15, 11, -7),
		Vector4(-5, -21, -5, -15),
		Vector4(6, -21, 6, -15),
	]:
		pen.stroke(PackedVector2Array([Vector2(d.x, d.y), Vector2(d.z, d.w)]), ICE_LINE, 1.4, false)
	pen.fill(ScenePath.at(10, 1).v(-9).a(8, false, true, 26, -9).v(1).done(), ICE_PORCH)
	pen.fill(ScenePath.at(13.5, 1).v(-8).a(4.5, false, true, 22.5, -8).v(1).done(), LAMP)
	pen.pop()


## A polar bear on all fours, facing right (`flip` turns it round).
static func _bear(pen: ScenePen, x: float, b: float, s: float, flip: bool) -> void:
	pen.push(ScenePen.place(x, b, 0.0, -s if flip else s, s))
	pen.rect(-11, -6, 5, 7, FUR_SHADE, 2.2)
	pen.rect(5, -6, 5, 7, FUR_SHADE, 2.2)
	pen.ellipse(Vector2(0, -11), 16, 9, FUR)
	pen.rect(-14, -7, 5.4, 8, FUR, 2.4)
	pen.rect(8.6, -7, 5.4, 8, FUR, 2.4)
	pen.circle(Vector2(-15.5, -12), 2.4, FUR)
	pen.circle(Vector2(15, -15.5), 7, FUR)
	pen.circle(Vector2(11.5, -21.5), 2.5, FUR)
	pen.ellipse(Vector2(21, -13.5), 4.4, 3.3, FUR)
	pen.circle(Vector2(24.4, -14.4), 1.4, BEAR_NOSE)
	pen.circle(Vector2(17, -17), 1.1, BEAR_NOSE)
	pen.pop()


func portal_touch_colors(_t: ThemeDef) -> Array[Color]:
	return [Color.WHITE]


func draw_portal_touch(p: PortalPen, _t: ThemeDef, cols: Array[Color]) -> void:
	PortalPainter.touch_stars(p, cols)
