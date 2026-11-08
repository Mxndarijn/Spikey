class_name NameDialog
extends Control
## Picks the name other players see on the leaderboards: a card high on the
## screen (so the phone keyboard never covers it) over a dark scrim, with a
## suggested name, a dice button for another suggestion, the rules, and Save.
## The first time there is no way out but Save; later "Keep <name>" closes it.

signal saved(player_name: String)
signal cancelled

const DICE_ICON := preload("res://assets/ui/icons/dice.svg")
const TOP := 92
const FIELD_H := 52.0
const RULES := "3 to 14 letters, numbers, dots or underscores."

var _field := LineEdit.new()
var _hint := Label.new()
var _save := Button.new()
var _rng := RandomNumberGenerator.new()


func _init(current_name: String, flyer_id: String) -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", UiTokens.SPACE_4)
	margin.add_theme_constant_override("margin_right", UiTokens.SPACE_5 - 4)
	margin.add_theme_constant_override("margin_top", TOP)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(LeaderboardRow.icon(LeaderboardRow.flyer_texture(flyer_id), 48))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.text = "Change your name" if not current_name.is_empty() else "Pick a leaderboard name"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(180, 0)
	words.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"MutedLabel"
	sub.text = "Everyone sees it next to your scores."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(180, 0)
	words.add_child(sub)
	head.add_child(words)
	col.add_child(head)

	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.add_theme_font_override("font", GameFonts.ui(900))
	label.text = "Leaderboard name"
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
	var dice := Button.new()
	dice.theme_type_variation = &"RoundButton"
	dice.icon = DICE_ICON
	dice.tooltip_text = "Suggest a random name"
	dice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice.custom_minimum_size = Vector2(FIELD_H, FIELD_H)
	dice.focus_mode = Control.FOCUS_NONE
	dice.pressed.connect(shuffle)
	line.add_child(dice)
	col.add_child(line)
	_hint.theme_type_variation = &"StatusLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(240, 0)
	col.add_child(_hint)
	_save.theme_type_variation = &"ActionButton"
	_save.text = "Save name"
	_save.custom_minimum_size = Vector2(0, 56)
	_save.focus_mode = Control.FOCUS_NONE
	_save.pressed.connect(_on_submit)
	col.add_child(_save)
	if not current_name.is_empty():
		var keep := Button.new()
		keep.text = "Keep %s" % current_name
		keep.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		keep.focus_mode = Control.FOCUS_NONE
		keep.pressed.connect(cancelled.emit)
		col.add_child(keep)
	_check()


func _style_field() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.PANEL
	box.set_border_width_all(UiTheme.BORDER)
	box.border_color = UiTokens.INK_LINE
	box.set_corner_radius_all(14)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.anti_aliasing = true
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = UiTokens.INK_900
	_field.add_theme_stylebox_override("normal", box)
	_field.add_theme_stylebox_override("focus", focus)
	_field.add_theme_font_override("font", GameFonts.display())
	_field.add_theme_font_size_override("font_size", 20)
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
	_hint.text = RULES if problem.is_empty() else problem
	var color := UiTokens.ON_PANEL_MUTED if problem.is_empty() else UiTokens.DANGER
	_hint.add_theme_color_override("font_color", color)
	_save.disabled = not problem.is_empty()


func _on_submit() -> void:
	if can_save():
		saved.emit(_field.text)
