extends HazardPainter
## Lava Rise: the lava in the spike colour, the one colour that kills, with a
## lighter crest. What sinks it is safe, so it is paper with a mint mark: the
## cool stone and the Cold Wall's ice block in its wall slot (mint frost and
## glow), and the rafts.
##
## A raft is a flat ledge to land on: paper with a darker face, a mint rim whose
## top is exactly the sim's surface (line - RAFT_HIGH), a contact shadow on the
## lava and two down arrows (landing here lowers the lava). Rising (its first
## second, not safe yet) it is still lava-hot and rings spread over it. The sim
## uses a raft up on its first touch: here it dips under the bird with a splash
## and sinks away, and while the lava sinks its top cools to a crust with arrows
## riding down on it.
##
## The lava has no cap, so it may cover an exit (RoomView draws exits under the
## hazards): the part under the lava shows as a dashed ink rim through it, so
## the exit is plainly there and plainly blocked.

const LavaHazard := preload("res://sim/hazards/lava.gd")

const WAVE := 3.0
## The ledge: height of its face below the line, its rim, the arrows.
const LEDGE_FACE := 9.0
const RIM := 4.0
const ARROW := 4.0
## A used raft: how far it dips under the bird, how long it stays on top of the
## lava, how fast it sinks after, how long the splash lasts (seconds).
const DIP := 6.0
const DIP_TIME := 0.08
const ON_TOP := 0.15
const SINK_SPEED := 30.0
const SPLASH_TIME := 0.5
const USED_TIME := 1.2
## The crust on sinking lava: its depth, and how far its arrows sit below the top.
const CRUST := 7.0
const CRUST_ARROW_Y := 14.0
## A covered exit's rim through the lava: its alpha, dashes and width.
const SUNK_ALPHA := 0.55
const SUNK_DASHES := 14
const SUNK_W := 2.0

## Rafts seen up last frame (RaftLanding) and rafts landed on (px x, px line,
## time), per "<hazard id>:<index>". Looks only.
var _was_on := {}
var _used := {}


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as LavaHazard
	var theme := look.theme
	var line := HazardLayer.px(h.line)
	var w := RoomView.W
	remember(h, line, look.time)
	if h.line < SimConfig.KILL_BOTTOM:
		for i in LavaHazard.MAX_RAFTS:
			if h.raft_on[i] and h.raft_age[i] < LavaHazard.RAFT_RISE:
				_raft(c, h, i, line, look)
		_used_rafts(c, h, line, look, false)
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= w:
			pts.append(Vector2(x, _wave(x, line, look)))
			x += 8.0
		pts.append(Vector2(w, RoomView.H + RoomView.SURROUND))
		pts.append(Vector2(0, RoomView.H + RoomView.SURROUND))
		c.draw_colored_polygon(pts, theme.spike)
		for i in range(0, int(w), 30):
			var cy := _wave(i + 10.0, line, look) - 1.0
			c.draw_set_transform(Vector2(i + 10.0, cy), 0.0, Vector2(1.0, 0.35))
			c.draw_circle(Vector2.ZERO, 9.0, theme.spike_edge)
			c.draw_set_transform(Vector2.ZERO)
		_sunk_exits(c, line, look)
		if h.mode == LavaHazard.Mode.RAFTS:
			_sinking(c, h, line, look)
		for i in LavaHazard.MAX_RAFTS:
			if h.raft_on[i] and h.raft_age[i] < LavaHazard.RAFT_RISE:
				_ripples(c, h, i, line, look)
		_used_rafts(c, h, line, look, true)
	for i in LavaHazard.MAX_RAFTS:
		if h.raft_on[i] and h.raft_age[i] >= LavaHazard.RAFT_RISE:
			_raft(c, h, i, line, look)
	if h.ice_on:
		_ice(c, h, look)
	if h.stone_on:
		var p := HazardLayer.at(h.stone_x, h.stone_y)
		c.draw_set_transform(p, 0.2, Vector2(1.0, 0.8))
		c.draw_circle(Vector2.ZERO, 15.0, UiTokens.PANEL)
		c.draw_set_transform(Vector2.ZERO)
		_frost(c, p, 7.0, look)


## The drawn top of raft `i` (px): the sim's surface once it is up, lower while
## it still rises.
static func raft_top(h: LavaHazard, i: int, line: float) -> float:
	var rise := clampf(float(h.raft_age[i]) / LavaHazard.RAFT_RISE, 0.0, 1.0)
	return line - HazardLayer.px(LavaHazard.RAFT_HIGH) + (1.0 - rise) * 18.0


## Notes the rafts landed on (RaftLanding) and forgets them once drawn out.
## Returns how many were landed on since the last frame.
func remember(h: LavaHazard, line: float, time: float) -> int:
	var landed := RaftLanding.landed(h, _was_on)
	for i in landed:
		_used["%d:%d" % [h.get_instance_id(), i]] = [HazardLayer.px(h.raft_x[i]), line, time]
	for i in LavaHazard.MAX_RAFTS:
		var key := "%d:%d" % [h.get_instance_id(), i]
		if h.raft_on[i] or (_used.has(key) and time - float(_used[key][2]) > USED_TIME):
			_used.erase(key)
	return landed.size()


## Whether raft `i` of `h` was landed on and is still drawn (dipping or sinking).
func landed_on(h: LavaHazard, i: int) -> bool:
	return _used.has("%d:%d" % [h.get_instance_id(), i])


## The shown exits (open or ghost) of `sim` as [side, centre y px], for the
## covered-exit rim.
static func shown_exits(sim: GameSim) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var st := sim.state
	if not st.exit_open and not st.exit_preview:
		return out
	out.append(Vector2(st.exit_side, st.exit_a_y / float(SimConfig.SUB)))
	if st.exit_b_kind != SimState.ExitKind.NORMAL:
		out.append(Vector2(st.exit_side, st.exit_b_y / float(SimConfig.SUB)))
	return out


## Whether lava with its top at `line` px covers any of an exit's opening
## centred at `y` px.
static func covers(line: float, y: float) -> bool:
	return y + SimConfig.EXIT_HALF / float(SimConfig.SUB) > line


func _sunk_exits(c: CanvasItem, line: float, look: HazardLook) -> void:
	if look.sim == null:
		return
	var half := SimConfig.EXIT_HALF / float(SimConfig.SUB)
	var rim := Color(look.theme.ink, SUNK_ALPHA)
	for e in shown_exits(look.sim):
		if not covers(line, e.y):
			continue
		var side := int(e.x)
		var wall := HazardLayer.px(
			look.sim.room.wall_left() if side == 0 else look.sim.room.wall_right()
		)
		var into := 1.0 if side == 0 else -1.0
		var centre := Vector2(wall + into * RoomView.EXIT_DEPTH, e.y)
		var radius := Vector2(16.0, half * 0.95)
		var steps := SUNK_DASHES * 2
		for i in range(0, steps, 2):
			var a0 := TAU * i / steps
			var a1 := TAU * (i + 1) / steps
			var p0 := centre + Vector2(cos(a0), sin(a0)) * radius
			var p1 := centre + Vector2(cos(a1), sin(a1)) * radius
			# Only the dashes under the lava's top: above it the portal shows itself.
			if minf(p0.y, p1.y) > _wave(p0.x, line, look) + 2.0:
				c.draw_line(p0, p1, rim, SUNK_W, true)


func _wave(x: float, line: float, look: HazardLook) -> float:
	return line + sin(x / 22.0 + look.time * 4.0) * WAVE


func _frost(c: CanvasItem, p: Vector2, r: float, look: HazardLook) -> void:
	for k in 3:
		var a := k * PI / 3.0 + look.time
		var d := Vector2(cos(a), sin(a)) * r
		c.draw_line(p - d, p + d, UiTokens.SUCCESS, 3.0, true)


## A raft that is out. Rising, it comes up from below the surface (drawn
## before the lava, so the lava covers what is still under).
func _raft(c: CanvasItem, h: LavaHazard, i: int, line: float, look: HazardLook) -> void:
	var rise := clampf(float(h.raft_age[i]) / LavaHazard.RAFT_RISE, 0.0, 1.0)
	_ledge(c, HazardLayer.px(h.raft_x[i]), raft_top(h, i, line), rise, line, look)


## The ledge with its top at `top`. `rise` < 1: still coming up, lava-hot
## (spike edge cooling to paper), no shadow and no arrows yet.
func _ledge(
	c: CanvasItem, x: float, top: float, rise: float, line: float, look: HazardLook, shadow := true
) -> void:
	var t := look.theme
	var half := HazardLayer.px(LavaHazard.RAFT_HALF)
	var high := HazardLayer.px(LavaHazard.RAFT_HIGH)
	var cool := clampf((rise - 0.35) / 0.65, 0.0, 1.0)
	var body := t.spike_edge.lerp(t.paper, cool)
	if rise >= 1.0 and shadow:
		c.draw_set_transform(Vector2(x, line + 3.0), 0.0, Vector2(1.0, 0.28))
		c.draw_circle(Vector2.ZERO, half + 8.0, t.spike.darkened(0.35))
		c.draw_set_transform(Vector2.ZERO)
	c.draw_rect(Rect2(x - half, top, half * 2.0, high + LEDGE_FACE), body.lerp(t.ink, 0.2))
	c.draw_rect(Rect2(x - half, top, half * 2.0, high), body)
	c.draw_rect(Rect2(x - half, top, half * 2.0, RIM), t.spike_edge.lerp(UiTokens.SUCCESS, cool))
	if rise >= 1.0:
		for k: float in [-1.0, 1.0]:
			_arrow(c, Vector2(x + k * half * 0.45, top + high + 4.0), ARROW, t.paper)


func _arrow(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array(
		[p + Vector2(-r, -r * 0.6), p + Vector2(0, r * 0.6), p + Vector2(r, -r * 0.6)]
	)
	c.draw_polyline(pts, col, 2.0, true)


## Rings spread on the lava over a raft still coming up (not safe yet).
func _ripples(c: CanvasItem, h: LavaHazard, i: int, line: float, look: HazardLook) -> void:
	var x := HazardLayer.px(h.raft_x[i])
	var half := HazardLayer.px(LavaHazard.RAFT_HALF)
	var rise := float(h.raft_age[i]) / LavaHazard.RAFT_RISE
	for k in 2:
		var ph := fmod(rise * 2.0 + k * 0.5, 1.0)
		c.draw_set_transform(Vector2(x, line - 1.0), 0.0, Vector2(1.0, 0.3))
		c.draw_arc(Vector2.ZERO, half * (0.35 + 0.75 * ph), PI, TAU, 24, look.theme.spike_edge, 6.0)
		c.draw_set_transform(Vector2.ZERO)


## A raft just landed on: it dips under the bird (on top of the lava), then
## sinks away under it; the splash goes on top. `front`: after the lava.
func _used_rafts(c: CanvasItem, h: LavaHazard, line: float, look: HazardLook, front: bool) -> void:
	var high := HazardLayer.px(LavaHazard.RAFT_HIGH)
	for i in LavaHazard.MAX_RAFTS:
		var key := "%d:%d" % [h.get_instance_id(), i]
		if not _used.has(key):
			continue
		var u: Array = _used[key]
		var x: float = u[0]
		var e := look.time - float(u[2])
		if e > USED_TIME or e < 0.0:
			continue
		var dip := DIP * minf(e / DIP_TIME, 1.0) + maxf(e - ON_TOP, 0.0) * SINK_SPEED
		if front == (e < ON_TOP):
			_ledge(c, x, line - high + dip, 1.0, line, look, false)
		if front and e < SPLASH_TIME:
			_splash(c, x, line, e / SPLASH_TIME, look)


## Lava drops thrown up from both ends and a ring; `k` 0..1 over the splash.
func _splash(c: CanvasItem, x: float, line: float, k: float, look: HazardLook) -> void:
	var t := look.theme
	var half := HazardLayer.px(LavaHazard.RAFT_HALF)
	for j in 4:
		var side := -1.0 if j < 2 else 1.0
		var out := 6.0 + 18.0 * k + (j % 2) * 6.0
		var up := 26.0 * k - 60.0 * k * k + (j % 2) * 4.0
		c.draw_circle(
			Vector2(x + side * (half + out * 0.5), line - up), 3.0 * (1.0 - k) + 1.0, t.spike
		)
	c.draw_set_transform(Vector2(x, line), 0.0, Vector2(1.0, 0.3))
	c.draw_arc(Vector2.ZERO, half + 10.0 + 30.0 * k, PI, TAU, 28, t.spike_edge, 6.0)
	c.draw_set_transform(Vector2.ZERO)


## While the lava sinks (a raft was landed on) its top cools: a lighter crust,
## with arrows riding down on it.
func _sinking(c: CanvasItem, h: LavaHazard, line: float, look: HazardLook) -> void:
	if HazardLayer.px(h.line_at(h.rises)) - line <= 1.0:
		return
	var t := look.theme
	var w := RoomView.W
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= w:
		pts.append(Vector2(x, _wave(x, line, look)))
		x += 8.0
	x = w
	while x >= 0.0:
		pts.append(Vector2(x, _wave(x, line, look) + CRUST))
		x -= 8.0
	c.draw_colored_polygon(pts, t.spike.lerp(t.spike_edge, 0.6))
	var drop := fmod(look.time * 40.0, 12.0)
	for k in 5:
		_arrow(c, Vector2(40.0 + k * 70.0, line + CRUST_ARROW_Y + drop), 6.0, t.paper)


## The ice block in its wall slot, over a mint glow.
func _ice(c: CanvasItem, h: LavaHazard, look: HazardLook) -> void:
	var depth := HazardLayer.px(LavaHazard.ICE_DEPTH)
	var cy := HazardLayer.px(SimConfig.slot_center_y(h.ice_slot))
	var half := HazardLayer.px(SimConfig.SLOT_SIZE) / 2.0
	var x0 := 0.0 if h.ice_side == 0 else RoomView.W - depth - 6.0
	var glow := Color(UiTokens.SUCCESS, 0.35)
	c.draw_rect(Rect2(x0 - 4.0, cy - half - 4.0, depth + 14.0, half * 2.0 + 8.0), glow)
	c.draw_rect(Rect2(x0, cy - half + 1.0, depth + 6.0, half * 2.0 - 2.0), UiTokens.PANEL)
	_frost(c, Vector2(x0 + (depth + 6.0) / 2.0, cy), 6.0, look)
