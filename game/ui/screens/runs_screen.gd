class_name RunsScreen
extends Control
## Your runs (minimal kit): the back arrow and the title, a paper tab bar
## (Latest, Saved 3/20), one line on what the tab keeps, and a scrolling list
## of RunRow cards. Latest holds the last RunHistory.LATEST_MAX runs on this
## phone; the bookmark saves a run into Saved (up to RunHistory.SAVED_MAX),
## where it stays until it is removed. Watch plays the run back in the room.

signal closed
signal watch_requested(record: RunRecord)

const LATEST := "latest"
const SAVED := "saved"
const SIDE := UiKit.SCREEN_SIDE
const TOP := UiKit.SCREEN_TOP
const BOTTOM := 40
const GAP := 8
const LATEST_HINT := "Your last 100 runs stay on this phone. Save one to keep it."
const SAVED_HINT := "Saved runs stay until you remove them."
const FULL_HINT := "Saved is full. Remove a saved run first."
const LATEST_EMPTY := "No runs yet. Play one and it shows up here."
const SAVED_EMPTY := "Nothing saved yet. Tap the bookmark on a run to keep it."

## Unix time the "when" lines are counted from; tests can set it.
var now := 0
var bias_minutes := 0

var _store: RunStore
var _tab := LATEST
var _tabs := {}
var _hint: Label
var _list := VBoxContainer.new()
var _scroll := SmoothScroll.new()
var _rows: Array[RunRow] = []
var _empty: Label


func _init(store: RunStore, tab: String = LATEST) -> void:
	_store = store
	_tab = tab if tab == SAVED else LATEST
	now = int(Time.get_unix_time_from_system())
	bias_minutes = int(Time.get_time_zone_from_system().get("bias", 0))


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", TOP)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var header := UiKit.header("Your runs", closed.emit)
	var title := header.get_node("Title") as Label
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(header)
	col.add_child(_tab_bar())
	_hint = UiKit.wrapped("", &"RoomMuted", 0.0)
	col.add_child(_hint)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", GAP)
	_scroll.add_child(_list)
	col.add_child(FadeMask.new(_scroll))
	show_tab(_tab)


func _tab_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TabStrip"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	bar.add_child(tabs)
	var group := ButtonGroup.new()
	for id in [LATEST, SAVED]:
		var tab := Button.new()
		tab.name = id.capitalize()
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(show_tab.bind(id))
		_tabs[id] = tab
		tabs.add_child(tab)
	_update_tab_names()
	return bar


func _update_tab_names() -> void:
	(_tabs[LATEST] as Button).text = "Latest"
	(_tabs[SAVED] as Button).text = (
		"Saved %d/%d" % [_store.history.saved_count(), RunHistory.SAVED_MAX]
	)


## Shows the Latest or the Saved runs.
func show_tab(id: String) -> void:
	_tab = id if id == SAVED else LATEST
	(_tabs[_tab] as Button).button_pressed = true
	_hint.text = SAVED_HINT if _tab == SAVED else LATEST_HINT
	_fill()
	_scroll.scroll_vertical = 0


func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_empty = null
	var records := _store.history.saved() if _tab == SAVED else _store.history.latest()
	if records.is_empty():
		_empty = UiKit.wrapped(SAVED_EMPTY if _tab == SAVED else LATEST_EMPTY, &"SkyCaption")
		_list.add_child(UiKit.spacer(24))
		_list.add_child(_empty)
	for r in records:
		var row := RunRow.new(r, now, bias_minutes)
		row.watch_pressed.connect(watch_requested.emit)
		row.save_pressed.connect(_toggle_saved)
		_list.add_child(row)
		_rows.append(row)
	_list.add_child(UiKit.spacer(FadeMask.FADE))
	_update_tab_names()


## The bookmark: saves the run, or takes it out of Saved. On Saved the row
## goes; on Latest it stays and its bookmark empties.
func _toggle_saved(r: RunRecord) -> void:
	if not r.saved and _store.history.is_saved_full():
		_hint.text = FULL_HINT
		return
	_store.set_saved(r.id, not r.saved)
	_hint.text = SAVED_HINT if _tab == SAVED else LATEST_HINT
	if _tab == SAVED or _store.history.find(r.id) == null:
		var keep := _scroll.scroll_vertical
		_fill()
		_scroll.scroll_vertical = keep
		return
	for row in _rows:
		if row.record == r:
			row.refresh()
	_update_tab_names()


func tab() -> String:
	return _tab


func rows() -> Array[RunRow]:
	return _rows


func hint_text() -> String:
	return _hint.text


func tab_text(id: String) -> String:
	return (_tabs[id] as Button).text


func empty_text() -> String:
	return _empty.text if _empty != null else ""
