class_name NewBestFx
extends Control
## The new-best moment on Game over, drawn over the room: the gold "New best!"
## ribbon, three white sparkles that twinkle once, and confetti that falls
## through the screen once and fades out. `time` (seconds since game over)
## drives it; `still` shows the calm end state (ribbon and sparkles, no
## confetti) for reduced motion.

const GOLD := UiTokens.ACTION
const TAIL := Color("#E0A82E")
const FOLD := Color("#B8861E")
const CONFETTI_COLORS: Array[Color] = [
	UiTokens.ACTION, Color.WHITE, UiTokens.INK_LINE, Color("#FF8A6A"), Color("#7FD3FF")
]
const RIBBON_TOP := 60.0
const RIBBON_W := 150.0
const RIBBON_H := 38.0
## x, y, radius on the 360 x 640 screen.
const SPARKLES: Array[Vector3] = [Vector3(50, 146, 10), Vector3(322, 136, 8), Vector3(330, 296, 9)]
## The confetti falls once, in this many seconds.
const FALL_TIME := 2.4
## No confetti near the score.
const CLEAR_CENTER := Vector2(180, 204)
const CLEAR_RADIUS := 124.0

var time := 0.0:
	set(value):
		time = value
		queue_redraw()
var still := false:
	set(value):
		still = value
		queue_redraw()

## [position, rotation, colour] for each piece, the same every time.
var _pieces: Array[Array] = []
var _label := Label.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	for i in 26:
		var p := Vector2(rng.randf_range(24, 336), rng.randf_range(60, 400))
		var rot := rng.randf_range(0.0, PI)
		var c := CONFETTI_COLORS[rng.randi() % CONFETTI_COLORS.size()]
		if p.distance_to(CLEAR_CENTER) >= CLEAR_RADIUS:
			_pieces.append([p, rot, c])
	_label.text = "New best!"
	_label.add_theme_font_override("font", GameFonts.wide(900, 112))
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", UiTokens.ON_ACTION)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -RIBBON_W / 2.0
	_label.offset_right = RIBBON_W / 2.0
	_label.offset_top = RIBBON_TOP
	_label.offset_bottom = RIBBON_TOP + RIBBON_H
	add_child(_label)


func ribbon_text() -> String:
	return _label.text


## How far the confetti has fallen (px) and how visible it is, at `t`.
static func confetti_at(t: float) -> Vector2:
	var drop := -120.0 + 640.0 * minf(1.0, t / FALL_TIME)
	var alpha := clampf(minf(t * 3.0, (FALL_TIME - t) / 0.6), 0.0, 1.0)
	return Vector2(drop, alpha)


func _draw() -> void:
	var cx := size.x / 2.0
	_draw_ribbon(cx)
	var tw := 1.0 if still else 0.6 + 0.4 * absf(sin(minf(time, 1.2) * TAU))
	for s in SPARKLES:
		_sparkle(Vector2(s.x - 180.0 + cx, s.y), s.z, Color(1, 1, 1, tw))
	if still:
		return
	var fall := confetti_at(time)
	if fall.y <= 0.0:
		return
	for piece: Array in _pieces:
		var p: Vector2 = piece[0]
		var c: Color = piece[2]
		draw_set_transform(Vector2(p.x - 180.0 + cx, p.y + fall.x), piece[1], Vector2.ONE)
		draw_style_box(_bit(Color(c, fall.y)), Rect2(-4.5, -2, 9, 4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _bit(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(2)
	s.anti_aliasing = true
	return s


func _draw_ribbon(cx: float) -> void:
	var y := RIBBON_TOP
	var h := RIBBON_H
	var x0 := cx - RIBBON_W / 2.0
	var x1 := cx + RIBBON_W / 2.0
	var left := PackedVector2Array(
		[
			Vector2(x0 + 10, y + 10),
			Vector2(x0 - 22, y + 10),
			Vector2(x0 - 10, y + h / 2 + 10),
			Vector2(x0 - 22, y + h + 10),
			Vector2(x0 + 10, y + h + 10),
		]
	)
	var right := PackedVector2Array()
	for p in left:
		right.append(Vector2(2.0 * cx - p.x, p.y))
	draw_colored_polygon(left, TAIL)
	draw_colored_polygon(right, TAIL)
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(x0 + 10, y + h), Vector2(x0 + 10, y + h + 10), Vector2(x0 - 2, y + h)]
		),
		FOLD
	)
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(x1 - 10, y + h), Vector2(x1 - 10, y + h + 10), Vector2(x1 + 2, y + h)]
		),
		FOLD
	)
	var body := UiTheme.flat(GOLD, 6, 0)
	draw_style_box(body, Rect2(x0, y, RIBBON_W, h))


## A soft four-point star.
func _sparkle(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 4:
		var a := i * PI / 2.0 - PI / 2.0
		var tip := c + Vector2(cos(a), sin(a)) * r
		var nxt := c + Vector2(cos(a + PI / 2.0), sin(a + PI / 2.0)) * r
		var bend := c + Vector2(cos(a + PI / 4.0), sin(a + PI / 4.0)) * r * 0.28
		for k in 6:
			var u := k / 6.0
			pts.append(tip.lerp(bend, u).lerp(bend.lerp(nxt, u), u))
	draw_colored_polygon(pts, color)
