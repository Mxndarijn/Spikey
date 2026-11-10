class_name CrashPainter
extends RefCounted
## Draws a crash effect (any CrashStyle) onto a CanvasItem at one moment `t`
## (seconds since the crash): in the room through CrashView and in the shop
## pictures, so both always look the same. Call only from that item's _draw().
## Friendly, so never in the world's spike colour. Every piece's path comes
## from its index, so the same crash always draws the same and no random
## numbers are used. A new kind is one `_<kind>` function here plus its line
## in paint().

const INK := Color("#231A33")
## A feather's shaded half.
const FEATHER_SHADE := Color("#FFE8D2")
const POW_TEXT := "POW!"
const POW_FONT := 22
## The flyer's drawn canvas in a run (BirdView): sizes here are tuned on it.
const REF := 72.0
## How long a burst piece lives, at most.
const PIECE_LIFE := 1.4
## Burst pieces: [speed px/s, gravity px/s2].
const MOTION := {
	CrashStyle.FEATHER: [70.0, 50.0],
	CrashStyle.CONFETTI: [190.0, 300.0],
	CrashStyle.SHARD: [170.0, 420.0],
	CrashStyle.PIXEL: [80.0, 140.0],
}
## Paint Splat: the blob's circles (x, y, radius) and drips (x, top, length).
const BLOB: Array[Vector3] = [
	Vector3(0, 0, 26),
	Vector3(18, -18, 10),
	Vector3(-20, -14, 12),
	Vector3(-16, 18, 11),
	Vector3(16, 18, 9),
]
const DRIPS: Array[Vector3] = [Vector3(-20, 16, 40), Vector3(2, 20, 26), Vector3(-34, -12, 22)]
const DRIP_WIDTH := 7.0


## `origin`: where the flyer crashed. `away`: +1 when pieces fly right (it hit
## the left wall), -1 when they fly left. `scale` shrinks it for small
## pictures; `alpha` fades it (dimmed shop items). `palette` replaces the
## style's colours for Shatter (the flyer's own colours).
static func paint(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	away: float,
	scale: float = 1.0,
	alpha: float = 1.0,
	palette: PackedColorArray = PackedColorArray()
) -> void:
	if style == null or t < 0.0 or alpha <= 0.0 or scale <= 0.0:
		return
	if not style.loops() and t > style.duration():
		return
	var cols := style.colors
	if style.piece == CrashStyle.SHARD and not palette.is_empty():
		cols = palette
	if cols.is_empty():
		cols = PackedColorArray([Color.WHITE])
	var side := 1.0 if away >= 0.0 else -1.0
	match style.kind:
		CrashStyle.SPLAT:
			_splat(ci, style, t, origin, side, scale, alpha, cols)
		CrashStyle.RAYS:
			_rays(ci, style, t, origin, scale, alpha, cols)
		CrashStyle.POW:
			_pow(ci, style, t, origin, scale, alpha, cols)
		CrashStyle.ORBIT:
			_orbit(ci, style, t, origin, side, scale, alpha, cols)
		CrashStyle.BUBBLE:
			_bubble(ci, style, t, origin, scale, alpha, cols)
		CrashStyle.GHOST:
			_ghost(ci, t, origin, scale, alpha, cols)
		_:
			_burst(ci, style, t, origin, side, scale, alpha, cols)
	ci.draw_set_transform(Vector2.ZERO)


## A number from 0 to 1 that is always the same for piece `i` and `salt`.
static func rnd(i: int, salt: int) -> float:
	var v := sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return v - floorf(v)


static func ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


## Eases to 1 with a small overshoot (a pop).
static func back_out(x: float) -> float:
	var c := 1.70158
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


## A few of a flyer's own colours for Shatter: sampled from its art, skipping
## the ink outline. Empty when the art can't be read (the style's own colours
## are used then).
static func flyer_palette(tex: Texture2D) -> PackedColorArray:
	var out := PackedColorArray()
	if tex == null:
		return out
	var img := tex.get_image()
	if img == null or img.is_empty():
		return out
	if img.is_compressed() and img.decompress() != OK:
		return out
	var w := img.get_width()
	var h := img.get_height()
	for j in 7:
		for i in 7:
			var c := img.get_pixel(int(w * (0.2 + 0.1 * i)), int(h * (0.2 + 0.1 * j)))
			if c.a < 0.9 or c.v < 0.3:
				continue
			var known := false
			for k in out:
				if absf(k.r - c.r) + absf(k.g - c.g) + absf(k.b - c.b) < 0.25:
					known = true
			if not known:
				out.append(Color(c, 1.0))
			if out.size() >= 4:
				return out
	return out


## Pieces thrown away from the wall: they slow down, fall and fade.
static func _burst(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	side: float,
	scale: float,
	alpha: float,
	cols: PackedColorArray
) -> void:
	var motion: Array = MOTION.get(style.piece, MOTION[CrashStyle.CONFETTI])
	var base := 0.0 if side > 0.0 else PI
	if style.piece == CrashStyle.FEATHER and t < 0.4:
		# The puff where it hit.
		var k := t / 0.4
		var puff := Color(cols[0], (1.0 - k) * alpha)
		for p: Vector3 in [Vector3(-4, 6, 10), Vector3(-16, -2, 7), Vector3(-12, 14, 6)]:
			var at := origin + Vector2(p.x * side, p.y) * scale
			ci.draw_circle(at, p.z * (0.6 + 0.6 * k) * scale, puff)
	for i in style.count:
		var life := PIECE_LIFE * (0.65 + 0.35 * rnd(i, 1))
		var f := 1.0 - t / life
		if f <= 0.0:
			continue
		# A wide cone away from the wall, tipped a little upward.
		var ang := base + (rnd(i, 2) - 0.5) * 2.6 - 0.3 * side
		var speed := float(motion[0]) * (0.45 + 0.75 * rnd(i, 3))
		var travel := speed * t * (1.0 - 0.3 * minf(t / life, 1.0))
		var fall := Vector2(0.0, float(motion[1]) * t * t * 0.5)
		var pos := origin + (Vector2.from_angle(ang) * travel + fall) * scale
		var col := Color(cols[i % cols.size()], minf(f * 2.5, 1.0) * alpha)
		var spin := (rnd(i, 4) - 0.5) * 10.0 * t + rnd(i, 5) * TAU
		match style.piece:
			CrashStyle.FEATHER:
				var s := (0.8 + 0.5 * rnd(i, 6)) * scale
				pos.x += sin(t * 5.0 + i) * 6.0 * scale
				ci.draw_set_transform(pos, ang + sin(t * 4.0 + i) * 0.8, Vector2(s, s))
				ci.draw_colored_polygon(_lens(9.0, 5.0, true), col)
				ci.draw_colored_polygon(_lens(9.0, 5.0, false), Color(FEATHER_SHADE, col.a))
			CrashStyle.SHARD:
				var s := (0.6 + 0.6 * rnd(i, 6)) * scale
				ci.draw_set_transform(pos, spin, Vector2(s, s))
				ci.draw_colored_polygon(
					PackedVector2Array([Vector2(-9, 6), Vector2(9, 2), Vector2(-1, -10)]), col
				)
			CrashStyle.PIXEL:
				# Blocks keep to a grid and shrink in whole pixels.
				var half := maxf(roundf((2.0 + 3.0 * rnd(i, 6)) * f + 1.0), 1.0) * scale
				var cell := (pos / (2.0 * scale)).floor() * 2.0 * scale
				ci.draw_set_transform(Vector2.ZERO)
				ci.draw_rect(Rect2(cell - Vector2(half, half), Vector2(half, half) * 2.0), col)
			_:
				_confetti(ci, i, pos, spin, t, scale, col)
	ci.draw_set_transform(Vector2.ZERO)


## One paper bit: a strip that flips over, a dot or a triangle.
static func _confetti(
	ci: CanvasItem, i: int, pos: Vector2, spin: float, t: float, scale: float, col: Color
) -> void:
	match i % 3:
		0:
			var flip := maxf(absf(cos(t * 6.0 + i)), 0.3)
			ci.draw_set_transform(pos, spin, Vector2(scale, scale * flip))
			ci.draw_rect(Rect2(-5.0, -2.0, 10.0, 4.0), col)
		1:
			ci.draw_set_transform(Vector2.ZERO)
			ci.draw_circle(pos, 3.0 * scale, col)
		_:
			ci.draw_set_transform(pos, spin, Vector2(scale, scale))
			ci.draw_colored_polygon(
				PackedVector2Array([Vector2(0, -4), Vector2(4, 3), Vector2(-4, 3)]), col
			)


## A flat blob that pops out where the flyer hit, drips, and throws drops.
static func _splat(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	side: float,
	scale: float,
	alpha: float,
	cols: PackedColorArray
) -> void:
	var col := Color(cols[0], alpha)
	var k := back_out(clampf(t / 0.18, 0.0, 1.0))
	var grow := clampf((t - 0.15) / 0.9, 0.0, 1.0)
	for d in DRIPS:
		var top := origin + Vector2(d.x * side, d.y) * scale * k
		var length := d.z * grow * scale
		var half := DRIP_WIDTH * 0.5 * scale
		ci.draw_rect(Rect2(top - Vector2(half, 0.0), Vector2(half * 2.0, length)), col)
		ci.draw_circle(top + Vector2(0.0, length), half, col)
	for b in BLOB:
		ci.draw_circle(origin + Vector2(b.x * side, b.y) * scale * k, b.z * scale * k, col)
	var base := 0.0 if side > 0.0 else PI
	for i in style.count:
		var life := 0.9 * (0.6 + 0.4 * rnd(i, 1))
		var f := 1.0 - t / life
		if f <= 0.0:
			continue
		var ang := base + (rnd(i, 2) - 0.5) * 2.2 - 0.3 * side
		var travel := 150.0 * (0.5 + 0.7 * rnd(i, 3)) * t
		var pos := origin + (Vector2.from_angle(ang) * travel + Vector2(0.0, 190.0 * t * t)) * scale
		ci.draw_circle(pos, (2.5 + 3.5 * rnd(i, 4)) * scale, Color(col, minf(f * 2.5, 1.0) * alpha))


## Rays that shoot out in a ring, long and short in turn, each ending in a dot.
static func _rays(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	scale: float,
	alpha: float,
	cols: PackedColorArray
) -> void:
	var a := (1.0 - clampf((t - 0.55) / 0.6, 0.0, 1.0)) * alpha
	var n := maxi(style.count, 1)
	for i in n:
		var dir := Vector2.from_angle(TAU * i / n - PI / 2.0)
		var long := i % 2 == 0
		var reach := (48.0 if long else 30.0) * scale
		var head := reach * ease_out(clampf(t / 0.35, 0.0, 1.0))
		var tail := reach * 0.85 * clampf((t - 0.12) / 0.45, 0.0, 1.0)
		var col := Color(cols[i % cols.size()], a)
		ci.draw_line(origin + dir * tail, origin + dir * head, col, 3.0 * scale, true)
		ci.draw_circle(origin + dir * head, (4.0 if long else 3.0) * scale, col)
	var core := 1.0 - clampf(t / 0.3, 0.0, 1.0)
	ci.draw_circle(origin, 8.0 * core * scale, Color(Color.WHITE, alpha))
	for i in 5:
		# Sparks that fall once the rays are out.
		var st := t - 0.35 - 0.05 * i
		if st <= 0.0:
			continue
		var from := Vector2((rnd(i, 1) - 0.5) * 80.0, (rnd(i, 2) - 0.5) * 40.0)
		var pos := origin + (from + Vector2(0.0, 60.0 * st + 120.0 * st * st)) * scale
		ci.draw_circle(pos, 2.2 * scale, Color(cols[i % cols.size()], a))


## A two-layer comic starburst that pops out and holds, with its word.
static func _pow(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	scale: float,
	alpha: float,
	cols: PackedColorArray
) -> void:
	var a := (1.0 - clampf((t - 0.9) / 0.4, 0.0, 1.0)) * alpha
	var k := back_out(clampf(t / 0.16, 0.0, 1.0)) * scale
	var star := _star(maxi(style.count, 5), 46.0, 28.0)
	var outer: Color = cols[1 % cols.size()]
	ci.draw_set_transform(origin, -0.12, Vector2(k, k) * 1.28)
	ci.draw_colored_polygon(star, Color(outer, a))
	ci.draw_set_transform(origin, -0.12, Vector2(k, k))
	ci.draw_colored_polygon(star, Color(cols[0], a))
	if t < 0.08:
		return
	var font := GameFonts.display()
	var size := maxi(int(POW_FONT * scale), 6)
	ci.draw_set_transform(origin + Vector2(-64.0, 70.0) * scale, -0.14)
	ci.draw_string_outline(
		font, Vector2.ZERO, POW_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(outer, a)
	)
	ci.draw_string(font, Vector2.ZERO, POW_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, a))


## Stars circling above the flyer on a dashed ring, and three knock marks.
static func _orbit(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	side: float,
	scale: float,
	alpha: float,
	cols: PackedColorArray
) -> void:
	var a := clampf(t / 0.2, 0.0, 1.0) * alpha
	var c := origin + Vector2(0.0, -36.0) * scale
	var radii := Vector2(28.0, 9.0) * scale
	for d in 10:
		var from := TAU * d / 10.0 + t * 0.6
		var dash := PackedVector2Array()
		for j in 4:
			dash.append(c + Vector2.from_angle(from + 0.3 * j / 3.0) * radii)
		ci.draw_polyline(dash, Color(Color.WHITE, 0.8 * a), 2.0 * scale, true)
	var n := maxi(style.count, 1)
	for k in n:
		var phase := t * 3.5 + TAU * k / n
		var at := c + Vector2.from_angle(phase) * radii
		# Bigger at the front of the ring.
		var r := (6.5 + 2.0 * sin(phase)) * scale
		ci.draw_colored_polygon(TrailPainter.sparkle_points(at, r), Color(cols[k % cols.size()], a))
	if t < 0.35:
		var knock := Color(Color.WHITE, (1.0 - t / 0.35) * alpha)
		for j in 3:
			var from := origin + Vector2(-side * 22.0, -10.0 + 10.0 * j) * scale
			var to := from + Vector2(-side * 9.0, -4.0 + 4.0 * j) * scale
			ci.draw_line(from, to, knock, 3.0 * scale, true)


## A bubble that closes round the flyer and wobbles; small ones rise beside it.
static func _bubble(
	ci: CanvasItem,
	style: CrashStyle,
	t: float,
	origin: Vector2,
	scale: float,
	alpha: float,
	cols: PackedColorArray
) -> void:
	var col: Color = cols[0]
	var r := 40.0 * scale * back_out(clampf(t / 0.3, 0.0, 1.0)) * (1.0 + 0.03 * sin(t * 3.0))
	if r >= 1.0:
		ci.draw_circle(origin, r, Color(col, 0.25 * alpha))
		ci.draw_arc(origin, r, 0.0, TAU, 40, Color(col, alpha), 3.0 * scale, true)
		ci.draw_arc(origin, r * 0.72, PI * 1.1, PI * 1.45, 10, Color(col, alpha), 4.0 * scale, true)
	for i in style.count:
		var cycle := fmod(t * 0.5 + rnd(i, 1), 1.0)
		var at := origin + Vector2((rnd(i, 2) - 0.5) * 70.0, 56.0 - cycle * 80.0) * scale
		var small := (3.0 + 4.0 * rnd(i, 3)) * scale
		var fade := minf(t / 0.3, 1.0) * (1.0 - cycle) * alpha
		ci.draw_arc(at, small, 0.0, TAU, 16, Color(col, fade), 2.0 * scale, true)


## A small ghost with a halo that sways up out of the flyer and fades.
static func _ghost(
	ci: CanvasItem, t: float, origin: Vector2, scale: float, alpha: float, cols: PackedColorArray
) -> void:
	var a := clampf(t / 0.15, 0.0, 1.0) * (1.0 - clampf((t - 1.3) / 0.5, 0.0, 1.0)) * alpha
	var rise := 64.0 * ease_out(clampf(t / 1.2, 0.0, 1.0))
	var pos := origin + Vector2(sin(t * 3.0) * 5.0, -20.0 - rise) * scale
	var s := 1.5 * scale
	var tilt := sin(t * 3.0) * 0.12
	var body := PackedVector2Array([Vector2(-11, 12), Vector2(-11, -3)])
	for j in range(1, 8):
		body.append(Vector2(0, -3) + Vector2.from_angle(PI + PI * j / 8.0) * 11.0)
	for p: Vector2 in [
		Vector2(11, -3),
		Vector2(11, 12),
		Vector2(7, 8),
		Vector2(3.5, 12),
		Vector2(0, 8),
		Vector2(-3.5, 12),
		Vector2(-7, 8),
	]:
		body.append(p)
	ci.draw_set_transform(pos, tilt, Vector2(s, s))
	ci.draw_colored_polygon(body, Color(cols[0], a))
	var ink := Color(INK, a)
	ci.draw_circle(Vector2(-4, -3), 2.0, ink)
	ci.draw_circle(Vector2(4, -3), 2.0, ink)
	ci.draw_circle(Vector2(0, 3), 2.2, ink)
	var gold: Color = cols[1 % cols.size()]
	ci.draw_set_transform(pos + Vector2(0.0, -21.0).rotated(tilt) * s, tilt, Vector2(s, s * 0.32))
	ci.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(gold, a), 2.6, true)
	ci.draw_set_transform(Vector2.ZERO)
	for j: int in [-1, 1]:
		var at := pos + Vector2(j * 30.0, -6.0 + 8.0 * j) * scale
		ci.draw_colored_polygon(
			TrailPainter.sparkle_points(at, (4.5 + j) * scale), Color(cols[0], a * 0.9)
		)


## A feather's upper (or lower) half: pointed at both ends.
static func _lens(half_len: float, half_w: float, upper: bool) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-half_len, 0.0)])
	var steps := 6
	for j in range(1, steps):
		var u := float(j) / steps
		var y := sin(PI * u) * half_w
		pts.append(Vector2(lerpf(-half_len, half_len, u), -y if upper else y))
	pts.append(Vector2(half_len, 0.0))
	return pts


## A starburst with `points` tips at `outer` px and dips at `inner` px.
static func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r := outer if i % 2 == 0 else inner
		pts.append(Vector2.from_angle(PI * i / points) * r)
	return pts
