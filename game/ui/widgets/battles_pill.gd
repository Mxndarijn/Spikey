class_name BattlesPill
extends Button
## Home's battle log, kept small: one solid paper pill. With battles waiting
## for your turn: "Your turn in 2 battles" and See all; with none
## waiting: "Battle a friend" and Start. Either way a tap opens Battles.

const HEIGHT := 50.0
const BATTLE_ICON := preload("res://assets/ui/icons/battle.svg")
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
	icon.texture = BATTLE_ICON
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
	_more = UiKit.label("", &"SmallNameLabel", false)
	_more.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	row.add_child(_more)
	var chev := TextureRect.new()
	chev.texture = CHEVRON
	chev.modulate = UiTokens.ON_PANEL
	chev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chev.custom_minimum_size = Vector2(12, 12)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chev)
	set_turns(0)


## n battles wait for this player's turn.
func set_turns(n: int) -> void:
	# The count is in the words; a separate number badge read as a fragment.
	_count.visible = false
	_count.text = str(n)
	if n > 0:
		_text.text = turns_text(n)
		_more.text = "See all"
	else:
		_text.text = "Battle a friend"
		_more.text = "Start"


## "Your turn in 1 battle", "Your turn in 2 battles".
static func turns_text(n: int) -> String:
	return "Your turn in %d %s" % [n, "battle" if n == 1 else "battles"]


func line_text() -> String:
	return _text.text
