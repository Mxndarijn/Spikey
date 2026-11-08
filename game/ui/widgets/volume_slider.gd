class_name VolumeSlider
extends Range
## A flat volume slider (0 to 100): a 10px soft edge track filled ink up to the
## value and a white knob with a 3px ink ring. The knob always stays inside the
## bar, even at 0 and 100. Drag or tap anywhere on it; left and right keys move
## it by KEY_STEP. `faded` draws it at the disabled opacity (the sound is off).

const HEIGHT := 44.0
const TRACK_H := 10.0
const KNOB := 24.0
const RING := 3.0
const KEY_STEP := 5.0

var faded := false:
	set(value):
		faded = value
		queue_redraw()

var _dragging := false


func _init() -> void:
	min_value = 0.0
	max_value = 100.0
	step = 1.0
	custom_minimum_size = Vector2(0, HEIGHT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	value_changed.connect(queue_redraw.unbind(1))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				value = value_at(mb.position.x)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		value = value_at((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		value -= KEY_STEP
		accept_event()
	elif event.is_action_pressed("ui_right"):
		value += KEY_STEP
		accept_event()


## The value under a point (x in local px): the knob's centre follows the finger.
func value_at(x: float) -> float:
	var span := maxf(size.x - KNOB, 1.0)
	var t := clampf((x - KNOB / 2.0) / span, 0.0, 1.0)
	return lerpf(min_value, max_value, t)


## The knob's centre x for the current value: from KNOB/2 to width - KNOB/2.
func knob_x() -> float:
	return KNOB / 2.0 + maxf(size.x - KNOB, 0.0) * float(ratio)


func _draw() -> void:
	var a := UiTokens.OPACITY_DISABLED if faded else 1.0
	var mid := size.y / 2.0
	var track := Rect2(0, mid - TRACK_H / 2.0, size.x, TRACK_H)
	_pill(track, Color(UiTokens.EDGE, a))
	var x := knob_x()
	_pill(Rect2(track.position, Vector2(maxf(x, TRACK_H), TRACK_H)), Color(UiTokens.INK_LINE, a))
	draw_circle(Vector2(x, mid), KNOB / 2.0, Color(UiTokens.INK_LINE, a), true, -1.0, true)
	draw_circle(Vector2(x, mid), KNOB / 2.0 - RING, Color(1, 1, 1, a), true, -1.0, true)


func _pill(r: Rect2, color: Color) -> void:
	var rad := r.size.y / 2.0
	draw_rect(
		Rect2(r.position + Vector2(rad, 0), Vector2(maxf(r.size.x - rad * 2.0, 0.0), r.size.y)),
		color
	)
	draw_circle(r.position + Vector2(rad, rad), rad, color, true, -1.0, true)
	draw_circle(Vector2(r.end.x - rad, r.position.y + rad), rad, color, true, -1.0, true)
