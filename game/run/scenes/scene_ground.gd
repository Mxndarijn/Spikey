class_name SceneGround
extends RefCounted
## One rolling layer of land in a room scene: a sine curve, filled down to the
## floor. Props stand on y(x). Depth 0 is far (small, faded toward the sky),
## 1 middle, 2 near (big, full colour).

const SCALES := [0.6, 0.85, 1.15]

var y0: float
var amp: float
var waves: float
var phase: float
var col: Color
var depth: int


func _init(
	p_y0: float, p_amp: float, p_waves: float, p_phase: float, p_col: Color, p_depth: int
) -> void:
	y0 = p_y0
	amp = p_amp
	waves = p_waves
	phase = p_phase
	col = p_col
	depth = p_depth


## The surface height at x.
func y(x: float) -> float:
	return y0 - amp * sin(TAU * waves * x / 360.0 + phase)


## The surface slope at x, in degrees.
func slope(x: float) -> float:
	return rad_to_deg(atan((y(x + 1.0) - y(x - 1.0)) / 2.0))


## Prop size on this layer.
func scale() -> float:
	return SCALES[depth]


## The surface from x0 to x1 (inclusive) every `step` px, `lift` px above it.
func surface(x0: float, x1: float, step: float, lift: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := x0
	while x <= x1 + 0.01:
		pts.append(Vector2(x, y(x) - lift))
		x += step
	return pts


func paint(pen: ScenePen) -> void:
	var pts := PackedVector2Array([Vector2(-10, 640)])
	pts.append_array(surface(-10, 368, 6))
	pts.append(Vector2(370, y(370)))
	pts.append(Vector2(370, 640))
	pen.fill(pts, col)
