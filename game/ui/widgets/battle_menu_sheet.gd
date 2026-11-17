class_name BattleMenuSheet
extends Control
## A battle's menu (docs/DUEL_MODE.md, screen K2): Nudge (once a day, when it
## is the rival's turn), Close with no result (after 7 days waiting on the
## rival, any time against a bot), and Resign, each with a line saying what it
## does to the battle. Resign asks once more before it happens.

signal nudge_pressed
signal close_pressed
signal resign_pressed
signal closed

const CLOSE_NOTE := "Ends for both; counts for nobody. Possible after 7 days waiting."
const CLOSE_NOTE_BOT := "Ends the battle with no result."
const RESIGN_NOTE := "%s wins. From round 3 on it counts as your loss."
const SURE := "Resign? %s wins this battle"

var _nudge: Button
var _close: Button
var _resign: Button
var _sure := false
var _rival := ""


func _init(view: BattleView) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rival = view.rival_label()
	var parts := BattleKit.card_over_scrim(closed.emit)
	add_child(parts[0])
	var col: VBoxContainer = parts[1]
	var title := UiKit.label("Battle with %s" % _rival, &"NameLabel", false)
	title.add_theme_font_size_override("font_size", 22)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(UiKit.card_head(title, closed.emit))
	var line := UiKit.wrapped(view.status_line(), &"MutedLabel")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(line)
	_nudge = UiKit.row_button("Nudge %s" % _rival, UiTokens.PANEL_RAISED)
	_nudge.name = "Nudge"
	_nudge.disabled = not view.can_nudge
	_nudge.visible = not view.rival_bot and view.rival_name != ""
	_nudge.pressed.connect(nudge_pressed.emit)
	col.add_child(_nudge)
	_close = UiKit.row_button("Close, no result", UiTokens.PANEL_RAISED)
	_close.name = "Close"
	_close.disabled = not view.can_close
	_close.pressed.connect(close_pressed.emit)
	col.add_child(_close)
	col.add_child(_note(CLOSE_NOTE_BOT if view.rival_bot else CLOSE_NOTE))
	_resign = UiKit.action_button("Resign")
	_resign.name = "Resign"
	_resign.add_theme_color_override("font_color", UiTokens.ON_PRIMARY)
	var red := UiTheme.flat(UiTokens.DANGER, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		_resign.add_theme_stylebox_override(state, red)
	_resign.pressed.connect(_on_resign)
	_resign.visible = view.status in [BattleView.OPEN, BattleView.WAITING]
	col.add_child(_resign)
	col.add_child(_note(RESIGN_NOTE % _rival))


static func _note(text: String) -> Label:
	var l := UiKit.wrapped(text, &"MutedLabel")
	l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## The first press asks; the second resigns.
func _on_resign() -> void:
	if not _sure:
		_sure = true
		_resign.text = SURE % _rival
		return
	resign_pressed.emit()


func nudge_button() -> Button:
	return _nudge


func close_button() -> Button:
	return _close


func resign_button() -> Button:
	return _resign
