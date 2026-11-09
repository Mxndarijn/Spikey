class_name PortalPainter
extends RefCounted
## Draws an exit portal (any PortalStyle) onto a CanvasItem: in the room and in
## the shop pictures, so both always look the same. Call only from that item's
## _draw(). Safe, so never in the world's spike colour.
##
## Every style is the same vortex disc: a rim ring, the disc, a turning inside
## drawn by its `kind` (spiral arms, dots, rings, galaxy, pixel), and a dark eye.
## Match my world adds the world's own touch on the rim. A new kind is one
## `_draw_<kind>` function here plus its line in paint().

## The sizes are tuned on the game's exit: half height 48 px (SimConfig.EXIT_HALF).
const REF_HALF := 48.0
## Where RoomView puts the `center` it passes (its EXIT_DEPTH), and where the
## disc's centre sits, both in px from the wall at the game's exit size.
const EXIT_CENTER_DEPTH := 6.0
const DISC_DEPTH := 18.0
## Spiral radius in disc units (inside the rim, PortalPen.OUTER).
const R := 58.0
## How fast the inside turns, radians per second.
const SPIN_SPEED := 1.2
## Shop pictures: the portal's half-height as a share of the room's height and
## the fixed moment they show.
const THUMB_HEIGHT := 0.4
const THUMB_TIME := 0.8

## Rim touches with fixed colours.
const AUTUMN_LEAVES: Array[Color] = [Color("E2603A"), Color("F2A23A"), Color("C9452F")]
const SPRINKLES: Array[Color] = [Color("FFFFFF"), Color("7FD3FF"), Color("FFD23F"), Color("7FE3B5")]
const EMBER := Color("FFD27A")
const PEBBLE := Color("C98366")
## Neon's spikes are hot pink, so its rim glows cyan.
const NEON_RING := Color("4FE3FF")
const WISP := Color(0.913725, 0.882353, 1.0, 0.8)


## `center`: the disc's centre. `side`: 0 on the left wall, 1 on the right.
## `colors`: from PortalStyle.colors(). `theme` picks the rim touch.
static func paint(
	ci: CanvasItem,
	style: PortalStyle,
	center: Vector2,
	half_height: float,
	side: int,
	open_amount: float,
	time: float,
	colors: Dictionary,
	theme: ThemeDef,
	alpha: float = 1.0
) -> void:
	if style == null or open_amount <= 0.0 or half_height <= 0.0:
		return
	var o := clampf(open_amount, 0.0, 1.15)
	var into := 1.0 if side == 0 else -1.0
	var scale := half_height / PortalPen.OUTER * o
	var p := PortalPen.new(ci, center, scale, into, time * SPIN_SPEED, alpha)
	var base: Color = colors["base"]
	var arms: Array[Color] = []
	arms.assign(colors["arms"])
	p.circle(0.0, 0.0, PortalPen.OUTER, colors["rim"], false)
	p.circle(0.0, 0.0, R + 2.0, base, false)
	match style.kind:
		PortalStyle.DOTS:
			_draw_dots(p, style, arms)
		PortalStyle.RINGS:
			_draw_rings(p, style, arms)
		PortalStyle.GALAXY:
			_draw_galaxy(p, style, arms)
		PortalStyle.PIXEL:
			_draw_pixel(p, style, arms)
		_:
			_draw_spiral(p, style, arms)
	p.circle(0.0, 0.0, 9.0, colors["eye"], false, 16)
	if style.follows_world and theme != null:
		_draw_touch(p, theme)


## Points along one spiral arm from the eye out to R, starting at angle `a0`.
static func arm(a0: float, steps: int = 40, tight: float = 0.075) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var r := 6.0 + (R - 6.0) * i / steps
		var a := a0 + r * tight
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts


static func _draw_spiral(p: PortalPen, style: PortalStyle, arms: Array[Color]) -> void:
	var n := maxi(style.arm_count, 1)
	for j in n:
		p.stroke(arm(j * TAU / n), style.arm_width, arms[j % arms.size()])


static func _draw_dots(p: PortalPen, style: PortalStyle, arms: Array[Color]) -> void:
	var n := maxi(style.arm_count, 1)
	for j in n:
		for v in arm(j * TAU / n, 12):
			p.circle(v.x, v.y, 1.5 + v.length() * 0.09, arms[j % mini(arms.size(), 2)], true, 12)


## Broken rings: each a dashed circle, turned a little from the last.
static func _draw_rings(p: PortalPen, style: PortalStyle, arms: Array[Color]) -> void:
	var radii: Array[float] = [16.0, 28.0, 40.0, 52.0]
	for j in radii.size():
		var r := radii[j]
		# Dashes 0.9 r long with 0.35 r gaps (in radians: 0.9 and 0.35).
		var dash := 0.9
		var gap := 0.35
		var a := j * deg_to_rad(40.0)
		var end := a + TAU
		while a < end - 0.01:
			var stop := minf(a + dash, end)
			var pts := PackedVector2Array()
			var steps := 8
			for i in steps + 1:
				var t := lerpf(a, stop, float(i) / steps)
				pts.append(Vector2(cos(t) * r, sin(t) * r))
			p.stroke(pts, style.arm_width, arms[j % mini(arms.size(), 2)], true, false)
			a = stop + gap


static func _draw_galaxy(p: PortalPen, style: PortalStyle, arms: Array[Color]) -> void:
	var n := maxi(style.arm_count, 1)
	for j in n:
		var c := Color(arms[j % mini(arms.size(), 2)], 0.8)
		p.stroke(arm(j * TAU / n, 40, 0.09), style.arm_width, c)
	var sizes: Array[float] = [1.2, 1.8, 2.4]
	for i in 16:
		var a := i * 2.39996 + 0.7
		var r := 8.0 + (R - 12.0) * fposmod(i * 0.618034 + 0.13, 1.0)
		p.circle(cos(a) * r, sin(a) * r, sizes[i % 3], Color.WHITE, true, 8)


## Blocks along two arms, snapped to a grid, growing outward.
static func _draw_pixel(p: PortalPen, style: PortalStyle, arms: Array[Color]) -> void:
	var n := maxi(style.arm_count, 1)
	for j in n:
		for v in arm(j * TAU / n, 18):
			var s := 3.0 + v.length() * 0.1
			p.square(
				roundf(v.x / 6.0) * 6.0, roundf(v.y / 6.0) * 6.0, s, arms[j % mini(arms.size(), 2)]
			)


## The touch colours each world adds on the rim (Match my world only).
static func touch_colors(theme: ThemeDef) -> Array[Color]:
	match theme.id:
		"sunset":
			return [theme.glow]
		"jungle", "meadow":
			return [theme.world_accent, theme.trail]
		"autumn":
			return AUTUMN_LEAVES
		"ice", "deepsea", "star", "blossom", "winterfest", "cove", "clouds", "aurora":
			return [Color.WHITE]
		"lava":
			return [EMBER]
		"glade":
			return [theme.particle]
		"lantern":
			return [theme.world_accent]
		"sugar":
			return SPRINKLES
		"desert":
			return [PEBBLE]
		"neon":
			return [NEON_RING]
		"haunted":
			return [WISP]
	return []


## Points round the rim, `n` of them, as [canvas point, angle].
static func _rim(p: PortalPen, n: int, phase: float = 0.4) -> Array:
	var out := []
	for i in n:
		var a := phase + i * TAU / n
		out.append([p.rim_point(a, R + 14.0), a])
	return out


## One small touch from the world on the rim (sun ticks, leaves, ice shards...).
static func _draw_touch(p: PortalPen, theme: ThemeDef) -> void:
	var cols := touch_colors(theme)
	if cols.is_empty():
		return
	var s := p.scale
	match theme.id:
		"sunset":
			for e: Array in _rim(p, 8):
				var v: Vector2 = e[0]
				var a: float = e[1]
				p.line(v, v + Vector2(cos(a), sin(a)) * 7.0 * s, cols[0], 4.0)
		"jungle", "autumn", "meadow":
			var i := 0
			for e: Array in _rim(p, 5):
				var a: float = e[1]
				p.blob(e[0], 4.5, 9.0, a + deg_to_rad(120.0), cols[i % cols.size()])
				i += 1
		"ice":
			for e: Array in _rim(p, 5):
				var v: Vector2 = e[0]
				var a: float = e[1]
				var tri := PackedVector2Array(
					[
						v + Vector2(cos(a), sin(a)) * 10.0 * s,
						v + Vector2(cos(a + 1.7), sin(a + 1.7)) * 4.0 * s,
						v + Vector2(cos(a - 1.7), sin(a - 1.7)) * 4.0 * s,
					]
				)
				p.shape(tri, cols[0])
		"lava", "glade", "lantern":
			for e: Array in _rim(p, 6):
				p.blob(e[0], 3.5, 3.5, PI / 4.0, cols[0], 4)
		"deepsea", "cove":
			var i := 0
			for e: Array in _rim(p, 6):
				var r := 3.0 + (i % 3) * 1.5
				p.ring(e[0], r, r, cols[0], 2.0, 16)
				i += 1
		"sugar":
			var i := 0
			for e: Array in _rim(p, 8):
				var v: Vector2 = e[0]
				var d := Vector2.from_angle(deg_to_rad(i * 67.0)) * 2.5 * s
				p.line(v - d, v + d, cols[i % cols.size()], 3.0)
				i += 1
		"star", "aurora":
			for e: Array in _rim(p, 5):
				p.shape(_star(e[0], 5.0 * s, 2.0 * s), cols[0])
		"desert":
			var i := 0
			for e: Array in _rim(p, 6):
				p.blob(e[0], 3.0 + i % 2, 2.4 + i % 2, 0.0, cols[0], 12)
				i += 1
		"blossom", "clouds":
			for e: Array in _rim(p, 6):
				var a: float = e[1]
				p.blob(e[0], 5.0, 3.0, a, cols[0])
		"neon":
			p.ring(p.origin, (R + 12.0) * PortalPen.SQUASH, R + 12.0, cols[0], 3.5, 40)
		"haunted":
			for e: Array in _rim(p, 4):
				var v: Vector2 = e[0]
				var a: float = e[1]
				var ctrl := v + Vector2(cos(a) * 8.0, sin(a) * 8.0 - 6.0) * s
				var end := v + Vector2(cos(a) * 14.0, sin(a) * 4.0) * s
				var pts := PackedVector2Array()
				for k in 7:
					var t := k / 6.0
					pts.append(v.lerp(ctrl, t).lerp(ctrl.lerp(end, t), t))
				p.polyline(pts, cols[0], 3.0)
		"winterfest":
			for e: Array in _rim(p, 5):
				var v: Vector2 = e[0]
				for b: float in [0.0, 1.047, 2.094]:
					var d := Vector2(cos(b), sin(b)) * 5.0 * s
					p.line(v + d, v - d, cols[0], 2.0)


## A five-point star round `c` (canvas units).
static func _star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var r := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
