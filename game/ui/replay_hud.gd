class_name ReplayHud
extends Control
## The HUD for watching a leaderboard run, in the minimal kit like PracticeHud:
## a small ink chip "Replay: Noor, 31" at the top and a bare close icon top
## left that leaves. When the run ends, the dimmed room shows "Noor scored 31",
## the round Watch again and Back. A run that can't be played shows only its
## message and Back. Hud owns it and shows it only while replaying; the score
## stays Hud's.

signal again_pressed
signal back_pressed
## Shown, hidden, or the result screen came up (Hud follows it).
signal changed

const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const RESTART_ICON := preload("res://assets/ui/icons/restart.svg")
const CHIP_TOP := 48.0
const CHIP_H := 34.0

var _banner := PanelContainer.new()
var _line := Label.new()
var _exit: Button
var _over := ColorRect.new()
var _over_title := Label.new()
var _again: Button
var _player := ""
var _score := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_banner()
	_build_exit()
	_build_over()
	set_run("", 0)


func _build_banner() -> void:
	var chip := UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, 0)
	chip.content_margin_left = 14
	chip.content_margin_right = 14
	_banner.add_theme_stylebox_override("panel", chip)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.theme_type_variation = &"OnInkLabel"
	_line.add_theme_font_size_override("font_size", 14)
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.custom_minimum_size = Vector2(0, CHIP_H)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_line)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = CHIP_TOP
	_banner.offset_bottom = CHIP_TOP + CHIP_H
	add_child(_banner)


func _build_exit() -> void:
	_exit = UiKit.icon_button(CLOSE_ICON, "Stop watching")
	_exit.name = "ExitReplay"
	_exit.add_theme_constant_override("icon_max_width", 24)
	_place_exit(UiKit.ICON_BUTTON)
	_exit.pressed.connect(back_pressed.emit)
	add_child(_exit)


func _place_exit(side: float) -> void:
	_exit.custom_minimum_size = Vector2(side, side)
	_exit.size = Vector2(side, side)
	_exit.position = Vector2(10, 42)


## Settings > Large buttons.
func set_large_buttons(on: bool) -> void:
	_place_exit(UiKit.LARGE_BUTTON if on else UiKit.ICON_BUTTON)


func _build_over() -> void:
	_over.color = UiTokens.SCRIM
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_box := MarginContainer.new()
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_theme_constant_override("margin_left", 40)
	title_box.add_theme_constant_override("margin_right", 40)
	_over_title.theme_type_variation = &"ScrimTitle"
	_over_title.add_theme_font_size_override("font_size", 32)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(_over_title)
	_at(title_box, 150)
	_again = UiKit.primary(RESTART_ICON, "Watch again", true)
	_again.name = "WatchAgain"
	_again.anchor_left = 0.5
	_again.anchor_right = 0.5
	_again.offset_left = -UiKit.PRIMARY / 2.0
	_again.offset_right = UiKit.PRIMARY / 2.0
	_again.offset_top = 330
	_again.offset_bottom = 330 + UiKit.PRIMARY
	_again.pressed.connect(again_pressed.emit)
	_over.add_child(_again)
	var back := CenterContainer.new()
	back.name = "Back"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.theme_type_variation = &"ScrimButton"
	b.text = "Back"
	b.icon = BACK_ICON
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.add_theme_constant_override("icon_max_width", 20)
	b.pressed.connect(back_pressed.emit)
	back.add_child(b)
	_at(back, 470)
	add_child(_over)


func _at(c: Control, top: float) -> void:
	_over.add_child(c)
	c.anchor_right = 1.0
	c.offset_top = top
	c.offset_bottom = top + c.get_combined_minimum_size().y


## The run being watched; an empty name = not replaying (all hidden).
func set_run(player: String, score: int) -> void:
	_player = player
	_score = score
	_line.text = "Replay: %s, %d" % [player, score]
	visible = not player.is_empty()
	show_playing()
	changed.emit()


func show_playing() -> void:
	_banner.visible = true
	_exit.visible = true
	_over.visible = false
	changed.emit()


## The run played out: "Noor scored 31", Watch again and Back.
func show_over() -> void:
	_over_title.text = "%s scored %d" % [_player, _score]
	_again.visible = true
	_show_over_screen()


## The run can't be played: just the message and Back.
func show_message(text: String) -> void:
	visible = true
	_over_title.text = text
	_again.visible = false
	_show_over_screen()


func _show_over_screen() -> void:
	_banner.visible = false
	_exit.visible = false
	_over.visible = true
	changed.emit()


func is_over_showing() -> bool:
	return visible and _over.visible


func can_watch_again() -> bool:
	return is_over_showing() and _again.visible


func title_text() -> String:
	return _over_title.text


func chip_text() -> String:
	return _line.text
