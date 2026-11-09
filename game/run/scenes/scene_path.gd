class_name ScenePath
extends RefCounted
## Builds an outline the way an SVG path does (M, L, H, V, Q, C, A), in room px
## (360 x 640, y down). Curves become short straight pieces.
##   ScenePath.at(10, 20).l(30, 20).q(40, 10, 50, 20).done()

## Roughly how long each straight piece of a curve is, px.
const STEP := 5.0

var pts := PackedVector2Array()


static func at(x: float, y: float) -> ScenePath:
	var p := ScenePath.new()
	p.pts.append(Vector2(x, y))
	return p


func last() -> Vector2:
	return pts[pts.size() - 1]


func l(x: float, y: float) -> ScenePath:
	pts.append(Vector2(x, y))
	return self


func h(x: float) -> ScenePath:
	return l(x, last().y)


func v(y: float) -> ScenePath:
	return l(last().x, y)


## Quadratic curve through control (cx, cy) to (x, y).
func q(cx: float, cy: float, x: float, y: float) -> ScenePath:
	var p0 := last()
	var c := Vector2(cx, cy)
	var p1 := Vector2(x, y)
	var length := p0.distance_to(c) + c.distance_to(p1)
	var n := clampi(ceili(length / STEP), 2, 24)
	for i in range(1, n + 1):
		var t := float(i) / n
		pts.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))
	return self


## Cubic curve through controls (ax, ay) and (bx, by) to (x, y).
func c(ax: float, ay: float, bx: float, by: float, x: float, y: float) -> ScenePath:
	var p0 := last()
	var c0 := Vector2(ax, ay)
	var c1 := Vector2(bx, by)
	var p1 := Vector2(x, y)
	var length := p0.distance_to(c0) + c0.distance_to(c1) + c1.distance_to(p1)
	var n := clampi(ceili(length / STEP), 3, 32)
	for i in range(1, n + 1):
		pts.append(p0.bezier_interpolate(c0, c1, p1, float(i) / n))
	return self


## A circular arc of radius r to (x, y), with SVG's large-arc and sweep flags.
func a(r: float, large: bool, sweep: bool, x: float, y: float) -> ScenePath:
	var p0 := last()
	var p1 := Vector2(x, y)
	var hp := (p0 - p1) / 2.0
	var d2 := hp.length_squared()
	if d2 < 0.0001:
		return self
	r = maxf(r, sqrt(d2))
	var k := sqrt(maxf(r * r - d2, 0.0) / d2)
	if large == sweep:
		k = -k
	var cp := Vector2(k * hp.y, -k * hp.x)
	var center := cp + (p0 + p1) / 2.0
	var u := (hp - cp) / r
	var w := (-hp - cp) / r
	var start := u.angle()
	var delta := u.angle_to(w)
	if not sweep and delta > 0.0:
		delta -= TAU
	elif sweep and delta < 0.0:
		delta += TAU
	var n := clampi(ceili(absf(delta) * r / STEP), 2, 48)
	for i in range(1, n + 1):
		pts.append(center + Vector2.from_angle(start + delta * i / n) * r)
	return self


func done() -> PackedVector2Array:
	return pts
