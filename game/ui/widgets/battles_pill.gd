class_name BattlesPill
extends Button
## Home's battle log, kept small: one solid paper pill. With battles waiting
## for your turn: a gold count, "battles: your turn" and See all; with none
## waiting: "Battle a friend" and New. Either way a tap opens Battles.

const HEIGHT := 50.0
const TROPHY := preload("res://assets/ui/icons/trophy.svg")
const CHEVRON := preload("res://assets/ui/icons/chevron.svg")

var _count: Label
var _text: Label
var _more: Label


func _init() -> void:
	name = "Battles"
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Battles"
	custom_minimum_size = Vector2(0, HEIGHT)
	var box := UiTheme.solid(UiTokens.PANEL)
	var down := UiTheme.solid(UiTokens.PANEL_RAISED)
	for state in ["normal", "hover", "focus", "disabled"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, down)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -14
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	add_child(row)
	var disc := PanelContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.custom_minimum_size = Vector2(34, 34)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override(
		"panel", UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, 0)
	)
	var icon := TextureRect.new()
	icon.texture = TROPHY
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(18, 18)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(icon)
	row.add_child(disc)
	_count = Badge.make("")
	_count.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_LABEL)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_count)
	_text = UiKit.label("", &"SmallNameLabel", false)
	_text.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_LABEL)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.clip_text = true
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_text)
	_more = UiKit.label("", &"MutedLabel", false)
	_more.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	row.add_child(_more)
	var chev := TextureRect.new()
	chev.texture = CHEVRON
	chev.modulate = UiTokens.ON_PANEL_MUTED
	chev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chev.custom_minimum_size = Vector2(12, 12)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chev)
	set_turns(0)


## n battles wait for this player's turn.
func set_turns(n: int) -> void:
	_count.visible = n > 0
	_count.text = str(n)
	if n > 0:
		_text.text = "%s: your turn" % ("battle" if n == 1 else "battles")
		_more.text = "See all"
	else:
		_text.text = "Battle a friend"
		_more.text = "New"


func line_text() -> String:
	return ("%s %s" % [_count.text, _text.text]) if _count.visible else _text.text
