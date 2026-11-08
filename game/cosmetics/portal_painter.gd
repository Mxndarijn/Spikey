class_name PortalPainter
extends RefCounted
## Draws an exit portal (any PortalStyle kind) onto a CanvasItem: in the room
## and in the shop pictures, so both always look the same. Call only from that
## item's _draw(). Safe, so never in the world's spike colour.
##
## A new portal kind is one `_draw_<kind>` function here plus its line in
## paint(). Each draws with a Pen (the portal's own units, mirrored per wall)
## and gets how open it is (0..1, a little more while opening), the time and
## the colour.

## The sizes are tuned on the game's exit: half height 48 px (SimConfig.EXIT_HALF).
const REF_HALF := 48.0
## Portal half-width over half-height.
const RX_RATIO := 22.0 / 48.0
## Shop pictures: the portal's half-height as a share of the room's height,
## its gap from the right edge, and the fixed moment they show.
const THUMB_HEIGHT := 0.3
const THUMB_INSET := 4.0
const THUMB_TIME := 0.8

static var _bloom: GradientTexture2D


## `side`: 0 on the left wall (opens to the right), 1 on the right wall.
static func paint(
	ci: CanvasItem,
	style: PortalStyle,
	center: Vector2,
	half_height: float,
	side: int,
	open_amount: float,
	time: float,
	color: Color,
	alpha: float = 1.0
) -> void:
	if style == null or open_amount <= 0.0 or half_height <= 0.0:
		return
	var p := PortalPen.new(ci, center, half_height, 1.0 if side == 0 else -1.0, alpha)
	var o := clampf(open_amount, 0.0, 1.15)
	match style.kind:
		PortalStyle.SPLAT:
			_draw_splat(p, o, time, color)
		PortalStyle.FEATHERS:
			_draw_feathers(p, o, time, color)
		PortalStyle.CRACK:
			_draw_crack(p, o, time, color)
		PortalStyle.RIPPLE:
			_draw_ripple(p, o, time, color)
		_:
			_draw_cloud(p, o, time, color)


static func _light(c: Color, f: float) -> Color:
	return c.lerp(Color.WHITE, f)


static func _dark(c: Color, f: float) -> Color:
	return c.lerp(UiTokens.INK_900, f)


## Cloud Hole: a ring of puffy clouds round a hole of deep sky with stars,
## slowly drifting round.
static func _draw_cloud(p: PortalPen, o: float, time: float, color: Color) -> void:
	var ry := PortalPen.HALF * o
	var rx := 15.0 * o
	var cx := -6.0
	p.glow(cx, 0.0, ry * 1.6, color, 0.3)
	# The hole: lighter in the middle, deep at the edge (a fan of triangles so
	# the colours blend).
	var rim := p.ellipse(cx, 0.0, rx, ry, 32)
	var mid := p.at(cx, 0.0)
	var inner := p.col(_light(color, 0.3))
	var outer := p.col(_dark(color, 0.55))
	for i in rim.size():
		var b := rim[(i + 1) % rim.size()]
		p.ci.draw_polygon(
			PackedVector2Array([mid, rim[i], b]), PackedColorArray([inner, outer, outer])
		)
	for i in 5:
		var a := time * 0.7 + i * 1.3
		p.disc(cx + cos(a) * rx * 0.5, sin(a * 1.3) * ry * 0.6, 1.2, Color.WHITE)
	var puffs := 11
	for i in puffs:
		var a := time * 0.35 + i * TAU / puffs
		var r := 6.0 + 2.0 * sin(i * 2.7 + time)
		var x := cx + cos(a) * (rx + 3.0)
		var y := sin(a) * (ry + 3.0)
		p.disc(x, y + 1.5, r, Color(UiTokens.INK_900, 0.25))
		p.disc(x, y, r, Color.WHITE)


## Ink Splat: a wobbly ink blot with drips running down; its glowing middle
## is the way through.
static func _draw_splat(p: PortalPen, o: float, time: float, color: Color) -> void:
	var r0 := PortalPen.HALF * o
	p.fill(_blob(p, r0, time), UiTokens.INK_900)
	for i in 3:
		var f := fposmod(time * 0.45 + i / 3.0, 1.0)
		var drip := Color(UiTokens.INK_900, 1.0 - f)
		p.disc(-8.0 + (i - 1) * 7.0, r0 * 0.7 + f * 30.0, 3.2 - f * 1.5, drip)
	p.fill(_blob(p, r0 * 0.62, time), color)
	p.glow(-8.0, 0.0, r0 * 0.6, _light(color, 0.7), 0.9)


static func _blob(p: PortalPen, r: float, time: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var k := r * (0.82 + 0.12 * sin(5.0 * a + time * 1.6) + 0.07 * sin(9.0 * a - time * 2.3))
		pts.append(p.at(-8.0 + cos(a) * k * 0.75, sin(a) * k))
	return pts


## Feather Ring: a wreath of feathers turning round a bright core.
static func _draw_feathers(p: PortalPen, o: float, time: float, color: Color) -> void:
	var ry := PortalPen.HALF * o
	var rx := 14.0 * o
	var cx := -8.0
	p.glow(cx, 0.0, ry * 1.7, color, 0.6)
	p.disc(cx, 0.0, ry * 0.42, _light(color, 0.85))
	var count := 10
	var spin := time * 1.1
	for i in count:
		var a := spin + i * TAU / count
		var x := cx + cos(a) * rx * o
		var y := sin(a) * ry
		# Along the ring, tilted a little, like a wreath.
		var rot := atan2(sin(a) * ry, cos(a) * rx) + PI / 2.0 + 0.5
		var feather := p.ellipse(x, y, 4.0 * o, 11.0 * o, 16, rot)
		p.fill(feather, color if i % 2 else Color.WHITE)
		p.outline(feather, UiTokens.INK_900, 1.5)
		var tip := Vector2(0.0, -10.0 * o).rotated(rot)
		p.line(x + tip.x, y + tip.y, x - tip.x, y - tip.y, UiTokens.INK_900, 1.5)


## Breakout Crack: the wall cracks open with light blasting through, and
## chips of wall fall away.
static func _draw_crack(p: PortalPen, o: float, time: float, color: Color) -> void:
	var h := PortalPen.HALF * (0.3 + 0.7 * o)
	var jag: Array[float] = [0.0, 6.0, -3.0, 8.0, -1.0, 7.0, -4.0, 5.0, 0.0]
	var n := jag.size()
	p.glow(-4.0, 0.0, h * 1.9, _light(color, 0.4), 0.7 * minf(o, 1.0))
	var pts := PackedVector2Array()
	for i in n:
		var y := -h + 2.0 * h * i / (n - 1)
		var w := (5.0 + jag[i]) * o * sin(PI * i / (n - 1)) + 0.5
		pts.append(p.at(-w - 2.0, y))
	for i in range(n - 1, -1, -1):
		pts.append(p.at(1.0, -h + 2.0 * h * i / (n - 1)))
	p.fill(pts, _light(color, 0.8))
	p.outline(pts, UiTokens.INK_900, 2.5)
	p.line(-6.0, -h * 0.4, -14.0 * o, -h * 0.6, UiTokens.INK_900, 2.0)
	p.line(-7.0, h * 0.25, -15.0 * o, h * 0.45, UiTokens.INK_900, 2.0)
	for i in 4:
		var f := fposmod(time * 0.6 + i / 4.0, 1.0)
		var x := -6.0 - i * 3.0 - f * 10.0
		var y := -h * 0.3 + i * 10.0 + f * f * 60.0
		var chip := p.ellipse(x, y, 3.5, 3.5, 4, f * 5.0 + i)
		p.fill(chip, Color(color.darkened(0.55), 1.0 - f))


## Ripple Mirror: an upright pool of light with rings rippling outward.
static func _draw_ripple(p: PortalPen, o: float, time: float, color: Color) -> void:
	var ry := PortalPen.HALF * o
	var rx := 11.0 * o
	var cx := -6.0
	p.glow(cx, 0.0, ry * 1.7, color, 0.55)
	var pts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in 36:
		var a := TAU * i / 36.0
		var k := 1.0 + 0.05 * sin(6.0 * a + time * 4.0)
		var x := cos(a) * rx * k
		pts.append(p.at(cx + x, sin(a) * ry * k))
		# Lighter on the room side (-x in Pen units).
		var f := clampf(0.5 - x / maxf(rx * 2.0, 0.001), 0.0, 1.0)
		colors.append(p.col(_dark(color, 0.2).lerp(_light(color, 0.55), f)))
	if pts.size() >= 3:
		p.ci.draw_polygon(pts, colors)
	p.outline(pts, UiTokens.INK_900, 2.5)
	for i in 3:
		var f := fposmod(time * 0.9 + i / 3.0, 1.0)
		var ring := p.ellipse(cx, 0.0, rx * f * 0.9 + 1.0, ry * f * 0.9 + 1.0, 28)
		p.outline(ring, Color(Color.WHITE, 0.85 * (1.0 - f)), 2.0)


static func _fade(color: Color, a: float) -> Color:
	return Color(color, color.a * a)


static func _soft(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	ci.draw_texture_rect(bloom_texture(), Rect2(center - radii, radii * 2.0), false, color)


## A soft white bloom, tinted per use (the same falloff as the room's glow).
static func bloom_texture() -> GradientTexture2D:
	if _bloom == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray(
			[
				Color(1, 1, 1, UiTokens.OPACITY_GLOW_INNER),
				Color(1, 1, 1, UiTokens.OPACITY_GLOW_OUTER),
				Color(1, 1, 1, 0),
			]
		)
		_bloom = GradientTexture2D.new()
		_bloom.gradient = g
		_bloom.fill = GradientTexture2D.FILL_RADIAL
		_bloom.fill_from = Vector2(0.5, 0.5)
		_bloom.fill_to = Vector2(1.0, 0.5)
		_bloom.width = 128
		_bloom.height = 128
	return _bloom
