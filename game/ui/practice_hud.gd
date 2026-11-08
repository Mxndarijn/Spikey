class_name PracticeHud
extends Control
## The extra HUD for a practice run (Sticker Pop): a cream "Practice" banner
## naming the room that repeats and saying nothing counts, a restart button
## (top right), "Back to rooms" while paused, and the crash screen with this
## try's points, Try again and Back to rooms. Hud owns it and shows it only in
## practice.

signal restart_pressed
signal rooms_pressed

const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const BANNER_FILL := Color("#FFE3A3")

var _banner := VBoxContainer.new()
var _room_line := Label.new()
var _restart := Button.new()
var _pause_rooms := Button.new()
var _over := ColorRect.new()
var _over_room := Label.new()
var _over_points := Label.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_banner()
	_build_restart()
	_build_pause_rooms()
	_build_over()
	set_room("")


func _build_banner() -> void:
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_theme_constant_override("separation", 4)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.offset_left = 72
	_banner.offset_right = -72
	_banner.offset_top = 40
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiTheme.sticker(BANNER_FILL, 14, UiTheme.DROP_PILL, 4))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var word := Label.new()
	word.theme_type_variation = &"NameLabel"
	word.add_theme_font_size_override("font_size", 20)
	word.text = "Practice"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(word)
	_room_line.theme_type_variation = &"StatusLabel"
	_room_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_room_line)
	tag.add_child(text)
	var tilt := Tilt.new(tag, -2.0)
	tilt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.add_child(tilt)
	add_child(_banner)


func _build_restart() -> void:
	_restart.theme_type_variation = &"RoundButton"
	_restart.icon = RESTART_ICON
	_restart.tooltip_text = "Restart this room"
	_restart.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart.focus_mode = Control.FOCUS_NONE
	_restart.anchor_left = 1.0
	_restart.anchor_right = 1.0
	_restart.offset_left = -64
	_restart.offset_right = -16
	_restart.offset_top = 44
	_restart.offset_bottom = 92
	_restart.pressed.connect(restart_pressed.emit)
	add_child(_restart)


func _build_pause_rooms() -> void:
	_pause_rooms.text = "Back to rooms"
	_pause_rooms.icon = ROOMS_ICON
	_pause_rooms.focus_mode = Control.FOCUS_NONE
	_pause_rooms.anchor_left = 0.5
	_pause_rooms.anchor_right = 0.5
	_pause_rooms.anchor_top = 1.0
	_pause_rooms.anchor_bottom = 1.0
	_pause_rooms.offset_left = -110
	_pause_rooms.offset_right = 110
	_pause_rooms.offset_top = -120
	_pause_rooms.offset_bottom = -68
	_pause_rooms.pressed.connect(rooms_pressed.emit)
	add_child(_pause_rooms)


func _build_over() -> void:
	_over.color = UiTokens.SCRIM
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 28)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 44)
	_over.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Crashed"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(Tilt.new(title, -3.0))
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BigPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_room.theme_type_variation = &"MutedLabel"
	_over_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_room)
	_over_points.theme_type_variation = &"BigScoreLabel"
	_over_points.add_theme_font_size_override("font_size", 80)
	_over_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_points)
	var unit := Label.new()
	unit.theme_type_variation = &"MutedLabel"
	unit.text = "points this try"
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(unit)
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "Practice never counts for coins, best score, cleared rooms or leaderboards."
	box.add_child(note)
	panel.add_child(box)
	col.add_child(panel)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var again := Button.new()
	again.theme_type_variation = &"ActionButton"
	again.text = "Try again"
	again.icon = RESTART_ICON
	again.add_theme_font_size_override("font_size", 26)
	again.custom_minimum_size = Vector2(0, 64)
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(restart_pressed.emit)
	col.add_child(again)
	var rooms := Button.new()
	rooms.text = "Back to rooms"
	rooms.icon = ROOMS_ICON
	rooms.custom_minimum_size = Vector2(0, 52)
	rooms.focus_mode = Control.FOCUS_NONE
	rooms.pressed.connect(rooms_pressed.emit)
	col.add_child(rooms)
	var tap := Label.new()
	tap.theme_type_variation = &"SkyCaption"
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.text = "Or tap anywhere to try again."
	col.add_child(tap)
	add_child(_over)


## The room this practice repeats; empty = not practising (all hidden).
func set_room(room_name: String) -> void:
	_room_line.text = "%s, on repeat" % room_name
	_over_room.text = room_name
	visible = not room_name.is_empty()
	show_playing(false)


## While the room is being played (or waiting for the first tap).
func show_playing(paused: bool) -> void:
	_banner.visible = true
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


func room_line() -> String:
	return _room_line.text
