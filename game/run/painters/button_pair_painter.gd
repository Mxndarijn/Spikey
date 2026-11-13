extends HazardPainter
## Buttons: two hanging buttons. The top one hangs on a rod from the ceiling,
## the bottom one stands on a post from the floor; the edge spikes stay behind
## them. Each button is a dark base with a cap on the room side. The lit one
## (the next to press) has its cap in the world accent and two chevrons
## pointing at it from the room. A press sinks the cap SINK into its base,
## with a flash on the face, a ring and a few flat shards; then it stays sunk
## a little, in paper with a tick, until the other one is pressed. Pressing the
## unlit one only dents it. A row of ten pips under the score counts the
## presses. Never in the spike colour.

const ButtonPairHazard := preload("res://sim/hazards/button_pair.gd")
const ROD := 6.0
## The base the cap sinks into, and the cap, px (BODY = BASE + CAP).
const BASE := 10.0
const CAP := 16.0
const SINK := 6.0
const DONE_SINK := 3.0
const DENT := 2.0
const PRESS_FX := 22.0
const PIPS := 10
const PIP_R := 4.5
const PIP_STEP := 13.0
const PIP_Y := 172.0


func paint(c: CanvasItem, hazard: Hazard, look: HazardLook) -> void:
	var h := hazard as ButtonPairHazard
	for top: bool in [true, false]:
		_button(c, h, look, top)
	_pips(c, h, look)


func _button(c: CanvasItem, h: ButtonPairHazard, look: HazardLook, top: bool) -> void:
	var theme := look.theme
	var x0 := HazardLayer.px(h.x0(top))
	var x1 := HazardLayer.px(h.x1(top))
	var mid := (x0 + x1) / 2.0
	var face := HazardLayer.px(ButtonPairHazard.face(top))
	var dir := 1.0 if top else -1.0
	var shut := _exit_open(look)
	var lit := h.lit_top == top and not shut
	var done := h.lit_top != top and h.presses > 0 and not shut
	# How far the cap is pushed into its base.
	var sink := 0.0
	if done:
		var k := clampf((h.since_press - 6.0) / 10.0, 0.0, 1.0)
		sink = lerpf(SINK, DONE_SINK, k)
	if h.last_top == top:
		sink = maxf(sink, DENT * clampf(1.0 - h.since_wrong / 10.0, 0.0, 1.0))
	var back := face - dir * (BASE + CAP)
	# The rod (top) or post (bottom) to the edge, behind everything.
	var rod_col := Color(theme.ink, 0.45)
	if top:
		c.draw_rect(Rect2(mid - ROD / 2.0, 0.0, ROD, back), rod_col)
	else:
		c.draw_rect(Rect2(mid - ROD / 2.0, back, ROD, RoomView.H - back), rod_col)
	# The base.
	var base_y := back if top else back - BASE
	_box(c, Rect2(x0 - 6.0, base_y, x1 - x0 + 12.0, BASE), theme.ink, 4, 4, 4, 4)
	# The cap, on the room side of the base, pushed back by `sink`.
	var cap_y := face - CAP - sink if top else face + sink
	var cap_col := Color(theme.ink, 0.22)
	if lit:
		cap_col = theme.world_accent
	elif done:
		cap_col = theme.paper
	var r_out := 8 if top else 0
	var r_in := 0 if top else 8
	_box(c, Rect2(x0, cap_y, x1 - x0, CAP), theme.ink, r_in, r_in, r_out, r_out)
	_box(
		c, Rect2(x0 + 2.5, cap_y + 2.5, x1 - x0 - 5.0, CAP - 5.0), cap_col, r_in, r_in, r_out, r_out
	)
	var strip_y := cap_y + CAP - 7.0 if top else cap_y + 3.0
	c.draw_rect(Rect2(mid - 16.0, strip_y, 32.0, 4.0), Color(theme.paper, 0.6))
	if done:
		_tick(c, Vector2(mid, cap_y + CAP / 2.0), theme.world_accent)
	var edge := face - dir * sink
	if lit:
		var pulse := 0.5 + 0.5 * sin(look.time * 5.0)
		for i in 2:
			var cy := edge + dir * (18.0 + i * 16.0)
			var a := (1.0 if i == 0 else 0.5) * (0.7 + 0.3 * pulse)
			var pts := PackedVector2Array(
				[
					Vector2(mid - 11.0, cy + dir * 10.0),
					Vector2(mid, cy),
					Vector2(mid + 11.0, cy + dir * 10.0)
				]
			)
			c.draw_polyline(pts, Color(theme.world_accent, a), 5.0, true)
	if h.last_top == top and h.since_press < PRESS_FX:
		_burst(c, Vector2(mid, edge), x1 - x0, dir, h.since_press / PRESS_FX, theme)


## The press: a flash across the face, a ring and six shards flying into the room.
static func _burst(
	c: CanvasItem, at: Vector2, w: float, dir: float, k: float, theme: ThemeDef
) -> void:
	var fade := 1.0 - k
	_ellipse(c, at, w / 2.0 * (1.0 - k * 0.3), 6.0, Color(theme.paper, fade * 0.9), true)
	_ellipse(c, at, 20.0 + 60.0 * k, 8.0 + 26.0 * k, Color(theme.world_accent, fade), false)
	for i in 6:
		var ang := PI * (0.12 + 0.152 * i)
		var r := 16.0 + 40.0 * k
		var p := at + Vector2(cos(ang) * r * 1.5, dir * sin(ang) * r)
		var tri := PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 4), p + Vector2(-5, 4)])
		c.draw_colored_polygon(tri, Color(theme.world_accent, fade))


## Ten pips under the score: one lights per press; all lit once the exit opens.
func _pips(c: CanvasItem, h: ButtonPairHazard, look: HazardLook) -> void:
	var lit := PIPS if _exit_open(look) else mini(h.presses, PIPS)
	var x := RoomView.W / 2.0 - PIP_STEP * (PIPS - 1) / 2.0
	for i in PIPS:
		var col := look.theme.world_accent if i < lit else Color(look.theme.ink, 0.2)
		c.draw_circle(Vector2(x + i * PIP_STEP, PIP_Y), PIP_R, col, true, -1.0, true)


static func _tick(c: CanvasItem, at: Vector2, col: Color) -> void:
	var pts := PackedVector2Array(
		[at + Vector2(-6.0, 0.0), at + Vector2(-2.0, 4.5), at + Vector2(6.5, -5.0)]
	)
	c.draw_polyline(pts, col, 3.5, true)


static func _ellipse(
	c: CanvasItem, at: Vector2, rx: float, ry: float, col: Color, fill: bool
) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	if fill:
		c.draw_colored_polygon(pts, col)
	else:
		c.draw_polyline(pts, col, 4.0, true)


static func _box(
	c: CanvasItem, rect: Rect2, col: Color, tl: int, tr: int, br: int, bl: int
) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.anti_aliasing = true
	box.corner_radius_top_left = tl
	box.corner_radius_top_right = tr
	box.corner_radius_bottom_right = br
	box.corner_radius_bottom_left = bl
	box.draw(c.get_canvas_item(), rect)


## With the exit open both buttons go dark.
static func _exit_open(look: HazardLook) -> bool:
	return look.sim != null and look.sim.state.exit_open
