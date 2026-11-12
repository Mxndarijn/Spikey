extends HazardPainter
## Drop (Spike Rain; "pinecone" in Orchard Drop, "icicle" in Winter Icicle
## Drop). While warning: the drop swells out of the ceiling on a thin neck,
## trembles, stretches and drips off, with a faint dotted line down its column
## (the pinecone keeps a dark mark, the icicle shakes instead). While falling:
## the deadly drop in the spike colour. Spike Rain's variants add the band a
## wobbling drop can reach, two floor shards and a floor spike that grows.

const DropHazard := preload("res://sim/hazards/drop.gd")

const LENGTH := 26.0
## The floor row as RoomView draws it: spikes stand on the band, this deep.
const FLOOR_BASE_Y := SimConfig.WORLD_H / float(SimConfig.SUB) - RoomView.BAND
const DOT_GAP := 12.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as DropHazard
	var theme := look.theme
	var time := look.time
	var r := HazardLayer.px(h.radius)
	if h.shard_t > 0:
		_shards(c, h, look)
	if h.staked():
		var age := DropHazard.STAKE_STEPS - h.timer
		var pop := 0.0
		if age >= DropHazard.STAKE_GROW and age < DropHazard.STAKE_GROW + 8:
			pop = 6.0 * sin(PI * (age - DropHazard.STAKE_GROW) / 8.0)
		var grown := HazardLayer.px(h.stake_height()) + pop
		_floor_spike(c, h, look, grown, HazardLayer.px(h.stake_half_base()), 0.0)
		return
	if h.warning():
		var k: float = h.warn_progress() / float(SimTrig.ONE)
		var top := HazardLayer.px(SimConfig.KILL_TOP)
		var x := HazardLayer.px(h.x)
		match look.skin:
			"icicle":
				_icicle_forming(c, x, top, r, k, look)
			"pinecone":
				_mark(c, x, top, r, k, theme)
			_:
				_drip(c, h, look, x, top, r, k)
		return
	if not h.falling():
		return
	var p := HazardLayer.at(h.x, h.y)
	match look.skin:
		"icicle":
			_icicle(c, p, r, look)
		"pinecone":
			_pinecone(c, p, r, theme, time)
		_:
			_spike_drop(c, p, r, theme)


## The drop forming on the ceiling. It is visible from the first frame of the
## warning (at 55% size), full size by 60%, trembles from 45% and lets go over
## the last 30%. A faint dotted line shows the column it will fall down.
func _drip(
	c: CanvasItem, h: DropHazard, look: HazardLook, x: float, top: float, r: float, k: float
) -> void:
	var theme := look.theme
	var time := look.time
	var path := Color(theme.spike, 0.28 * minf(1.0, k * 4.0))
	if h.style == DropHazard.Style.WOBBLE:
		var half := r + HazardLayer.px(DropHazard.SWAY)
		var bottom := HazardLayer.px(SimConfig.KILL_BOTTOM)
		var band := Color(theme.spike, 0.08 * minf(1.0, k * 4.0))
		c.draw_rect(Rect2(x - half, top, half * 2.0, bottom - top), band)
	var y0 := top + r * 2.0 + fmod(time * 40.0, DOT_GAP)
	var floor_y := HazardLayer.px(SimConfig.KILL_BOTTOM)
	while y0 < floor_y:
		c.draw_line(Vector2(x, y0), Vector2(x, minf(y0 + 3.0, floor_y)), path, 2.0, true)
		y0 += DOT_GAP
	if h.style == DropHazard.Style.STAKE:
		# The floor spike it will land on starts to stir.
		var stir := sin(time * 60.0) * 1.2 * maxf(0.0, (k - 0.4) / 0.6)
		_floor_spike(c, h, look, 3.0 * k, HazardLayer.px(DropHazard.FLOOR_SPIKE_W) / 2.0, stir)

	var grow := 0.55 + 0.45 * minf(1.0, k / 0.6)
	var stretch := (k - 0.7) / 0.3 if k > 0.7 else 0.0
	var tremble := 0.0
	if k > 0.45:
		tremble = sin(time * 55.0) * 1.6 * minf(1.0, (k - 0.45) / 0.3)
	if h.style == DropHazard.Style.WOBBLE:
		tremble += sin(time * 9.0) * 6.0 * k
	var rr := r * grow
	var cx := x + tremble
	var cy := top - rr * 0.2 + stretch * rr * 0.6
	# The neck that holds it to the ceiling thins as it lets go.
	var neck := rr * 0.9 * (1.0 - 0.75 * stretch)
	var pts := PackedVector2Array(
		[
			Vector2(x - neck * 1.4, 0.0),
			Vector2(x + neck * 1.4, 0.0),
			Vector2(cx + neck * 0.5, cy - rr * 0.6),
			Vector2(cx - neck * 0.5, cy - rr * 0.6),
		]
	)
	c.draw_colored_polygon(pts, theme.spike)
	c.draw_set_transform(Vector2(cx, cy), 0.0, Vector2(1.0 - 0.15 * stretch, 1.0 + 0.25 * stretch))
	_spike_drop(c, Vector2.ZERO, rr, theme)
	c.draw_set_transform(Vector2.ZERO)


## The pinecone's warning: a faint column and a dark mark hanging from the ceiling.
static func _mark(c: CanvasItem, x: float, top: float, r: float, k: float, theme: ThemeDef) -> void:
	c.draw_line(
		Vector2(x, top), Vector2(x, top + 160.0 * k), Color(theme.spike, 0.12), r * 2.0, true
	)
	var mark := Rect2(x - r, top - 4.0, r * 2.0, 6.0 + 8.0 * k)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(theme.spike, 0.35 + 0.5 * k)
	box.set_corner_radius_all(4)
	box.anti_aliasing = true
	box.draw(c.get_canvas_item(), mark)


## Stake: the floor spike under the drop, drawn over RoomView's own one,
## `extra` px taller and `half` px half-wide, its tip moved `stir` px sideways.
static func _floor_spike(
	c: CanvasItem, h: DropHazard, look: HazardLook, extra: float, half: float, stir: float
) -> void:
	var base := Vector2(HazardLayer.px(h.base_x), FLOOR_BASE_Y)
	var depth := RoomView.EDGE_SPIKE_DEPTH + extra
	var dir := Vector2(stir / depth, -1.0).normalized()
	var pen := ScenePen.new(c)
	var pts := RoomView.spike_points(base, dir, half, depth)
	pen.fill(pts, look.theme.spike)
	var lit := RoomView.INK_SPIKE_EDGE if look.ink else look.theme.spike_edge
	pen.fill(RoomView.spike_lit_points(base, dir, half, depth), lit)
	if look.ink:
		pen.stroke(pts, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W)


## Shatter: two small spiked shards skipping apart along the floor.
static func _shards(c: CanvasItem, h: DropHazard, look: HazardLook) -> void:
	var r := HazardLayer.px(DropHazard.SHARD_RADIUS)
	var y := HazardLayer.px(h.shard_y)
	var spin := HazardLayer.px(h.shard_dx) * 0.08
	for side in [-1.0, 1.0]:
		var p := Vector2(HazardLayer.px(h.shard_x) + side * HazardLayer.px(h.shard_dx), y)
		var pts := PackedVector2Array()
		for i in 3:
			var a: float = side * spin + TAU * i / 3.0 - PI / 2.0
			pts.append(p + Vector2(cos(a), sin(a)) * r * 1.3)
		c.draw_colored_polygon(pts, look.theme.spike)
		pts.append(pts[0])
		if look.ink:
			c.draw_polyline(pts, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W, true)
		else:
			c.draw_polyline(pts, look.theme.spike_edge, 1.5, true)


## A teardrop pointing down, with a lighter edge.
static func _spike_drop(c: CanvasItem, p: Vector2, r: float, theme: ThemeDef) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI * i / 12.0
		pts.append(p + Vector2(cos(a) * r, -sin(a) * r * 0.9))
	pts.append(p + Vector2(0, r * 1.6))
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike, 1.0, true)
	c.draw_arc(p, r * 0.6, PI * 1.15, PI * 1.6, 8, Color(theme.spike_edge, 0.8), 2.0, true)


## A falling icicle: a two-tone rounded spike like the room's own, pointing
## down from its top at `p.y - r` (its hitbox is the circle at `p`).
static func _icicle(c: CanvasItem, p: Vector2, r: float, look: HazardLook) -> void:
	var base := Vector2(p.x, p.y - r)
	RoomView.paint_spike(c, base, Vector2(0, 1), r, LENGTH * 1.4, look.theme, look.ink)


## The icicle forming, the way Spike Rain's drops form: it grows out of the
## ceiling band (55% long at once, full by 60% of the warning), trembles from
## 45% and lets go over the last 30%, ending where the falling icicle starts.
static func _icicle_forming(
	c: CanvasItem, x: float, top: float, r: float, k: float, look: HazardLook
) -> void:
	var grow := 0.55 + 0.45 * minf(1.0, k / 0.6)
	var stretch := (k - 0.7) / 0.3 if k > 0.7 else 0.0
	var tremble := 0.0
	if k > 0.45:
		tremble = sin(look.time * 55.0) * 1.2 * minf(1.0, (k - 0.45) / 0.3)
	var length := LENGTH * 1.4
	var tip := top + length * grow
	# Hanging from the band, then its base drops to the ceiling line as it lets go.
	var base_y := lerpf(RoomView.BAND, top, stretch)
	var base := Vector2(x + tremble, base_y)
	var half := r * (0.7 + 0.3 * grow)
	RoomView.paint_spike(c, base, Vector2(0, 1), half, tip - base_y, look.theme, look.ink)


static func _pinecone(c: CanvasItem, p: Vector2, r: float, theme: ThemeDef, time: float) -> void:
	var spin := sin(time * 6.0) * 0.25
	c.draw_set_transform(p, spin, Vector2(1.0, 1.3))
	# Thorns around an oval body.
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		var rr := r * (1.25 if i % 2 == 0 else 0.95)
		pts.append(Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, theme.spike)
	pts.append(pts[0])
	c.draw_polyline(pts, theme.spike, 1.0, true)
	# Scales.
	for row in 3:
		var y := (row - 1) * r * 0.5
		c.draw_arc(
			Vector2(0, y), r * 0.55, 0.2, PI - 0.2, 8, Color(theme.spike_edge, 0.7), 1.5, true
		)
	c.draw_set_transform(Vector2.ZERO)
