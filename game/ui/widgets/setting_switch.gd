class_name SettingSwitch
extends Button
## One on/off setting in the settings sheet: the name (15/800) and a muted hint
## on the left, a 52x30 switch on the right (ink when on, soft edge when off,
## a white knob). The whole row is the tap target (46px tall, so five fit the sheet).

const SWITCH := Vector2(52, 30)
const KNOB := 24.0
const ROW_H := 46.0

var _name := Label.new()
var _hint := Label.new()


func _init(title: String, hint: String) -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	tooltip_text = title
	custom_minimum_size = Vector2(0, ROW_H)
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, clear)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_right = -(SWITCH.x + UiTokens.SPACE_3)
	add_child(col)
	_name.theme_type_variation = &"InkLabel"
	_name.text = title
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name)
	_hint.theme_type_variation = &"MutedLabel"
	_hint.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	_hint.text = hint
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_hint)
	toggled.connect(queue_redraw.unbind(1))


func title() -> String:
	return _name.text


func _draw() -> void:
	var r := Rect2(Vector2(size.x - SWITCH.x, (size.y - SWITCH.y) / 2.0), SWITCH)
	var on := button_pressed
	var track := UiTheme.flat(UiTokens.INK_LINE if on else UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
	draw_style_box(track, r)
	var pad := (SWITCH.y - KNOB) / 2.0
	var x := r.end.x - pad - KNOB / 2.0 if on else r.position.x + pad + KNOB / 2.0
	draw_circle(
		Vector2(x, r.position.y + SWITCH.y / 2.0), KNOB / 2.0, Color.WHITE, true, -1.0, true
	)
