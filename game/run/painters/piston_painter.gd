extends HazardPainter
## Piston (Piston Press), the hazard-lane look: a banded housing in the wall.
## While it warns, the ram's whole lane (its row from the wall to its reach,
## the box it will kill in) fills with diagonal stripes in spike colour that
## scroll into the room and speed up as the slam nears, edged top and bottom
## with a stop bar at the reach. Out, the ram is a striped rod in spike colour
## with a toothed nose, drawn exactly as far as it kills; a puff of dust
## marks the hit. Reads only side, y, reach, glow() and extent().

const PistonHazard := preload("res://sim/hazards/piston.gd")

const HOUSING_W := 14.0
const HOUSING_HALF := 26.0
const BAND := 4.0
const TEETH := 3
const NOSE := 12.0
const STRIPE_STEP := 16.0
const STRIPE_W := 7.0
## Stripe scroll, px per second, at the start and the end of the warning.
const SCROLL_SLOW := 40.0
const SCROLL_FAST := 220.0
const EDGE := 2.0
const STOP := 3.0
## The dust after a hit: seconds it lasts.
const DUST_TIME := 0.25

## When each ram (by instance id) got fully out, in look.time seconds: the dust's clock.
var _hit_at := {}


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as PistonHazard
	var theme := look.theme
	var y := HazardLayer.px(h.y)
	var half := HazardLayer.px(h.HALF_H)
	var base := HazardLayer.px(h.base_x())
	var reach := HazardLayer.px(h.reach)
	var dir := 1.0 if h.side == 0 else -1.0
	_housing(c, theme, base, dir, y)
	var glow: float = h.glow() / float(SimTrig.ONE)
	if glow > 0.0:
		_lane(c, theme, base, dir, reach, y, half, glow, look.time)
	var ext := HazardLayer.px(h.extent())
	if ext > 0.0:
		_ram(c, look, base, dir, ext, y, half)
	_dust(c, h, theme, look.time, base + dir * reach, dir, y, half, ext >= reach)


## The warning: the ram's lane, wall to reach (the box it will kill in), striped
## and edged.
func _lane(
	c: CanvasItem,
	theme: ThemeDef,
	base: float,
	dir: float,
	reach: float,
	y: float,
	half: float,
	glow: float,
	time: float
) -> void:
	var x0 := base
	var x1 := base + dir * reach
	var lane := Rect2(minf(x0, x1), y - half, absf(x1 - x0), half * 2.0)
	# The scroll speeds up through the warning (its distance is the integral).
	var speed := SCROLL_SLOW + (SCROLL_FAST - SCROLL_SLOW) * glow
	var off := fposmod(time * speed, STRIPE_STEP)
	_stripes(c, lane, dir, off, Color(theme.spike, 0.22 + 0.5 * glow))
	c.draw_rect(Rect2(lane.position.x, y - half, lane.size.x, EDGE), theme.spike, true)
	c.draw_rect(Rect2(lane.position.x, y + half - EDGE, lane.size.x, EDGE), theme.spike, true)
	var stop_x := x1 - STOP if dir > 0.0 else x1
	c.draw_rect(Rect2(stop_x, y - half, STOP, half * 2.0), theme.spike, true)


## Diagonal stripes clipped to `box`, moved `off` px into the room.
static func _stripes(c: CanvasItem, box: Rect2, dir: float, off: float, color: Color) -> void:
	var h := box.size.y
	var x := box.position.x - h - STRIPE_STEP + (off if dir > 0.0 else -off)
	while x < box.end.x:
		var pts := PackedVector2Array(
			[
				Vector2(x, box.end.y),
				Vector2(x + STRIPE_W, box.end.y),
				Vector2(x + STRIPE_W + h, box.position.y),
				Vector2(x + h, box.position.y),
			]
		)
		var clipped := Geometry2D.intersect_polygons(pts, _rect_points(box))
		for poly in clipped:
			c.draw_colored_polygon(poly, color)
		x += STRIPE_STEP


static func _rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	)


## The ram: exactly the box it kills in, a striped rod and a toothed nose.
func _ram(
	c: CanvasItem, look: HazardLook, base: float, dir: float, ext: float, y: float, half: float
) -> void:
	var theme := look.theme
	var tip := base + dir * ext
	var nose_x := tip - dir * minf(NOSE, ext)
	# The rod is as tall as the ram's hitbox (the sim kills over the whole
	# HALF_H band), so nothing deadly sticks out beside a thinner drawing.
	var body := Rect2(minf(base, nose_x), y - half, absf(nose_x - base), half * 2.0)
	if body.size.x > 0.5:
		HazardLayer.rock_box(c, body, look)
		var inner := Rect2(body.position.x, y - half + 3.0, body.size.x, half * 2.0 - 6.0)
		_stripes(c, inner, dir, fposmod(ext, STRIPE_STEP), Color(theme.spike_edge, 0.55))
	var head := Rect2(minf(nose_x, nose_x - dir * 6.0), y - half, 6.0, half * 2.0)
	c.draw_rect(head, theme.spike, true)
	var tooth_h := half * 2.0 / TEETH
	for i in TEETH:
		var ty := y - half + tooth_h * i
		var pts := PackedVector2Array(
			[Vector2(nose_x, ty), Vector2(tip, ty + tooth_h / 2.0), Vector2(nose_x, ty + tooth_h)]
		)
		c.draw_colored_polygon(pts, theme.spike)
		pts.append(pts[0])
		var edge := HazardLayer.INK_EDGE if look.ink else theme.spike
		c.draw_polyline(pts, edge, 1.0, true)


## A puff of dust above and below the tip just after it hits (looks only).
func _dust(
	c: CanvasItem,
	h: Hazard,
	theme: ThemeDef,
	time: float,
	tip: float,
	dir: float,
	y: float,
	half: float,
	out: bool
) -> void:
	var key := h.get_instance_id()
	if not out:
		_hit_at.erase(key)
		return
	if not _hit_at.has(key):
		_hit_at[key] = time
	var k := (time - float(_hit_at[key])) / DUST_TIME
	if k < 0.0 or k >= 1.0:
		return
	var puff := theme.particle if theme.night else theme.paper
	for sgn: float in [-1.0, 1.0]:
		for i in 3:
			var p := Vector2(
				tip - dir * 4.0 + dir * (i * 7.0 * k + i * 2.0),
				y + sgn * (half + 3.0 + 10.0 * k + i * 3.0)
			)
			c.draw_circle(p, 2.5 + 4.0 * k - i * 0.5, Color(puff, 0.9 * (1.0 - k)))


## The housing in the wall (safe, part of the wall), under the lane and the ram
## so the whole deadly box shows, right up to the wall.
func _housing(c: CanvasItem, theme: ThemeDef, base: float, dir: float, y: float) -> void:
	var hx := base if dir > 0.0 else base - HOUSING_W
	var plate := StyleBoxFlat.new()
	plate.bg_color = theme.world_accent
	plate.set_corner_radius_all(2)
	plate.anti_aliasing = true
	plate.draw(c.get_canvas_item(), Rect2(hx, y - HOUSING_HALF, HOUSING_W, HOUSING_HALF * 2.0))
	var band := Color(theme.spike, 0.5)
	c.draw_rect(Rect2(hx, y - HOUSING_HALF, HOUSING_W, BAND), band, true)
	c.draw_rect(Rect2(hx, y + HOUSING_HALF - BAND, HOUSING_W, BAND), band, true)
