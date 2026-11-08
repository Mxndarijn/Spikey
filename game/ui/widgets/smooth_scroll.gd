class_name SmoothScroll
extends ScrollContainer
## A vertical list that follows the finger (or a held mouse) and coasts after
## a flick, slowing down every frame. Godot's own drag only works on touch
## screens and coasts on the 60 Hz physics tick, which judders on 90 and
## 120 Hz phones; this replaces it.
##
## A drag starts after DEADZONE px and cancels the press of the card under the
## finger (Buttons drop it on NOTIFICATION_SCROLL_BEGIN). Taps read through
## gui_input check `swallow_tap()`. `blocked` returns true while a popup
## covers the list. The input math is in press/move/release/advance, so tests
## can drive it without a window.

## Past this many px a press turns into a drag.
const DEADZONE := 8.0
## Coasting speed falls by this factor per second (exponential).
const FRICTION := 5.0
## Below this speed (px/s) coasting stops.
const MIN_SPEED := 20.0
const MAX_SPEED := 5000.0
## The flick speed is measured over the last moments of the drag.
const SAMPLE_WINDOW := 0.08
## A finger held still this long before lifting does not flick.
const HOLD_STOP := 0.06

## Returns true while something covers the list (a popup): no drag starts.
var blocked := Callable()

var _tracking := false
var _dragging := false
var _press_y := 0.0
var _last_y := 0.0
var _pos := 0.0
var _velocity := 0.0
## Recent (time, y) points of the drag.
var _samples: Array[Vector2] = []
## The process frame whose release ended a drag.
var _drag_end_frame := -1


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Turns off the built-in touch drag: this script does the dragging.
	scroll_deadzone = 1 << 20


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var now := Time.get_ticks_usec() / 1000000.0
	var y := get_global_mouse_position().y
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if get_global_rect().has_point(get_global_mouse_position()) and not _is_blocked():
				press(y, now)
		elif _tracking:
			release(now)
		return
	if event is InputEventMouseMotion and _tracking:
		move(y, now)


func _process(delta: float) -> void:
	advance(delta)


## A finger came down on the list: stops any coasting.
func press(y: float, t: float) -> void:
	_tracking = true
	_dragging = false
	_press_y = y
	_last_y = y
	_velocity = 0.0
	_pos = get_v_scroll_bar().value
	_samples = [Vector2(t, y)]


## The finger moved to `y`; returns true once it is dragging the list.
func move(y: float, t: float) -> bool:
	if not _tracking:
		return false
	if not _dragging:
		if absf(y - _press_y) < DEADZONE:
			return false
		_dragging = true
		_last_y = y
		propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		scroll_started.emit()
	_set_pos(_pos - (y - _last_y))
	_last_y = y
	_samples.append(Vector2(t, y))
	while _samples.size() > 2 and t - _samples[0].x > SAMPLE_WINDOW:
		_samples.pop_front()
	return true


## The finger lifted: a drag coasts on with the finger's last speed.
func release(t: float) -> void:
	if _dragging:
		_velocity = _flick_speed(t)
		_drag_end_frame = Engine.get_process_frames()
		if is_zero_approx(_velocity):
			_end_scroll()
	_tracking = false
	_dragging = false


## Coasting for one frame.
func advance(delta: float) -> void:
	if _tracking or is_zero_approx(_velocity):
		return
	# Something else moved the list (a tab change): stop coasting.
	if absf(get_v_scroll_bar().value - _pos) > 1.0:
		_pos = get_v_scroll_bar().value
		_velocity = 0.0
		_end_scroll()
		return
	var before := _pos
	_set_pos(_pos + _velocity * delta)
	_velocity *= exp(-FRICTION * delta)
	if absf(_velocity) < MIN_SPEED or is_equal_approx(before, _pos):
		_velocity = 0.0
		_end_scroll()


## True during the release that ended a drag, so a row's own tap ignores it.
func swallow_tap() -> bool:
	return _dragging or _drag_end_frame == Engine.get_process_frames()


func is_dragging() -> bool:
	return _dragging


func is_coasting() -> bool:
	return not is_zero_approx(_velocity)


## The scroll offset in px (not rounded).
func offset() -> float:
	return _pos


## The furthest the list scrolls.
func max_offset() -> float:
	var bar := get_v_scroll_bar()
	return maxf(bar.max_value - bar.page, 0.0)


func _set_pos(value: float) -> void:
	_pos = clampf(value, 0.0, max_offset())
	get_v_scroll_bar().value = _pos


## Px per second that the list moves after the last moments of the drag;
## zero when the finger rested before lifting.
func _flick_speed(t: float) -> float:
	if _samples.size() < 2:
		return 0.0
	var last: Vector2 = _samples[_samples.size() - 1]
	if t - last.x > HOLD_STOP:
		return 0.0
	var first: Vector2 = _samples[0]
	var dt := last.x - first.x
	if dt <= 0.0:
		return 0.0
	# The list moves against the finger.
	return clampf(-(last.y - first.y) / dt, -MAX_SPEED, MAX_SPEED)


func _end_scroll() -> void:
	propagate_notification(Control.NOTIFICATION_SCROLL_END)
	scroll_ended.emit()


func _is_blocked() -> bool:
	return blocked.is_valid() and bool(blocked.call())
