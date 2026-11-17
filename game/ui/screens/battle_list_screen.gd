class_name BattleListScreen
extends Control
## Battles (docs/DUEL_MODE.md, screen B1): the back arrow and the title, then
## the player's battles in three groups, Your turn first, then Their turn, then
## Finished (the last 30 days), each a paper row with the rival (and the BOT
## pill for a bot), what happens next and the score; New battle on the action
## line. Shows loading and offline too. The list comes from BattleService.

signal closed
signal battle_picked(battle: int)
signal new_pressed
## Offline: try again.
signal refresh_requested

const NEW_ICON := preload("res://assets/ui/icons/play.svg")
const TITLE := "Battles"
const SIDE := UiKit.SCREEN_SIDE
const TOP := UiKit.SCREEN_TOP
const LIST_TOP := TOP + UiKit.HEADER_HEIGHT + 12.0
const LOADING := "Loading your battles"
const EMPTY := "No battles yet. Start one: a friend or a random rival."

var _list: VBoxContainer
var _note: Label
var _primary: Button
var _battles: Array[BattleView] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var head := UiKit.header(TITLE, closed.emit)
	add_child(head)
	head.anchor_right = 1.0
	head.offset_left = SIDE
	head.offset_right = -SIDE
	head.offset_top = TOP
	head.offset_bottom = TOP + UiKit.HEADER_HEIGHT
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.anchor_right = 1.0
	scroll.offset_left = SIDE
	scroll.offset_right = -SIDE
	scroll.offset_top = LIST_TOP
	scroll.offset_bottom = UiKit.ACTION_TOP - 12.0
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", UiTokens.SPACE_2)
	scroll.add_child(_list)
	_note = UiKit.wrapped(LOADING, &"RoomMuted", 300)
	_list.add_child(_note)
	_primary = UiKit.primary(NEW_ICON, "New")
	_primary.name = "Primary"
	_primary.tooltip_text = "New battle"
	_primary.pressed.connect(new_pressed.emit)
	UiKit.place_primary(self, _primary)


## The battles arrived (your turn first, as the server sends them).
func show_battles(battles: Array[BattleView]) -> void:
	_battles = battles
	for c in _list.get_children():
		c.queue_free()
	_note = null
	if battles.is_empty():
		_note = UiKit.wrapped(EMPTY, &"RoomMuted", 300)
		_list.add_child(_note)
		return
	var groups := [
		["Your turn", battles.filter(func(b: BattleView) -> bool: return b.my_turn())],
		[
			"Their turn",
			battles.filter(func(b: BattleView) -> bool: return not b.is_over() and not b.my_turn())
		],
		["Finished", battles.filter(func(b: BattleView) -> bool: return b.is_over())],
	]
	for g: Array in groups:
		var list: Array = g[1]
		if list.is_empty():
			continue
		var label := UiKit.label(str(g[0]).to_upper(), &"SkyCaption", false)
		label.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
		_list.add_child(label)
		for b: BattleView in list:
			var row := BattleKit.row(b)
			row.pressed.connect(battle_picked.emit.bind(b.id))
			_list.add_child(row)


## No server or no answer: a line and Retry on the action line.
func show_offline(message: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	_note = UiKit.wrapped(message, &"RoomMuted", 300)
	_list.add_child(_note)
	var retry := UiKit.text_button("Try again", &"PlainButton")
	retry.name = "Retry"
	retry.pressed.connect(refresh_requested.emit)
	_list.add_child(retry)


## This app is older than the server's game: Battle waits for the update.
func show_update(message: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	_note = UiKit.wrapped(message, &"RoomMuted", 300)
	_list.add_child(_note)
	var update := UiKit.text_button(GameModes.UPDATE_LINE, &"PlainButton")
	update.name = "Update"
	update.pressed.connect(StoreLink.open)
	_list.add_child(update)
	_primary.disabled = true


func battles() -> Array[BattleView]:
	return _battles


func rows() -> Array[Button]:
	var out: Array[Button] = []
	for c in _list.get_children():
		if c is Button and c.name.begins_with("Battle"):
			out.append(c as Button)
	return out


func note_text() -> String:
	return _note.text if _note != null else ""


## How many of the battles wait for this player (the Home card's badge).
static func turns_waiting(battles: Array[BattleView]) -> int:
	return battles.filter(func(b: BattleView) -> bool: return b.my_turn()).size()
