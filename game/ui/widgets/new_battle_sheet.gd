class_name NewBattleSheet
extends Control
## New battle (docs/DUEL_MODE.md, screen B2): a paper card over the dimmed room.
## Invite a friend (a code to send), a random rival (a player, or a bot when no
## one is free), or a friend's code typed in. Every battle is first to 6 round
## wins with no time limit; the line under the title says how many are going.

signal invite_pressed
signal random_pressed
signal join_pressed(code: String)
signal closed

const RANDOM_NOTE := "A player, or a bot when no one is free"
const RULES := "First to 6 round wins · No time limit"
const CODE_LENGTH := 6

var _field := LineEdit.new()
var _join: Button


## `open`: battles going now.
func _init(open: int = 0) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var parts := BattleKit.card_over_scrim(closed.emit)
	add_child(parts[0])
	var col: VBoxContainer = parts[1]
	var title := UiKit.label("New battle", &"NameLabel", false)
	col.add_child(UiKit.card_head(title, closed.emit))
	var rules := UiKit.wrapped(
		"%s · %d of %d going" % [RULES, open, MatchRules.MAX_OPEN], &"MutedLabel"
	)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(rules)
	var invite := UiKit.action_button("Invite a friend")
	invite.name = "Invite"
	invite.pressed.connect(invite_pressed.emit)
	col.add_child(invite)
	var random := UiKit.row_button("Random rival", UiTokens.PANEL_RAISED)
	random.name = "Random"
	random.pressed.connect(random_pressed.emit)
	col.add_child(random)
	var note := UiKit.label(RANDOM_NOTE, &"MutedLabel")
	note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	col.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	col.add_child(row)
	_field.name = "Code"
	_field.placeholder_text = "Friend's code"
	_field.max_length = CODE_LENGTH + 1
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	_field.text_changed.connect(func(_t: String) -> void: _join.disabled = not code_ok())
	_field.text_submitted.connect(func(_t: String) -> void: _on_join())
	row.add_child(_field)
	_join = UiKit.text_button("Join", &"InkButton")
	_join.name = "Join"
	_join.disabled = true
	_join.pressed.connect(_on_join)
	row.add_child(_join)


## The typed code without spaces or dashes, in capitals.
func code() -> String:
	return clean(_field.text)


static func clean(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func code_ok() -> bool:
	return code().length() == CODE_LENGTH


func field() -> LineEdit:
	return _field


func _on_join() -> void:
	if code_ok():
		join_pressed.emit(code())
