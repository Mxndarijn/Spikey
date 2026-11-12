extends HazardPainter
## Crate Drop (and Winter Gift Stack, skin "gift"): stacked crates and the ones
## falling, in spike colour with lighter planks; a pulsing marker under the
## ceiling shows where the next crate (or pair) falls. Gift stacks carry a
## coin on top.
##
## Landing: the floor spikes under a stack ride up on top of it. When a crate
## lands, the stack settles one spike depth down onto the floor band over
## SINK_TIME (with a dust puff), squashing the spikes under it (RoomView asks
## floor_sink() how far each floor spike is down), while spikes push up on its
## top with their tips at the sim's stack top. Only spikes wholly under a stack
## sink: the sim kills from the stack's top to the bottom of the room over its
## width, so no safe spot appears.

const CrateDropHazard := preload("res://sim/hazards/crate_drop.gd")

const COIN := preload("res://assets/ui/coin.svg")
const COIN_SIZE := 26.0
## Seconds for the spikes under a new stack to sink.
const SINK_TIME := 0.3
## A floor spike sinks when a stack covers its base but this much (px).
const SINK_SLACK := 4.0
## Dust puffs: how long they last (s), how far they spread (px), and where
## each cloud starts across the crate's width (-1 left edge, 1 right edge).
const PUFF_TIME := 0.45
const PUFF_SPREAD := 18.0
const PUFF_AT: Array[float] = [-1.0, -0.5, 0.0, 0.5, 1.0]

## The hazard the landing state below belongs to (a new room starts fresh).
var _hazard_id := 0
## Crates per column last frame, and when each column's stack started (s).
var _heights := PackedInt32Array()
var _started := PackedFloat32Array()
## When each column's top crate landed (s): it settles from then.
var _landed := PackedFloat32Array()
## Dust puffs: [x, y, width, start time].
var _puffs: Array[PackedFloat32Array] = []
var _now := 0.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as CrateDropHazard
	var theme := look.theme
	var time := look.time
	_track_landings(h, time)
	var w := HazardLayer.px(h.crate_w)
	var ch := HazardLayer.px(h.crate_h)
	var gift := h.gifts
	var floor_y := HazardLayer.px(h.FLOOR)
	for col in h.cols:
		var n: int = h.heights[col]
		var x := HazardLayer.px(h.col_left(col))
		_stack(c, col, n, x, w, ch, floor_y, look, gift)
		if h.coins[col] == 1:
			var p := HazardLayer.at(h.col_center(col), h.coin_y(col))
			p.y += sin(time * 4.0 + col) * 2.0
			var s := Vector2(COIN_SIZE, COIN_SIZE)
			c.draw_texture_rect(COIN, Rect2(p - s / 2.0, s), false)
	_draw_puffs(c, time)
	if h.col < 0:
		return
	if h.warn_left > 0:
		_marker(c, h, h.col, theme, time)
		if h.col_b >= 0:
			_marker(c, h, h.col_b, theme, time)
		return
	if not h.done:
		_falling(
			c, Rect2(HazardLayer.px(h.col_left(h.col)), HazardLayer.px(h.y), w, ch), look, gift
		)
	if h.col_b >= 0 and not h.done_b:
		var xb := HazardLayer.px(h.col_left(h.col_b))
		_falling(c, Rect2(xb, HazardLayer.px(h.y_b), w, ch), look, gift)


## A falling crate comes out from behind the ceiling spikes: above the
## ceiling's kill line (deadly anyway) it isn't drawn, so it never shows on top
## of the spike row while it drops in.
static func _falling(c: CanvasItem, r: Rect2, look: HazardLook, gift: bool) -> void:
	var top := HazardLayer.px(SimConfig.KILL_TOP)
	if r.end.y <= top:
		return
	if r.position.y >= top:
		_crate(c, r, look, gift)
		return
	# Partly out: the visible slice keeps its rounded bottom and its planks.
	var shown := Rect2(r.position.x, top, r.size.x, r.end.y - top)
	HazardLayer.rock_box(c, shown, look)
	var edge := Color(look.theme.spike_edge, 0.75)
	var inner := shown.grow(-5.0)
	if inner.size.y > 2.0 and not gift:
		c.draw_rect(inner, edge, false, 2.0, true)


## A standing stack, drawn one spike depth lower than the sim's (so it sits on
## the floor band, where the spikes stood) with the floor spikes riding on top
## of it: their tips are the sim's stack top, where it starts to kill. When a
## crate lands, it settles over SINK_TIME, squashing the spikes it landed on
## while new ones push up on top of it.
func _stack(
	c: CanvasItem,
	col: int,
	n: int,
	x: float,
	w: float,
	ch: float,
	floor_y: float,
	look: HazardLook,
	gift: bool
) -> void:
	if n <= 0:
		return
	var d := RoomView.EDGE_SPIKE_DEPTH
	var e := _ease(_now - _landed[col])
	for i in n:
		var top := i == n - 1
		var y := floor_y - ch * (i + 1) + (d * e if top else d)
		if top and n > 1:
			_spikes_on(c, x, w, floor_y - ch * (n - 1) + d, d * (1.0 - e), look)
		_crate(c, Rect2(x, y, w, ch), look, gift)
	_spikes_on(c, x, w, floor_y - ch * n + d * e, d * e, look)


## Floor spikes standing on a stack top at `y`, as many as fit its width.
static func _spikes_on(
	c: CanvasItem, x: float, w: float, y: float, depth: float, look: HazardLook
) -> void:
	if depth <= RoomView.TIP_BACK + 1.0:
		return
	var count := maxi(1, roundi(w / (RoomView.EDGE_SPIKE_HALF * 2.0)))
	var step := w / count
	for i in count:
		var base := Vector2(x + step * (i + 0.5), y)
		RoomView.paint_spike(c, base, Vector2(0, -1), step / 2.0, depth, look.theme, look.ink)


## 0..1: how far a floor spike from `left` to `right` (px) has sunk.
func floor_sink(hazard: Hazard, left: float, right: float) -> float:
	var h := hazard as CrateDropHazard
	if h.get_instance_id() != _hazard_id:
		return 0.0
	var w := HazardLayer.px(h.crate_w)
	var out := 0.0
	for col in mini(h.cols, _started.size()):
		if h.heights[col] == 0:
			continue
		var x := HazardLayer.px(h.col_left(col))
		if x <= left + SINK_SLACK and x + w >= right - SINK_SLACK:
			out = maxf(out, _ease(_now - _started[col]))
	return out


## Notes when stacks start and crates land (for the sink and the puffs).
func _track_landings(h: CrateDropHazard, time: float) -> void:
	_now = time
	if h.get_instance_id() != _hazard_id or _heights.size() != h.cols:
		_hazard_id = h.get_instance_id()
		_heights = PackedInt32Array(h.heights)
		_started = PackedFloat32Array()
		_started.resize(h.cols)
		# Stacks already standing (a redraw mid-room) are already down.
		_started.fill(time - SINK_TIME)
		_landed = PackedFloat32Array(_started)
		_puffs.clear()
		return
	for col in h.cols:
		var n: int = h.heights[col]
		if n == _heights[col]:
			continue
		if n > _heights[col]:
			if _heights[col] == 0:
				_started[col] = time
			_landed[col] = time
			# Where the new crate settles: one spike depth under the sim's.
			var bottom := HazardLayer.px(h.stack_top(col) + h.crate_h) + RoomView.EDGE_SPIKE_DEPTH
			var x := HazardLayer.px(h.col_left(col))
			var w := HazardLayer.px(h.crate_w)
			_puffs.append(PackedFloat32Array([x, bottom, w, time]))
		_heights[col] = n
	while not _puffs.is_empty() and time - _puffs[0][3] > PUFF_TIME:
		_puffs.pop_front()


## Light dust (safe, never in spike colour) rolling out from a landing.
func _draw_puffs(c: CanvasItem, time: float) -> void:
	for p in _puffs:
		var f := clampf((time - p[3]) / PUFF_TIME, 0.0, 1.0)
		var alpha := 0.55 * (1.0 - f)
		for k in PUFF_AT:
			var cx := p[0] + p[2] / 2.0 + k * (p[2] / 2.0 + PUFF_SPREAD * f)
			var cy := p[1] - 4.0 - 6.0 * f * absf(k)
			var r := 4.0 + 6.0 * f
			c.draw_circle(Vector2(cx, cy), r, Color(Color.WHITE, alpha), true, -1.0, true)


func _marker(c: CanvasItem, h: CrateDropHazard, col: int, theme: ThemeDef, time: float) -> void:
	# A chevron under the ceiling and a dashed drop line.
	var w := HazardLayer.px(h.crate_w)
	var cx := HazardLayer.px(h.col_left(col))
	var pulse := 0.55 + 0.35 * sin(time * 12.0)
	var mid := cx + w / 2.0
	var top := HazardLayer.px(SimConfig.KILL_TOP) + 6.0
	var land := HazardLayer.px(h.stack_top(col))
	c.draw_dashed_line(
		Vector2(mid, top + 14.0), Vector2(mid, land), Color(theme.spike, pulse * 0.45), 2.0, 8.0
	)
	var chev := PackedVector2Array(
		[Vector2(mid - 10.0, top), Vector2(mid, top + 10.0), Vector2(mid + 10.0, top)]
	)
	c.draw_polyline(chev, Color(theme.spike, pulse), 3.0, true)
	c.draw_rect(Rect2(cx, land - 3.0, w, 3.0), Color(theme.spike, pulse * 0.6), true)


## Ease-out from 0 to 1 over SINK_TIME seconds.
static func _ease(elapsed: float) -> float:
	var f := clampf(elapsed / SINK_TIME, 0.0, 1.0)
	return 1.0 - (1.0 - f) * (1.0 - f)


static func _crate(c: CanvasItem, r: Rect2, look: HazardLook, gift: bool) -> void:
	HazardLayer.rock_box(c, r, look)
	var theme := look.theme
	var edge := Color(theme.spike_edge, 0.75)
	if gift:
		# Ribbon cross and a bow.
		var mid := r.get_center()
		c.draw_rect(Rect2(mid.x - 3.0, r.position.y, 6.0, r.size.y), edge, true)
		c.draw_rect(Rect2(r.position.x, mid.y - 3.0, r.size.x, 6.0), edge, true)
		var bow_y := r.position.y + 2.0
		c.draw_circle(Vector2(mid.x - 5.0, bow_y), 4.0, edge, true, -1.0, true)
		c.draw_circle(Vector2(mid.x + 5.0, bow_y), 4.0, edge, true, -1.0, true)
		return
	# Wooden crate: a frame and a diagonal brace.
	var inner := r.grow(-5.0)
	c.draw_rect(inner, edge, false, 2.0, true)
	c.draw_line(inner.position, inner.end, edge, 2.0, true)
