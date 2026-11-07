class_name RoomView
extends Node2D
## Draws the room in the Sunset Glow style: sky gradient, sun, clouds, the big
## faint score, ceiling/floor spikes and the side-wall spikes from sim state.
## Smooth spikes with a rounded tip. Cosmetic only; hitboxes live in sim/.

const W := 360.0
const H := 640.0
const BAND := 8.0
const SPIKE_DEPTH := 30.0
const SPIKE_HALF := 18.0
const EDGE_SPIKE_DEPTH := 28.0
const EDGE_SPIKE_HALF := 15.0
const SLIDE_SPEED := 8.0
const FADE_SPEED := 2.5

var _run: RunController
## Per-slot slide-in progress (0..1) for each side wall.
var _left_reveal := PackedFloat32Array()
var _right_reveal := PackedFloat32Array()
var _palette := SunsetPalette.for_room(0)
var _prev_palette := SunsetPalette.for_room(0)
var _fade := 1.0
var _font := ThemeDB.fallback_font


func bind(run: RunController) -> void:
	_run = run
	_left_reveal.resize(SimConfig.SLOT_COUNT)
	_right_reveal.resize(SimConfig.SLOT_COUNT)
	_left_reveal.fill(0.0)
	_right_reveal.fill(0.0)
	_palette = SunsetPalette.for_room(0)
	_prev_palette = _palette
	_fade = 1.0
	queue_redraw()


func on_room_changed(room_index: int) -> void:
	_prev_palette = _current_palette()
	_palette = SunsetPalette.for_room(room_index)
	_fade = 0.0


func _process(delta: float) -> void:
	if _run == null or _run.sim == null:
		return
	var s := _run.sim.state
	_animate_wall(_left_reveal, s.left_spikes, delta)
	_animate_wall(_right_reveal, s.right_spikes, delta)
	_fade = minf(_fade + delta * FADE_SPEED, 1.0)
	queue_redraw()


func _animate_wall(reveal: PackedFloat32Array, mask: int, delta: float) -> void:
	for slot in SimConfig.SLOT_COUNT:
		var target := 1.0 if RoomRules.has_slot(mask, slot) else 0.0
		reveal[slot] = move_toward(reveal[slot], target, delta * SLIDE_SPEED)


func _current_palette() -> Dictionary:
	if _fade >= 1.0:
		return _palette
	var p := {}
	var sky: Array[Color] = []
	for i in 3:
		sky.append((_prev_palette.sky[i] as Color).lerp(_palette.sky[i], _fade))
	p.sky = sky
	p.sun = (_prev_palette.sun as Color).lerp(_palette.sun, _fade)
	p.spike = (_prev_palette.spike as Color).lerp(_palette.spike, _fade)
	return p


func _draw() -> void:
	var p := _current_palette()
	_draw_sky(p)
	_draw_score()
	_draw_edges(p.spike)
	if _run != null and _run.sim != null:
		_draw_side_spikes(_left_reveal, 0.0, 1.0, p.spike)
		_draw_side_spikes(_right_reveal, W, -1.0, p.spike)


func _draw_sky(p: Dictionary) -> void:
	var top: Color = p.sky[0]
	var mid: Color = p.sky[1]
	var bottom: Color = p.sky[2]
	var half := H * 0.55
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, half), Vector2(0, half)]),
		PackedColorArray([top, top, mid, mid])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, half), Vector2(W, half), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([mid, mid, bottom, bottom])
	)
	var sun: Color = p.sun
	draw_circle(Vector2(265, 175), 90.0, Color(sun, 0.25))
	draw_circle(Vector2(265, 175), 56.0, Color(sun, 0.45))
	var cloud := Color(1, 1, 1, 0.3)
	_draw_ellipse(Vector2(80, 250), Vector2(52, 13), cloud)
	_draw_ellipse(Vector2(115, 240), Vector2(34, 13), cloud)
	_draw_ellipse(Vector2(250, 410), Vector2(60, 14), cloud)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, radii.y / radii.x))
	draw_circle(Vector2.ZERO, radii.x, color)
	draw_set_transform(Vector2.ZERO)


func _draw_score() -> void:
	var score := 0 if _run == null or _run.sim == null else _run.sim.state.score
	draw_string(
		_font,
		Vector2(0, 375),
		str(score),
		HORIZONTAL_ALIGNMENT_CENTER,
		W,
		170,
		Color(1, 1, 1, 0.22)
	)


func _draw_edges(color: Color) -> void:
	draw_rect(Rect2(0, 0, W, BAND), color)
	draw_rect(Rect2(0, H - BAND, W, BAND), color)
	var count := int(W / (EDGE_SPIKE_HALF * 2.0))
	var step := W / count
	for i in count:
		var cx := step * (i + 0.5)
		_draw_spike(Vector2(cx, BAND), Vector2(0, 1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH, color)
		_draw_spike(Vector2(cx, H - BAND), Vector2(0, -1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH, color)


func _draw_side_spikes(reveal: PackedFloat32Array, wall_x: float, dir: float, color: Color) -> void:
	for slot in SimConfig.SLOT_COUNT:
		var t := reveal[slot]
		if t <= 0.0:
			continue
		var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB)
		var depth := SPIKE_DEPTH * ease(t, 0.5)
		var base_x := wall_x - dir * (SPIKE_DEPTH - depth)
		_draw_spike(Vector2(base_x, cy), Vector2(dir, 0), SPIKE_HALF, SPIKE_DEPTH, color)


## Smooth spike: triangle with a rounded tip; one half shaded darker.
func _draw_spike(base: Vector2, dir: Vector2, half: float, depth: float, color: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var a := base + side * half
	var b := base - side * half
	var tip := base + dir * depth
	var tip_r := 3.0
	var tip_c := tip - dir * tip_r * 1.6
	var arc := PackedVector2Array()
	for i in 7:
		var ang := lerpf(-PI * 0.38, PI * 0.38, i / 6.0)
		arc.append(tip_c + dir.rotated(ang) * tip_r)
	# Walk the tip arc from the a-side to the b-side so the outline never crosses itself.
	if arc[0].distance_squared_to(a) > arc[arc.size() - 1].distance_squared_to(a):
		arc.reverse()
	var pts := PackedVector2Array([a])
	pts.append_array(arc)
	pts.append(b)
	draw_colored_polygon(pts, color)
	var shade := PackedVector2Array([base, tip_c + dir * tip_r, b])
	draw_colored_polygon(shade, Color(0, 0, 0, SunsetPalette.SPIKE_DARK_SHADE))
