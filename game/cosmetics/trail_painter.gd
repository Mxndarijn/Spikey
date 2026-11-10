class_name TrailPainter
extends RefCounted
## Draws a trail (any TrailStyle kind) onto a CanvasItem from a list of points
## and their ages. Used by TrailView in the room and by ItemThumb for the shop
## picture, so both always look the same. Call only from that item's _draw().
## Shapes, sizes and colours follow the design board "Eight new trails".

const INK := Color("#1B1240")
## Music Notes: ink outline width and the small pink dots between notes.
const NOTE_INK_WIDTH := 2.4
const NOTE_DOT := Color("#FF6FA8")
## Leaf Swirl: the midrib.
const LEAF_VEIN := Color("#8A5A2A")
## Star Dust: the tiny white dots between sparkles.
const STAR_DOT := Color("#FFFFFF")
## Pixel Trail: squares snap to this grid (px at full scale).
const PIXEL_GRID := 4.0
## Flap trails: a feather's shaded half, a blossom's heart, a flame's core.
const FEATHER_SHADE := Color("#DCE8EE")
const BLOSSOM_HEART := Color("#FFE45C")
const FLAME_CORE := Color("#FFE45C")
## Comet: the white centre line covers only the newest part of the tail.
const COMET_CORE_SHARE := 0.7


## `pts` oldest first; `ages` in seconds per point; `scale` shrinks widths for
## small previews; `alpha` fades the whole trail (dimmed shop items).
static func paint(
	ci: CanvasItem,
	pts: PackedVector2Array,
	ages: PackedFloat32Array,
	style: TrailStyle,
	head: Color,
	tail: Color,
	scale: float = 1.0,
	alpha: float = 1.0
) -> void:
	if pts.size() < 2 and style.kind != TrailStyle.Kind.STAMPS:
		return
	head.a *= alpha
	tail.a *= alpha
	match style.kind:
		TrailStyle.Kind.RIBBON:
			_band(ci, pts, ages, style, 0.0, style.width * 0.5 * scale, head, tail)
		TrailStyle.Kind.DOTS:
			for i in pts.size():
				var f := fade(ages, i, style)
				ci.draw_circle(pts[i], style.width * 0.5 * f * scale, tail.lerp(head, f))
		TrailStyle.Kind.STRIPES:
			var n := style.colors.size()
			var band := style.width * scale / maxf(n, 1)
			for b in n:
				var off := (b - (n - 1) / 2.0) * band
				var c := style.colors[b]
				# Slightly wider than the spacing so the bands touch, like the board.
				_band(ci, pts, ages, style, off, band * 0.56, Color(c, alpha), Color(c, 0.0))
		TrailStyle.Kind.COMET:
			_comet(ci, pts, ages, style, head, tail, scale, alpha)
		TrailStyle.Kind.STAMPS:
			var newest := pts.size() - 1
			for i in pts.size():
				_stamp(ci, pts[i], ages[i], i, i == newest, style, scale, alpha)


static func fade(ages: PackedFloat32Array, i: int, style: TrailStyle) -> float:
	return clampf(1.0 - ages[i] / style.lifetime, 0.0, 1.0)


## A ribbon `off` px to the side of the path, `half` px wide at its head. It
## narrows toward the tail by `style.taper` and fades from `head` to `tail`.
static func _band(
	ci: CanvasItem,
	pts: PackedVector2Array,
	ages: PackedFloat32Array,
	style: TrailStyle,
	off: float,
	half: float,
	head: Color,
	tail: Color
) -> void:
	var n := pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colors := PackedColorArray()
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var f := fade(ages, i, style)
		var w := lerpf(1.0, f, style.taper)
		var mid := pts[i] + normal * off * w
		left.append(mid + normal * half * w)
		right.append(mid - normal * half * w)
		colors.append(tail.lerp(head, f))
	# Two triangles per segment via draw_primitive: no triangulation, so thin or
	# folded segments at sharp turns can't fail to draw.
	var no_uv := PackedVector2Array()
	for i in n - 1:
		ci.draw_primitive(
			PackedVector2Array([left[i], left[i + 1], right[i + 1]]),
			PackedColorArray([colors[i], colors[i + 1], colors[i + 1]]),
			no_uv
		)
		ci.draw_primitive(
			PackedVector2Array([left[i], right[i + 1], right[i]]),
			PackedColorArray([colors[i], colors[i + 1], colors[i]]),
			no_uv
		)


## A wide faint halo, a hot core, a white centre line near the head and embers
## falling off below the path.
static func _comet(
	ci: CanvasItem,
	pts: PackedVector2Array,
	ages: PackedFloat32Array,
	style: TrailStyle,
	head: Color,
	tail: Color,
	scale: float,
	alpha: float
) -> void:
	var w := style.width * scale
	var halo: Color = style.colors[0] if style.colors.size() > 0 else head
	var core: Color = style.colors[1] if style.colors.size() > 1 else Color.WHITE
	_band(ci, pts, ages, style, 0.0, w, Color(halo, 0.35 * alpha), Color(halo, 0.0))
	_band(ci, pts, ages, style, 0.0, w * 0.5, head, tail)
	var first := int(pts.size() * (1.0 - COMET_CORE_SHARE))
	if pts.size() - first >= 2:
		_band(
			ci,
			pts.slice(first),
			ages.slice(first),
			style,
			0.0,
			w * 0.18,
			Color(core, alpha),
			Color(core, 0.0)
		)
	var spark: Color = style.colors[2] if style.colors.size() > 2 else head
	for i in range(1, pts.size(), 3):
		var f := fade(ages, i, style)
		if f <= 0.0:
			continue
		var drop := Vector2(_jitter(i) * 12.0, ages[i] * 40.0 + absf(_jitter(i + 7)) * 10.0)
		var r := (1.6 + absf(_jitter(i + 3)) * 1.8) * scale
		ci.draw_circle(pts[i] + drop * scale, r, Color(spark, f * alpha))


static func _stamp(
	ci: CanvasItem,
	p: Vector2,
	age: float,
	i: int,
	newest: bool,
	style: TrailStyle,
	scale: float,
	alpha: float
) -> void:
	var f := clampf(1.0 - age / style.lifetime, 0.0, 1.0)
	if f <= 0.0:
		return
	var life := 1.0 - f
	var s := style.width * 0.5 * scale * lerpf(1.0, style.grow, life)
	var pos := p + Vector2(_jitter(i) * 4.0 * scale, -style.rise * age * scale)
	var col := Color.WHITE
	if style.colors.size() > 0:
		col = style.colors[i % style.colors.size()]
	var a := f * alpha
	col.a = a
	var rot := style.spin * age + i * 0.9
	match style.shape:
		TrailStyle.Shape.BUBBLE:
			_bubble(ci, pos, s, a, col, scale)
		TrailStyle.Shape.CONFETTI:
			# A paper bit: spins and flips over as it falls.
			var flip := maxf(absf(cos(style.spin * 0.6 * age + i * 1.3)), 0.25)
			ci.draw_set_transform(pos, rot, Vector2(1.0, flip))
			ci.draw_colored_polygon(_round_rect(s, s * 0.55, 1.5 * scale), col)
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.SPARKLE:
			# Twinkles once: small at the flyer, biggest halfway, then out.
			var size := s * (0.65 + 0.25 * _jitter(i + 5)) * (0.6 + 0.6 * sin(PI * life))
			ci.draw_colored_polygon(sparkle_points(pos, size), col)
			if i % 2 == 1:
				var dot := pos + Vector2(7.0, -5.0) * scale
				ci.draw_circle(dot, 1.4 * scale, Color(STAR_DOT, a * 0.8))
		TrailStyle.Shape.LEAF:
			ci.draw_set_transform(pos, rot)
			ci.draw_colored_polygon(_lens(s, s * 0.5), col)
			ci.draw_line(
				Vector2(-s * 0.75, 0), Vector2(s * 0.75, 0), Color(LEAF_VEIN, a * 0.5), 1.2 * scale
			)
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.NOTE:
			# Pops in over the first 0.12 s, then rises and fades.
			var pop := 1.0 - pow(1.0 - clampf(age / 0.12, 0.0, 1.0), 2.0)
			var u := s / 5.0 * (0.55 + 0.45 * pop)
			_note(ci, pos, u, _jitter(i) * 0.4, i % 3 == 1, a * 0.85, col)
			ci.draw_circle(pos + Vector2(-14.0, 12.0) * u, 2.0 * u, Color(NOTE_DOT, a * 0.8))
		TrailStyle.Shape.PIXEL:
			var grid := PIXEL_GRID * scale
			var cell := (pos / grid).floor() * grid
			# Alternating 8 and 7 px squares; sizes snap to whole pixels as they shrink.
			var half := s * (1.0 if i % 2 == 0 else 0.875)
			half = maxf(roundf(half * 2.0) / 2.0, 1.0)
			var c := Color(Color.WHITE, a) if newest else col
			ci.draw_rect(Rect2(cell - Vector2(half, half), Vector2(half, half) * 2.0), c)
		_:
			_flap_stamp(ci, pos, s, age, i, a, col, style, scale)


## The flap trails' shapes (one stamp per tap), `s` px from centre to edge.
static func _flap_stamp(
	ci: CanvasItem,
	pos: Vector2,
	s: float,
	age: float,
	i: int,
	a: float,
	col: Color,
	style: TrailStyle,
	scale: float
) -> void:
	# Pops in over the first 0.1 s.
	var pop := 0.6 + 0.4 * clampf(age / 0.1, 0.0, 1.0)
	var rot := style.spin * age + i * 0.9
	match style.shape:
		TrailStyle.Shape.CLOUD:
			ci.draw_circle(pos + Vector2(-0.8, 0.1) * s, s * 0.7, col)
			ci.draw_circle(pos + Vector2(0.1, -0.3) * s, s * 0.9, col)
			ci.draw_circle(pos + Vector2(1.0, 0.2) * s, s * 0.6, col)
		TrailStyle.Shape.RING:
			ci.draw_set_transform(pos, 0.0, Vector2(1.0, 0.45))
			ci.draw_arc(Vector2.ZERO, s, 0.0, TAU, 24, col, maxf(2.5 * scale, 1.0), true)
			ci.draw_arc(Vector2.ZERO, s * 0.5, 0.0, TAU, 16, col, maxf(2.5 * scale, 1.0), true)
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.HEART:
			ci.draw_set_transform(pos, 0.0, Vector2(pop, pop))
			ci.draw_colored_polygon(heart_points(s), col)
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.FEATHER:
			ci.draw_set_transform(pos, sin(rot) * 0.7)
			ci.draw_colored_polygon(_lens(s, s * 0.45), col)
			ci.draw_colored_polygon(_half_lens(s, s * 0.45), Color(FEATHER_SHADE, a))
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.DROPS:
			for k: int in [-1, 0, 1]:
				var c := col
				if k == 0 and style.colors.size() > 1:
					c = Color(style.colors[(i + 1) % style.colors.size()], a)
				var at := pos + Vector2(k * 0.85, -0.25 if k == 0 else 0.0) * s
				ci.draw_set_transform(at, k * 0.7)
				ci.draw_colored_polygon(_drop(s * 0.5), c)
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.SNOWFLAKE:
			for k in 3:
				var arm := Vector2.from_angle(rot + PI / 3.0 * k) * s
				ci.draw_line(pos - arm, pos + arm, col, maxf(2.4 * scale, 1.0), true)
		TrailStyle.Shape.BLOSSOM:
			for k in 5:
				var petal := Vector2.from_angle(TAU / 5.0 * k - PI / 2.0) * s * 0.75 * pop
				ci.draw_circle(pos + petal, s * 0.55 * pop, col)
			ci.draw_circle(pos, s * 0.4 * pop, Color(BLOSSOM_HEART, a))
		TrailStyle.Shape.PAW:
			# Left and right paws in turn.
			ci.draw_set_transform(pos, 0.26 if i % 2 == 0 else -0.26, Vector2(1.0, 0.85))
			ci.draw_circle(Vector2(0.0, s * 0.45), s * 0.75, col)
			ci.draw_set_transform(pos, 0.26 if i % 2 == 0 else -0.26)
			for k: int in [-1, 0, 1]:
				var toe := Vector2(k * 0.8, -0.55 if k != 0 else -0.95) * s
				ci.draw_circle(toe, s * 0.33, col)
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.FLAME:
			ci.draw_set_transform(pos, 0.0, Vector2(pop, pop))
			ci.draw_colored_polygon(_flame(s), col)
			ci.draw_set_transform(pos + Vector2(0.0, s * 0.45), 0.0, Vector2(pop, pop) * 0.5)
			ci.draw_colored_polygon(_flame(s), Color(FLAME_CORE, a))
			ci.draw_set_transform(Vector2.ZERO)
		TrailStyle.Shape.BOLT:
			ci.draw_set_transform(pos, 0.0, Vector2(pop, pop))
			ci.draw_colored_polygon(_bolt(s), col)
			ci.draw_set_transform(Vector2.ZERO)


## A heart, point down, `s` px from centre to its sides.
static func heart_points(s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector2 in [
		Vector2(0, 1),
		Vector2(-1, -0.1),
		Vector2(-1, -0.6),
		Vector2(-0.75, -0.95),
		Vector2(-0.4, -1),
		Vector2(-0.1, -0.8),
		Vector2(0, -0.5),
		Vector2(0.1, -0.8),
		Vector2(0.4, -1),
		Vector2(0.75, -0.95),
		Vector2(1, -0.6),
		Vector2(1, -0.1),
	]:
		pts.append(p * s)
	return pts


## The lower half of a _lens (a feather's shaded side).
static func _half_lens(half_len: float, half_w: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-half_len, 0.0)])
	var steps := 6
	for j in range(1, steps):
		var t := float(j) / steps
		pts.append(Vector2(lerpf(-half_len, half_len, t), sin(PI * t) * half_w))
	pts.append(Vector2(half_len, 0.0))
	return pts


## A teardrop, tip up, `r` px round.
static func _drop(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(0.0, -r * 1.7)])
	for j in 9:
		pts.append(Vector2.from_angle(-PI / 6.0 + (PI + PI / 3.0) * j / 8.0) * r)
	return pts


static func _flame(s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector2 in [
		Vector2(0, -1.4),
		Vector2(0.7, -0.2),
		Vector2(0.75, 0.5),
		Vector2(0.45, 1.0),
		Vector2(0, 1.15),
		Vector2(-0.45, 1.0),
		Vector2(-0.75, 0.5),
		Vector2(-0.7, -0.2),
	]:
		pts.append(p * s)
	return pts


static func _bolt(s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector2 in [
		Vector2(0.25, -1),
		Vector2(-0.6, 0.1),
		Vector2(-0.1, 0.1),
		Vector2(-0.35, 1),
		Vector2(0.6, -0.15),
		Vector2(0.1, -0.15),
	]:
		pts.append(p * s)
	return pts


## A bubble: faint fill, white ring, a highlight up and to the left. It keeps
## most of its ring until late in its life, like the board (0.95 -> 0.35).
static func _bubble(
	ci: CanvasItem, pos: Vector2, s: float, a: float, col: Color, scale: float
) -> void:
	var k := sqrt(a)
	ci.draw_circle(pos, s, Color(col, 0.15 * k))
	ci.draw_arc(pos, s, 0, TAU, 24, Color(col, 0.95 * k), maxf(2.0 * scale, 1.0), true)
	ci.draw_circle(pos + Vector2(-0.4, -0.5) * s, s * 0.25, Color(col, 0.7 * k))


## A four-point sparkle with curved (concave) sides, `r` px from centre to tip.
static func sparkle_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 5
	for k in 4:
		var a := Vector2.from_angle(PI / 2.0 * k - PI / 2.0) * r
		var b := Vector2.from_angle(PI / 2.0 * (k + 1) - PI / 2.0) * r
		# Quadratic curve from tip to tip with its control point at the centre.
		for j in steps:
			var t := float(j) / steps
			pts.append(c + a * (1.0 - t) * (1.0 - t) + b * t * t)
	return pts


## A leaf: pointed at both ends, `half_len` long each way, `half_w` wide.
static func _lens(half_len: float, half_w: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 6
	for j in steps:
		var t := float(j) / steps
		pts.append(Vector2(lerpf(-half_len, half_len, t), -sin(PI * t) * half_w))
	for j in steps:
		var t := float(j) / steps
		pts.append(Vector2(lerpf(half_len, -half_len, t), sin(PI * t) * half_w))
	return pts


## A rectangle `hw` x `hh` half-size with rounded corners of radius `r`.
static func _round_rect(hw: float, hh: float, r: float) -> PackedVector2Array:
	r = minf(r, minf(hw, hh))
	var pts := PackedVector2Array()
	var centres := [
		Vector2(hw - r, -hh + r),
		Vector2(hw - r, hh - r),
		Vector2(-hw + r, hh - r),
		Vector2(-hw + r, -hh + r)
	]
	for k in 4:
		for j in 3:
			var ang := -PI / 2.0 + PI / 2.0 * (k + j / 2.0)
			pts.append((centres[k] as Vector2) + Vector2.from_angle(ang) * r)
	return pts


## A music note on the board's 5-unit grid (`u` px per unit): white with an
## ink outline so it reads on every sky. `beamed` draws two notes joined.
static func _note(
	ci: CanvasItem, pos: Vector2, u: float, tilt: float, beamed: bool, a: float, col: Color
) -> void:
	var ink := Color(INK, a)
	var fill := Color(col, a)
	var heads: Array[Vector2] = [Vector2(0, 8)]
	var flag := PackedVector2Array([Vector2(4, 8), Vector2(4, -8), Vector2(10, -5)])
	if beamed:
		heads.append(Vector2(12, 6))
		flag = PackedVector2Array([Vector2(4, 8), Vector2(4, -8), Vector2(16, -10), Vector2(16, 6)])
	ci.draw_set_transform(pos, tilt, Vector2(u, u))
	var outline := flag.duplicate()
	outline.append(flag[0])
	ci.draw_polyline(outline, ink, NOTE_INK_WIDTH, true)
	ci.draw_colored_polygon(flag, fill)
	for h in heads:
		ci.draw_set_transform(pos + (h * u).rotated(tilt), tilt, Vector2(u, u * 0.8))
		ci.draw_circle(Vector2.ZERO, 5.0 + NOTE_INK_WIDTH * 0.5, ink)
		ci.draw_circle(Vector2.ZERO, 5.0, fill)
	ci.draw_set_transform(Vector2.ZERO)


## A fixed sideways offset per stamp, so stamps scatter without random numbers.
static func _jitter(i: int) -> float:
	return sin(i * 12.9898) * 0.5
