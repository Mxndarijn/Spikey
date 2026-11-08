class_name RoomsScreen
extends Control
## Every room kind, for practice (Sticker Pop): a back button, the title and how
## many rooms the player has cleared in real runs, tabs that jump to a group,
## and a scrolling list of groups with a card per room. A room opens for
## practice once a real run has met it.

signal closed
signal room_opened(id: String)

const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const CHECK_ICON := preload("res://assets/ui/icons/check.svg")
## Two cards per row, so each card has room for its picture, name and status.
const COLUMNS := 2
## Keeps every card, tab and pill clear of the screen edges.
const SIDE := 20
const NOTES := {
	"starter": "Clear a room by surviving all 10 of its points in a real run.",
	"seasonal":
	(
		"Seasonal rooms show up in runs during their season."
		+ " Once you have met one, you can practice it all year."
	),
}

var _profile: Profile
var _scroll := ScrollContainer.new()
var _sections := {}
var _selected := ""
var _tabs := {}
var _cards: Array[RoomCard] = []
var _cleared := Label.new()
var _dev: Control


func _init(profile: Profile) -> void:
	_profile = profile


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_6)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	margin.add_child(col)
	col.add_child(_header())
	col.add_child(_tab_bar())
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UiTokens.SPACE_4)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Room for the cards' drop shadows inside the scroll area.
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_bottom", 40)
	pad.add_child(list)
	_scroll.add_child(pad)
	col.add_child(_scroll)
	for g in RoomInfo.GROUPS:
		var section := _section(g)
		_sections[g] = section
		list.add_child(section)
	_cleared.text = "%d cleared" % _profile.total_clears()
	_select_tab("starter")


func _header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	var back := Button.new()
	back.theme_type_variation = &"RoundButton"
	back.icon = BACK_ICON
	back.tooltip_text = "Back"
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(closed.emit)
	row.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 32)
	title.text = "Rooms"
	var tilt := Tilt.new(title, -3.0)
	tilt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tilt)
	if DevMode.enabled():
		row.add_child(_dev_tag())
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"PillPanel"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := PanelContainer.new()
	badge.theme_type_variation = &"UsePill"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var check := TextureRect.new()
	check.texture = CHECK_ICON
	check.custom_minimum_size = Vector2(12, 12)
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.modulate = UiTokens.INK_LINE
	badge.add_child(check)
	inner.add_child(badge)
	_cleared.theme_type_variation = &"CoinLabel"
	_cleared.add_theme_font_size_override("font_size", 16)
	inner.add_child(_cleared)
	pill.add_child(inner)
	row.add_child(pill)
	return row


## "DEV": every room is open because the game runs from the editor or a debug build.
func _dev_tag() -> Control:
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override(
		"panel", UiTheme.sticker(UiTokens.INK_LINE, UiTokens.RADIUS_S, Vector2.ZERO, 4)
	)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.tooltip_text = "Developer mode: every room is open for practice"
	var l := Label.new()
	l.theme_type_variation = &"StatusLabel"
	l.add_theme_color_override("font_color", UiTokens.PANEL)
	l.text = "DEV"
	tag.add_child(l)
	_dev = tag
	return tag


func has_dev_tag() -> bool:
	return _dev != null


func _tab_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TabStrip"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	bar.add_child(tabs)
	var group := ButtonGroup.new()
	for g in RoomInfo.GROUPS:
		var tab := Button.new()
		tab.theme_type_variation = &"TabButton"
		tab.add_theme_font_size_override("font_size", 12)
		_tight(tab)
		tab.text = (RoomInfo.GROUP_NAMES[g] as String).replace("-game", "")
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_select_tab.bind(g))
		_tabs[g] = tab
		tabs.add_child(tab)
	return bar


## Five tabs share the bar, so they keep only a little padding.
## Copies the style from UiTheme directly: the tab isn't in the tree yet, so
## its own get_theme_stylebox() would return Godot's grey default buttons.
func _tight(tab: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := UiTheme.get_theme().get_stylebox(state, &"TabButton").duplicate() as StyleBox
		box.content_margin_left = 2
		box.content_margin_right = 2
		tab.add_theme_stylebox_override(state, box)


func _section(g: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var rooms := RoomInfo.rooms_in(g)
	var open := 0
	for def in rooms:
		if RoomInfo.is_open(_profile, def):
			open += 1
	var head := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"SkyLabel"
	title.add_theme_font_size_override("font_size", 22)
	title.text = RoomInfo.GROUP_NAMES[g]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var count := Label.new()
	count.theme_type_variation = &"SkyCaption"
	count.text = "%d of %d open" % [open, rooms.size()]
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)
	box.add_child(head)
	if NOTES.has(g):
		var note := PanelContainer.new()
		note.theme_type_variation = &"HintPill"
		note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var text := Label.new()
		text.theme_type_variation = &"StatusLabel"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(280, 0)
		text.text = NOTES[g]
		note.add_child(text)
		box.add_child(note)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for def in rooms:
		var card := RoomCard.new(_profile, def)
		card.pressed.connect(room_opened.emit.bind(def.id))
		grid.add_child(card)
		_cards.append(card)
	box.add_child(grid)
	return box


## Highlights a group's tab and shows only that group's rooms, from the top.
func _select_tab(g: String) -> void:
	_selected = g
	if _tabs.has(g):
		(_tabs[g] as Button).button_pressed = true
	for key: String in _sections:
		(_sections[key] as Control).visible = key == g
	_scroll.scroll_vertical = 0


func selected_group() -> String:
	return _selected


## The cards of the selected tab (the ones on screen).
func visible_cards() -> Array[RoomCard]:
	var out: Array[RoomCard] = []
	for card in _cards:
		if card.is_visible_in_tree():
			out.append(card)
	return out


func cards() -> Array[RoomCard]:
	return _cards


func cleared_text() -> String:
	return _cleared.text
