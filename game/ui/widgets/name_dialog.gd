class_name NameDialog
extends Control
## Picks the name other players see on the leaderboards (minimal kit): a flat
## paper card high on the screen (so the phone keyboard never covers the field)
## over a dark scrim, with a suggested name, a dice button for another
## suggestion, the rules, and Save. The first time there is no way out but
## Save; later "Keep <name>" closes it.

signal saved(player_name: String)
signal cancelled

const DICE_ICON := preload("res://assets/ui/icons/dice.svg")
const TOP := 120
const SIDE := 24
const FIELD_H := 48.0
## Says what LeaderboardService.name_problem() accepts.
const RULES := "%d to %d letters, numbers, dots or underscores."

var _field := LineEdit.new()
var _hint := Label.new()
var _save := Button.new()
var _rng := RandomNumberGenerator.new()


## `_flyer_id` is no longer drawn (the card has no picture); kept for callers.
func _init(current_name: String, _flyer_id: String = "") -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", TOP)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)

	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.text = "Change your name" if not current_name.is_empty() else "Pick your name"
	col.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"MutedLabel"
	sub.add_theme_font_override("font", GameFonts.ui(600))
	sub.add_theme_font_size_override("font_size", 14)
	sub.text = "This is how you show up on the leaderboards. You can change it later."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(200, 0)
	col.add_child(sub)

	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.add_theme_font_override("font", GameFonts.ui(800))
	label.add_theme_font_size_override("font_size", 13)
	label.text = "Name"
	col.add_child(label)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiTokens.SPACE_2)
	_style_field()
	_field.max_length = LeaderboardService.NAME_MAX
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.custom_minimum_size = Vector2(0, FIELD_H)
	_field.text = current_name if not current_name.is_empty() else suggestion()
	_field.text_changed.connect(_check.unbind(1))
	_field.text_submitted.connect(_on_submit.unbind(1))
	line.add_child(_field)
	line.add_child(_dice())
	col.add_child(line)
	_hint.theme_type_variation = &"MutedLabel"
	_hint.add_theme_font_override("font", GameFonts.ui(600))
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(200, 0)
	col.add_child(_hint)
	_save.theme_type_variation = &"ActionButton"
	_save.text = "Save name"
	_save.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	_save.focus_mode = Control.FOCUS_NONE
	_save.pressed.connect(_on_submit)
	col.add_child(_save)
	if not current_name.is_empty():
		var keep := Button.new()
		keep.theme_type_variation = &"InkButton"
		keep.text = "Keep %s" % current_name
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			keep.add_theme_color_override(state, UiTokens.ON_PANEL)
		keep.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		keep.focus_mode = Control.FOCUS_NONE
		keep.pressed.connect(cancelled.emit)
		col.add_child(keep)
	_check()


## The 48px round dice on the soft edge colour, an ink icon.
func _dice() -> Button:
	var dice := Button.new()
	dice.theme_type_variation = &"InkButton"
	dice.icon = DICE_ICON
	dice.tooltip_text = "Suggest a random name"
	dice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice.custom_minimum_size = Vector2(FIELD_H, FIELD_H)
	dice.focus_mode = Control.FOCUS_NONE
	var disc := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
	var down := UiTheme.flat(UiTokens.EDGE.darkened(0.08), UiTokens.RADIUS_PILL, 0)
	dice.add_theme_stylebox_override("normal", disc)
	dice.add_theme_stylebox_override("hover", disc)
	dice.add_theme_stylebox_override("pressed", down)
	dice.add_theme_stylebox_override("hover_pressed", down)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		dice.add_theme_color_override(state, UiTokens.ON_PANEL)
	dice.add_theme_color_override("icon_hover_pressed_color", UiTokens.ON_PANEL)
	dice.pressed.connect(shuffle)
	return dice


## A form field, so it keeps a 3px ink border: a white pill, 800/16 text.
func _style_field() -> void:
	var box := UiTheme.ringed(Color.WHITE, UiTokens.RADIUS_PILL, 0, UiTokens.INK_LINE, 3)
	box.content_margin_left = UiTokens.SPACE_4
	box.content_margin_right = UiTokens.SPACE_4
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = UiTokens.INK_900
	_field.add_theme_stylebox_override("normal", box)
	_field.add_theme_stylebox_override("focus", focus)
	_field.add_theme_font_override("font", GameFonts.ui(800))
	_field.add_theme_font_size_override("font_size", 16)
	_field.add_theme_color_override("font_color", UiTokens.ON_PANEL)
	_field.add_theme_color_override("caret_color", UiTokens.ON_PANEL)
	_field.add_theme_color_override("font_placeholder_color", UiTokens.ON_PANEL_MUTED)
	_field.placeholder_text = "Your name"


## A new random name in the field.
func shuffle() -> void:
	set_draft(suggestion())


func suggestion() -> String:
	return LeaderboardService.suggest_name(_rng)


func set_draft(text: String) -> void:
	_field.text = text
	_check()


func draft() -> String:
	return _field.text


func can_save() -> bool:
	return not _save.disabled


func hint_text() -> String:
	return _hint.text


## Shows the rules, or what is wrong in red, and only allows Save when valid.
func _check() -> void:
	var problem := LeaderboardService.name_problem(_field.text)
	var rules := RULES % [LeaderboardService.NAME_MIN, LeaderboardService.NAME_MAX]
	_hint.text = rules if problem.is_empty() else problem
	var color := UiTokens.ON_PANEL_MUTED if problem.is_empty() else UiTokens.DANGER
	_hint.add_theme_color_override("font_color", color)
	_save.disabled = not problem.is_empty()


func _on_submit() -> void:
	if can_save():
		saved.emit(_field.text)
