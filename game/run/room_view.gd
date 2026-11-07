class_name RoomView
extends Node2D
## Draws the room in the Sunset Glow style from the chosen world (ThemeDef):
## sky gradient, glow, clouds, the ghost score, and smooth spikes from sim state.
## Cosmetic only; hitboxes live in sim/.

const W := float(UiTokens.SIZE_VIEWPORT_W)
const H := float(UiTokens.SIZE_VIEWPORT_H)
const BAND := 8.0
const SPIKE_DEPTH := float(UiTokens.SIZE_SPIKE_DEPTH)
const SPIKE_HALF := UiTokens.SIZE_SPIKE_BASE / 2.0
const EDGE_SPIKE_DEPTH := 28.0
const EDGE_SPIKE_HALF := 15.0
const SPIKE_EDGE_ALPHA := 0.55
## Wall spikes slide in over about 125 ms; the sky fades over 400 ms.
const SLIDE_SPEED := 8.0
const FADE_SPEED := 2.5
const FLASH_ALPHA := 0.35

## Off when the player turns on reduced flashing (accessibility).
var flash_enabled := true

var _run: RunController
var _theme: ThemeDef
## Per-slot slide-in progress (0..1) for each side wall.
var _left_reveal := PackedFloat32Array()
var _right_reveal := PackedFloat32Array()
var _sky: Array[Color] = []
var _prev_sky: Array[Color] = []
var _fade := 1.0
var _flash := 0.0
var _room_index := 0


func bind(run: RunController, theme: ThemeDef) -> void:
	_run = run
	_left_reveal.resize(SimConfig.SLOT_COUNT)
	_right_reveal.resize(SimConfig.SLOT_COUNT)
	_left_reveal.fill(0.0)
	_right_reveal.fill(0.0)
	_room_index = 0
	set_theme(theme)


## Switches world instantly (theme picker); keeps the current room's palette slot.
func set_theme(theme: ThemeDef) -> void:
	_theme = theme
	_sky = theme.sky_for_room(_room_index)
	_prev_sky = _sky
	_fade = 1.0
	_flash = 0.0
	queue_redraw()


func on_room_changed(room_index: int) -> void:
	_prev_sky = _current_sky()
	_room_index = room_index
	_sky = _theme.sky_for_room(room_index)
	_fade = 0.0
	if flash_enabled:
		_flash = 1.0


func _process(delta: float) -> void:
	if _run == null or _run.sim == null:
		return
	var s := _run.sim.state
	_animate_wall(_left_reveal, s.left_spikes, delta)
	_animate_wall(_right_reveal, s.right_spikes, delta)
	_fade = minf(_fade + delta * FADE_SPEED, 1.0)
	_flash = maxf(_flash - delta * FADE_SPEED, 0.0)
	queue_redraw()


func _animate_wall(reveal: PackedFloat32Array, mask: int, delta: float) -> void:
	for slot in SimConfig.SLOT_COUNT:
		var target := 1.0 if RoomRules.has_slot(mask, slot) else 0.0
		reveal[slot] = move_toward(reveal[slot], target, delta * SLIDE_SPEED)


func _current_sky() -> Array[Color]:
	if _fade >= 1.0:
		return _sky
	var out: Array[Color] = []
	for i in 3:
		out.append(_prev_sky[i].lerp(_sky[i], _fade))
	return out


func _draw() -> void:
	if _theme == null:
		return
	_draw_sky(_current_sky())
	_draw_score()
	_draw_edges()
	if _run != null and _run.sim != null:
		_draw_side_spikes(_left_reveal, 0.0, 1.0)
		_draw_side_spikes(_right_reveal, W, -1.0)
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(_theme.world_accent, FLASH_ALPHA * _flash))


func _draw_sky(sky: Array[Color]) -> void:
	var half := H * 0.55
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, half), Vector2(0, half)]),
		PackedColorArray([sky[0], sky[0], sky[1], sky[1]])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, half), Vector2(W, half), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([sky[1], sky[1], sky[2], sky[2]])
	)
	var glow := _theme.glow
	draw_circle(Vector2(265, 175), 90.0, Color(glow, UiTokens.OPACITY_GLOW_OUTER))
	draw_circle(Vector2(265, 175), 56.0, Color(glow, UiTokens.OPACITY_GLOW_INNER))
	var cloud := Color(1, 1, 1, UiTokens.OPACITY_CLOUD)
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
		GameFonts.display(),
		Vector2(0, 380),
		str(score),
		HORIZONTAL_ALIGNMENT_CENTER,
		W,
		UiTokens.FONT_SIZE_SCORE_GHOST,
		UiTokens.SCORE_GHOST
	)


func _draw_edges() -> void:
	draw_rect(Rect2(0, 0, W, BAND), _theme.spike)
	draw_rect(Rect2(0, H - BAND, W, BAND), _theme.spike)
	var count := int(W / (EDGE_SPIKE_HALF * 2.0))
	var step := W / count
	for i in count:
		var cx := step * (i + 0.5)
		_draw_spike(Vector2(cx, BAND), Vector2(0, 1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH)
		_draw_spike(Vector2(cx, H - BAND), Vector2(0, -1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH)


func _draw_side_spikes(reveal: PackedFloat32Array, wall_x: float, dir: float) -> void:
	for slot in SimConfig.SLOT_COUNT:
		var t := reveal[slot]
		if t <= 0.0:
			continue
		var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB)
		var depth := SPIKE_DEPTH * ease(t, 0.5)
		var base_x := wall_x - dir * (SPIKE_DEPTH - depth)
		_draw_spike(Vector2(base_x, cy), Vector2(dir, 0), SPIKE_HALF, SPIKE_DEPTH)


## Smooth spike: a triangle with a rounded tip in the world's spike color,
## with one half lit in spike-edge.
func _draw_spike(base: Vector2, dir: Vector2, half: float, depth: float) -> void:
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
	draw_colored_polygon(pts, _theme.spike)
	var lit := PackedVector2Array([base, tip_c + dir * tip_r, b])
	draw_colored_polygon(lit, Color(_theme.spike_edge, SPIKE_EDGE_ALPHA))
