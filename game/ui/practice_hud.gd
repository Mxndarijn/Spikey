class_name PracticeHud
extends Control
## The extra HUD for a practice run, in the minimal kit: a small line
## "Practice: Piston Press" at the very top (the room on repeat), a bare restart
## icon top right, the text button Rooms while paused, and the crash screen on
## the dimmed room: "Crashed", the room, this try's points, the practice note,
## the round Try again on the action line and Rooms under it. Hud owns it and
## shows it only in practice; its pause button and score stay Hud's.

signal restart_pressed
signal rooms_pressed

const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
## The overlays' one text button: back to Rooms.
const ROOMS_TEXT := "Rooms"
## The line sits high on the ceiling's spike band, above SimConfig.KILL_TOP and the
## Spike Rain tells under it: the bird never gets there, so it never covers a
## hazard, a button or the bird.
## White in an ink halo, like the rest of the run's HUD.
const CHIP_TOP := 3.0
const CHIP_H := 17.0
## The chip stays clear of the corner buttons (Large buttons on, too).
const CHIP_MAX := 224.0
const NOTE := "Practice never counts for gold, best score, cleared rooms or leaderboards."

var _banner := PanelContainer.new()
var _room_line := Label.new()
var _restart: Button
var _pause_rooms: Control
var _over := ColorRect.new()
var _over_room := Label.new()
var _over_points := Label.new()
var _room_name := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_banner()
	_build_restart()
	_build_pause_rooms()
	_build_over()
	set_room("")


func _build_banner() -> void:
	_banner.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_line.theme_type_variation = &"HudLabel"
	_room_line.add_theme_font_size_override("font_size", 11)
	_room_line.add_theme_constant_override("outline_size", 3)
	_room_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_line.custom_minimum_size = Vector2(0, CHIP_H)
	_room_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_room_line)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = CHIP_TOP
	_banner.offset_bottom = CHIP_TOP + CHIP_H
	add_child(_banner)


func _build_restart() -> void:
	_restart = UiKit.hud_icon_button(RESTART_ICON, "Restart this room")
	_restart.add_theme_constant_override("icon_max_width", 24)
	_restart.anchor_left = 1.0
	_restart.anchor_right = 1.0
	_place_restart(UiKit.ICON_BUTTON)
	_restart.pressed.connect(restart_pressed.emit)
	add_child(_restart)


func _place_restart(side: float) -> void:
	_restart.custom_minimum_size = Vector2(side, side)
	_restart.offset_left = -Hud.CORNER.x - side
	_restart.offset_right = -Hud.CORNER.x
	_restart.offset_top = 42
	_restart.offset_bottom = 42 + side


## Settings > Large buttons changed.
func refresh_button_size() -> void:
	_place_restart(UiKit.button_size())


func _build_pause_rooms() -> void:
	_pause_rooms = UiKit.place_text_button(self, _rooms_button())


## The text button "Rooms" (the overlay's one other choice): back to Rooms.
func _rooms_button() -> Button:
	var b := UiKit.text_button(ROOMS_TEXT)
	b.pressed.connect(rooms_pressed.emit)
	UiKit.mark_back(b)
	return b


func _build_over() -> void:
	_over.color = UiTokens.SCRIM
	ScrimBleed.attach(_over)
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(UiKit.label("Crashed", &"ScrimTitle"), 84)
	(_over.get_child(0) as Label).add_theme_font_size_override("font_size", 40)
	_over_room.theme_type_variation = &"ScrimLabel"
	_over_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_over_room, 140)
	_over_points.theme_type_variation = &"ScrimScore"
	_over_points.add_theme_font_size_override("font_size", 110)
	_over_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_over_points, 160)
	_at(UiKit.label("points this try", &"ScrimLabel"), 280)
	var note := UiKit.wrapped(NOTE, &"ScrimCaption")
	var note_box := MarginContainer.new()
	note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_box.add_theme_constant_override("margin_left", 50)
	note_box.add_theme_constant_override("margin_right", 50)
	note_box.add_child(note)
	_at(note_box, 312)
	var again := UiKit.primary(RESTART_ICON, "Try again", true)
	again.name = "TryAgain"
	again.pressed.connect(restart_pressed.emit)
	UiKit.place_primary(_over, again)
	var rooms := UiKit.place_text_button(_over, _rooms_button())
	rooms.name = "BackToRooms"
	add_child(_over)


func _at(c: Control, top: float) -> void:
	_over.add_child(c)
	c.anchor_right = 1.0
	c.offset_top = top
	c.offset_bottom = top + c.get_combined_minimum_size().y


## The room this practice repeats; empty = not practising (all hidden).
func set_room(room_name: String) -> void:
	_room_name = room_name
	_room_line.text = "Practice: %s" % room_name
	UiKit.cap_width(_room_line, CHIP_MAX)
	_over_room.text = room_name
	visible = not room_name.is_empty()
	show_playing(false)


## While the room is being played (or waiting for the first tap).
func show_playing(paused: bool) -> void:
	_banner.visible = not paused
	_restart.visible = not paused
	_pause_rooms.visible = paused
	_over.visible = false


func show_over(points: int) -> void:
	_over_points.text = str(points)
	_banner.visible = false
	_restart.visible = false
	_pause_rooms.visible = false
	_over.visible = true


func is_over_showing() -> bool:
	return visible and _over.visible


func points_text() -> String:
	return _over_points.text


## "Piston Press, on repeat": what the chip means, for tests and tooltips.
func room_line() -> String:
	return "%s, on repeat" % _room_name


func chip_text() -> String:
	return _room_line.text
