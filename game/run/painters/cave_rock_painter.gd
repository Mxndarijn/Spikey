extends HazardPainter
## Cave Tunnel's rock: the ceiling rock, the floor rock and (fork) the island,
## each exactly the shape that kills (CaveRock's polylines, fangs included).
## Flat spike colour with a lighter stratum deeper in, a spike-edge rim just
## inside the edge, and the light half on every fang, as on the wall spikes.
## Nothing outside the outline is drawn in the spike colour.

const CaveRockHazard := preload("res://sim/hazards/cave_rock.gd")

## How far into the rock the lighter stratum lies, and how thick it is (px).
const STRATUM := 44.0
const STRATUM_W := 26.0
## The rim, just inside the edge.
const RIM_IN := 3.0
const RIM_W := 3.0
## A point is a fang tip when it sticks out this far past both neighbours (px).
const TIP_MIN := 6.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as CaveRockHazard
	var top := _points(h.top_x, h.top_y)
	var bottom := _points(h.bot_x, h.bot_y)
	_face(c, top, -1.0, look)
	_face(c, bottom, 1.0, look)
	if not h.isle_x.is_empty():
		_isle(c, _points(h.isle_x, h.isle_top), _points(h.isle_x, h.isle_bot), look)


static func _points(xs: PackedInt32Array, ys: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in xs.size():
		out.append(HazardLayer.at(xs[i], ys[i]))
	return out


## One rock face: `edge` left to right, the rock on side `dir` (-1 above it,
## 1 below it), filled out to the screen's edge.
static func _face(c: CanvasItem, edge: PackedVector2Array, dir: float, look: HazardLook) -> void:
	var theme := look.theme
	var far := -40.0 if dir < 0.0 else RoomView.H + 40.0
	c.draw_colored_polygon(_closed(edge, 0.0, far), theme.spike)
	# A lighter stratum deeper in: the same outline moved into the rock.
	var stratum := Color(theme.spike.lerp(theme.spike_edge, 0.16))
	var a := _shifted(edge, dir * STRATUM)
	var b := _shifted(edge, dir * (STRATUM + STRATUM_W))
	var band := PackedVector2Array(a)
	for i in range(b.size() - 1, -1, -1):
		band.append(b[i])
	c.draw_colored_polygon(band, stratum)
	# The rim just inside the edge, and the light half of each fang.
	c.draw_polyline(_shifted(edge, dir * RIM_IN), Color(theme.spike_edge, 0.85), RIM_W, true)
	for i in range(1, edge.size() - 1):
		var p := edge[i]
		var out := -dir
		var past_prev := (p.y - edge[i - 1].y) * out
		var past_next := (p.y - edge[i + 1].y) * out
		if past_prev >= TIP_MIN and past_next >= TIP_MIN:
			var mid := (edge[i - 1] + edge[i + 1]) * 0.5
			c.draw_colored_polygon(PackedVector2Array([p, mid, edge[i + 1]]), theme.spike_edge)
	if look.ink:
		c.draw_polyline(edge, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W, true)


## The island: rock between its upper and lower edges.
static func _isle(
	c: CanvasItem, upper: PackedVector2Array, lower: PackedVector2Array, look: HazardLook
) -> void:
	var theme := look.theme
	var pts := PackedVector2Array(upper)
	for i in range(lower.size() - 1, -1, -1):
		pts.append(lower[i])
	c.draw_colored_polygon(pts, theme.spike)
	c.draw_polyline(_shifted(upper, RIM_IN), Color(theme.spike_edge, 0.85), RIM_W, true)
	if look.ink:
		var ring := PackedVector2Array(pts)
		ring.append(pts[0])
		c.draw_polyline(ring, HazardLayer.INK_EDGE, HazardLayer.INK_LINE_W, true)


static func _closed(edge: PackedVector2Array, _unused: float, far: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(edge[0].x - 40.0, far))
	out.append(Vector2(edge[0].x - 40.0, edge[0].y))
	out.append_array(edge)
	out.append(Vector2(edge[edge.size() - 1].x + 40.0, edge[edge.size() - 1].y))
	out.append(Vector2(edge[edge.size() - 1].x + 40.0, far))
	return out


static func _shifted(edge: PackedVector2Array, dy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in edge:
		out.append(p + Vector2(0.0, dy))
	return out
