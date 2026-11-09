class_name PlatePainter
extends RefCounted
## Draws a name plate (any PlateStyle) into a pill-shaped rect on a CanvasItem:
## behind a leaderboard row and in the shop pictures, so both always look the
## same. Call only from that item's _draw().
##
## Scenes are laid out on a design row DESIGN_H px tall and scaled to the rect's
## height. Things on the left keep their distance from the left end, things on
## the right from the right end, so a row of any width works. Everything is
## cut to the pill. A new scene is one `_<scene>` function plus its line in
## paint().

## The design row (the mockup board): 576 x 88.
const DESIGN_W := 576.0
const DESIGN_H := 88.0
const GOLD := Color("#FFC93C")
const INK := Color("#231A33")
const WHITE := Color("#FFFFFF")
const SUNSET_SUN := Color("#FFDDB0")
const SUNSET_FAR := Color("#FF8F74")
const SUNSET_NEAR := Color("#E8745F")
const SUNSET_TREE := Color("#C9553B")
const SUNSET_TRUNK := Color("#B3543A")
const JUNGLE_FAR := Color("#8FD67A")
const JUNGLE_NEAR := Color("#4E9A3A")
const JUNGLE_TREE := Color("#3F8F4E")
const ICE_FLOOR := Color("#CFEAFB")
const ICE_LIGHT := Color("#A9DDF7")
const ICE_DEEP := Color("#7FC4EA")
const LAVA_FAR := Color("#FF8A5C")
const LAVA_NEAR := Color("#C9553B")
const LAVA_CONE := Color("#B3543A")
const LAVA_GLOW := Color("#FFD23F")
const SEA_FAR := Color("#3FC1D2")
const SEA_NEAR := Color("#1FA3B8")
const SEA_CORAL := Color("#FF7A8A")
const SUGAR_FAR := Color("#FFBBD6")
const SUGAR_NEAR := Color("#FF8FC0")
const SUGAR_BLUE := Color("#5CC8FF")
const SUGAR_LILAC := Color("#B69CFF")
const SUGAR_YELLOW := Color("#FFE45C")
const STAR_HILL := Color("#3B2C8F")
const STAR_MOON := Color("#C9C2F2")
const STAR_CYAN := Color("#7DE2FF")
const ROYAL_GEM := Color("#E8483F")


## Where things go on one plate: the rect, its scale, the pill to cut to.
class Pen:
	extends RefCounted
	var ci: CanvasItem
	var rect: Rect2
	var k := 1.0
	var alpha := 1.0
	var frame: PackedVector2Array

	## A point `x` design px from the left end.
	func left(x: float, y: float) -> Vector2:
		return rect.position + Vector2(x, y) * k

	## A point as far from the right end as design x is from DESIGN_W.
	func right(x: float, y: float) -> Vector2:
		return Vector2(rect.end.x - (DESIGN_W - x) * k, rect.position.y + y * k)

	## Fills a polygon, cut to the pill.
	func fill(pts: PackedVector2Array, color: Color) -> void:
		for part in Geometry2D.intersect_polygons(pts, frame):
			if part.size() >= 3 and absf(PlatePainter.area(part)) > 0.5:
				ci.draw_colored_polygon(part, Color(color, color.a * alpha))

	func disc(c: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array()
		for i in 20:
			pts.append(c + Vector2.from_angle(TAU * i / 20.0) * r * k)
		fill(pts, color)

	func box(at: Vector2, w: float, h: float, color: Color) -> void:
		var s := Vector2(w, h) * k
		fill(PackedVector2Array([at, at + Vector2(s.x, 0), at + s, at + Vector2(0, s.y)]), color)

	## A triangle standing on `foot` (its base centre), `w` wide and `h` tall.
	func peak(foot: Vector2, w: float, h: float, color: Color) -> void:
		fill(
			PackedVector2Array(
				[
					foot + Vector2(-w * 0.5, 0) * k,
					foot + Vector2(0, -h) * k,
					foot + Vector2(w * 0.5, 0) * k
				]
			),
			color
		)

	## A rolling hill across the whole plate: its top waves round `base` design px.
	func hill(base: float, amp: float, phase: float, color: Color) -> void:
		var pts := PackedVector2Array()
		var steps := 24
		for i in steps + 1:
			var u := float(i) / steps
			var y := base + amp * sin(u * TAU * 1.5 + phase)
			pts.append(Vector2(lerpf(rect.position.x - 1.0, rect.end.x + 1.0, u), left(0, y).y))
		pts.append(rect.end + Vector2(1, 1))
		pts.append(Vector2(rect.position.x - 1.0, rect.end.y + 1.0))
		fill(pts, color)


## Draws the plate into `rect` (a pill: fully round ends). Paper draws nothing
## unless `with_base` (the shop pictures show its plain pill too).
static func paint(
	ci: CanvasItem, rect: Rect2, style: PlateStyle, alpha: float = 1.0, with_base: bool = false
) -> void:
	# A pill needs to be wider than it is tall (its two round ends must not meet).
	if style == null or rect.size.y < 4.0 or rect.size.x < rect.size.y + 2.0:
		return
	if style.is_plain() and not with_base:
		return
	var pen := Pen.new()
	pen.ci = ci
	pen.rect = rect
	pen.k = rect.size.y / DESIGN_H
	pen.alpha = alpha
	pen.frame = pill(rect)
	ci.draw_colored_polygon(pen.frame, Color(style.base, alpha))
	match style.scene:
		PlateStyle.SUNSET:
			_sunset(pen)
		PlateStyle.JUNGLE:
			_jungle(pen)
		PlateStyle.ICE:
			_ice(pen)
		PlateStyle.LAVA:
			_lava(pen)
		PlateStyle.DEEPSEA:
			_deepsea(pen)
		PlateStyle.SUGAR:
			_sugar(pen)
		PlateStyle.STAR:
			_star(pen)
		PlateStyle.FINISH:
			_finish(pen)
		PlateStyle.ROYAL:
			_royal(pen)


## A gold ring just inside the pill: the player's own row, on top of its plate.
static func ring(ci: CanvasItem, rect: Rect2, width: float = 3.0) -> void:
	var pts := pill(rect.grow(-width * 0.5))
	pts.append(pts[0])
	ci.draw_polyline(pts, GOLD, width, true)


## The pill's outline: a rect with fully round ends.
static func pill(rect: Rect2) -> PackedVector2Array:
	var r := minf(rect.size.y, rect.size.x) * 0.5 - 0.01
	var pts := PackedVector2Array()
	var steps := 12
	var right := Vector2(rect.end.x - r, rect.position.y + rect.size.y * 0.5)
	var left := Vector2(rect.position.x + r, rect.position.y + rect.size.y * 0.5)
	for i in steps + 1:
		pts.append(right + Vector2.from_angle(-PI / 2.0 + PI * i / steps) * r)
	for i in steps + 1:
		pts.append(left + Vector2.from_angle(PI / 2.0 + PI * i / steps) * r)
	return pts


## Signed area of a polygon.
static func area(pts: PackedVector2Array) -> float:
	var sum := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * 0.5


static func _sunset(p: Pen) -> void:
	p.disc(p.right(440, 66), 26, SUNSET_SUN)
	p.hill(68, 7, 0.0, SUNSET_FAR)
	for at: Vector2 in [p.left(100, 76), p.left(118, 78), p.right(520, 74)]:
		p.box(at + Vector2(-1, -10) * p.k, 2, 10, SUNSET_TRUNK)
		p.disc(at + Vector2(0, -12) * p.k, 6, SUNSET_TREE)
	p.hill(80, 4, 1.2, SUNSET_NEAR)


static func _jungle(p: Pen) -> void:
	p.hill(68, 7, 0.0, JUNGLE_FAR)
	for at: Vector2 in [p.left(100, 70), p.left(115, 72), p.right(508, 74)]:
		p.peak(at, 16, 22, JUNGLE_TREE)
	p.peak(p.right(424, 76), 12, 14, JUNGLE_TREE)
	p.hill(80, 4, 1.2, JUNGLE_NEAR)
	p.disc(p.right(456, 78), 3, GOLD)
	p.disc(p.left(226, 82), 3, GOLD)


static func _ice(p: Pen) -> void:
	p.hill(78, 4, 0.6, ICE_FLOOR)
	p.peak(p.left(106, 90), 44, 36, ICE_LIGHT)
	p.peak(p.left(133, 90), 34, 26, ICE_DEEP)
	p.peak(p.right(458, 90), 52, 40, ICE_LIGHT)
	p.peak(p.right(493, 90), 42, 28, ICE_DEEP)
	p.peak(p.right(538, 90), 36, 24, ICE_LIGHT)


static func _lava(p: Pen) -> void:
	p.hill(68, 7, 0.0, LAVA_FAR)
	var top := p.right(450, 50)
	p.fill(
		PackedVector2Array(
			[
				top + Vector2(-54, 40) * p.k,
				top + Vector2(-12, 0) * p.k,
				top + Vector2(12, 0) * p.k,
				top + Vector2(54, 40) * p.k
			]
		),
		LAVA_CONE
	)
	p.fill(
		PackedVector2Array(
			[
				top + Vector2(-16, 4) * p.k,
				top + Vector2(-12, 0) * p.k,
				top + Vector2(12, 0) * p.k,
				top + Vector2(16, 4) * p.k,
				top + Vector2(8, 12) * p.k,
				top + Vector2(0, 7) * p.k,
				top + Vector2(-7, 13) * p.k
			]
		),
		LAVA_GLOW
	)
	p.hill(80, 4, 1.2, LAVA_NEAR)
	p.disc(p.left(110, 80), 3, LAVA_GLOW)
	p.disc(p.left(250, 85), 2.5, LAVA_GLOW)


static func _deepsea(p: Pen) -> void:
	p.hill(70, 6, 0.0, SEA_FAR)
	for at: Vector2 in [p.left(96, 68), p.right(486, 68)]:
		p.disc(at, 7, SEA_CORAL)
		p.disc(at + Vector2(11, -6) * p.k, 6, SEA_CORAL)
		p.disc(at + Vector2(20, 2) * p.k, 6, SEA_CORAL)
	p.hill(80, 4, 1.2, SEA_NEAR)
	p.disc(p.right(420, 50), 4, WHITE)
	p.disc(p.right(430, 34), 3, WHITE)
	p.disc(p.right(414, 22), 2, WHITE)


static func _sugar(p: Pen) -> void:
	p.hill(68, 7, 0.0, SUGAR_FAR)
	var pops := [[p.left(100, 74), SUGAR_BLUE], [p.right(488, 70), SUGAR_LILAC]]
	for pop: Array in pops:
		var foot: Vector2 = pop[0]
		p.box(foot + Vector2(-1.5, -18) * p.k, 3, 18, WHITE)
		p.disc(foot + Vector2(0, -22) * p.k, 9, pop[1] as Color)
		p.disc(foot + Vector2(0, -22) * p.k, 4.5, WHITE)
	p.hill(80, 4, 1.2, SUGAR_NEAR)
	p.box(p.left(150, 81), 8, 3, WHITE)
	p.box(p.left(300, 83), 8, 3, SUGAR_BLUE)
	p.box(p.right(420, 81), 8, 3, SUGAR_YELLOW)


static func _star(p: Pen) -> void:
	p.disc(p.right(430, 26), 13, STAR_MOON)
	var dots := [
		[p.left(60, 16), 2.0, WHITE],
		[p.left(150, 70), 1.5, STAR_CYAN],
		[p.left(240, 14), 2.0, WHITE],
		[p.right(320, 20), 1.5, STAR_CYAN],
		[p.right(376, 58), 2.0, WHITE],
		[p.right(486, 60), 1.5, WHITE],
		[p.right(548, 30), 2.0, STAR_CYAN],
	]
	for d: Array in dots:
		p.disc(d[0] as Vector2, float(d[1]), d[2] as Color)
	p.hill(74, 6, 0.0, STAR_HILL)
	p.box(p.left(96, 60), 10, 16, STAR_HILL)
	p.box(p.left(92, 56), 18, 6, STAR_CYAN)


## A checkered flag on each end: two columns of four squares.
static func _finish(p: Pen) -> void:
	var side := DESIGN_H / 4.0
	for row in 4:
		for col in 2:
			if (row + col) % 2 != 0:
				continue
			p.box(p.left(col * side, row * side), side, side, INK)
			p.box(p.right(DESIGN_W - (2 - col) * side, row * side), side, side, INK)


static func _royal(p: Pen) -> void:
	p.box(p.left(0, 77), p.rect.size.x / p.k, 11, GOLD)
	var c := p.right(440, 42)
	var crown := PackedVector2Array()
	for v: Vector2 in [
		Vector2(-13, 8),
		Vector2(-15, -8),
		Vector2(-7, -1),
		Vector2(0, -11),
		Vector2(7, -1),
		Vector2(15, -8),
		Vector2(13, 8),
	]:
		crown.append(c + v * 1.5 * p.k)
	p.fill(crown, GOLD)
	p.disc(c + Vector2(0, 6) * p.k, 3, ROYAL_GEM)
