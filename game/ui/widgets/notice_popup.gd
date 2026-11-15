class_name NoticePopup
extends Control
## A short message over Home with one button: the fresh start after a server
## move, "please update" when the server is newer than this app, and "moved to
## another phone" after a transfer code was used elsewhere. A flat paper card
## over the dimmed room (the Design Kit's popup), title, a line and the button.

signal closed

const SIDE := 28
const TEXT_WIDTH := 240.0

## The notices (title, text, button), by id.
const FRESH_START := "fresh_start"
const UPDATE := "update"
const MOVED := "moved"
const TEXTS := {
	FRESH_START:
	[
		"Fresh start",
		"Flapjaw has a new server, so scores, coins and items start over.",
		"Play",
	],
	UPDATE:
	[
		"Update Flapjaw",
		"This version can't reach the leaderboards any more. Update the app to keep your runs counting.",
		"OK",
	],
	MOVED:
	[
		"Moved to another phone",
		"Your progress is on your new phone now. This phone starts over as a new player.",
		"Play",
	],
}

var id := ""
var _title := Label.new()
var _text: Label
var _button: Button


func _init(notice_id: String) -> void:
	id = notice_id
	var words: Array = TEXTS.get(notice_id, ["", "", "OK"])
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_4)
	card.add_child(col)
	_title.theme_type_variation = &"NameLabel"
	_title.text = str(words[0])
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_text = UiKit.wrapped(str(words[1]), &"MutedLabel", TEXT_WIDTH)
	col.add_child(_text)
	_button = UiKit.action_button(str(words[2]))
	_button.pressed.connect(closed.emit)
	col.add_child(_button)


func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _text.text


func button() -> Button:
	return _button
