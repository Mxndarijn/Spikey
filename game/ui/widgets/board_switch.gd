class_name BoardSwitch
extends PanelContainer
## The leaderboards' Scores | Wins switch (docs/DUEL_MODE.md, screen L1): a
## small paper pill with two halves in the header's right slot, the board in
## view in ink. A tap on the other half emits `picked`.

signal picked(index: int)

const SCORES := 0
const WINS := 1
const NAMES: Array[String] = ["Scores", "Wins"]

var _buttons: Array[Button] = []


func _init(on: int) -> void:
	name = "BoardSwitch"
	var bar := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	bar.content_margin_top = 3
	bar.content_margin_bottom = 3
	add_theme_stylebox_override("panel", bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	for i in NAMES.size():
		var b := Button.new()
		b.name = NAMES[i]
		b.text = NAMES[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN - 6)
		b.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
		var fill := UiTokens.PRIMARY if i == on else UiTokens.PANEL
		var text := UiTokens.ON_PRIMARY if i == on else UiTokens.ON_PANEL_MUTED
		var box := UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0)
		box.content_margin_left = UiTokens.SPACE_3
		box.content_margin_right = UiTokens.SPACE_3
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(state, box)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, text)
		b.pressed.connect(_on_pressed.bind(i, on))
		row.add_child(b)
		_buttons.append(b)


func _on_pressed(i: int, on: int) -> void:
	if i != on:
		picked.emit(i)


func button(i: int) -> Button:
	return _buttons[i]
