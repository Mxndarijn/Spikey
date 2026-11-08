class_name RoomsScreen
extends Control
## Every room kind, for practice (minimal kit): a back arrow, the title and how
## many rooms the player has cleared in real runs (a check and the number), a
## paper tab bar with the room groups, the group's "5 of 8 open" line on the
## room, and a scrolling two-column grid of flat paper room cards. A room opens
## for practice once a real run has met it.

signal closed
signal room_opened(id: String)

const CHECK_ICON := preload("res://assets/ui/icons/check.svg")
## Two cards per row, so each card has room for its picture, name and status.
const COLUMNS := 2
## Keeps the header, tabs and cards clear of the screen edges.
const SIDE := 14
const TOP := 40
## The list stops this far above the bottom of the screen.
const BOTTOM := 40
const GAP := 10
## The group line sits a little further in than the cards (20px from the edge).
const CAPTION_INSET := 6
## Groups that need a word more than "5 of 8 open".
const NOTES := {
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
	margin.add_theme_constant_override("margin_top", TOP)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	margin.add_child(col)
	col.add_child(UiKit.header("Rooms", closed.emit, _clears()))
	col.add_child(_tab_bar())
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	col.add_child(_scroll)
	for g in RoomInfo.GROUPS:
		var section := _section(g)
		_sections[g] = section
		list.add_child(section)
	_select_tab("starter")


## The header's right side: (DEV,) a check and the total clears in real runs.
func _clears() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	if DevMode.enabled():
		row.add_child(_dev_tag())
		row.add_child(UiKit.spacer())
	var check := TextureRect.new()
	check.texture = CHECK_ICON
	check.custom_minimum_size = Vector2(16, 16)
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.modulate = UiTokens.ON_SKY
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(check)
	_cleared.theme_type_variation = &"SkyCaption"
	_cleared.text = UiKit.thousands(_profile.total_clears())
	_cleared.tooltip_text = "Rooms cleared in real runs"
	row.add_child(_cleared)
	return row


## "DEV": every room is open because the game runs from the editor or a debug build.
func _dev_tag() -> Control:
	var tag := PanelContainer.new()
	tag.theme_type_variation = &"UsePill"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.tooltip_text = "Developer mode: every room is open for practice"
	var l := Label.new()
	l.theme_type_variation = &"OnInkLabel"
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
	box.add_theme_constant_override("separation", GAP)
	var rooms := RoomInfo.rooms_in(g)
	var open := 0
	for def in rooms:
		if RoomInfo.is_open(_profile, def):
			open += 1
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	var count := UiKit.label(
		"%s, %d of %d open" % [RoomInfo.GROUP_NAMES[g], open, rooms.size()], &"SkyCaption", false
	)
	head.add_child(_inset(count))
	if NOTES.has(g):
		var note := UiKit.label(NOTES[g], &"RoomMuted", false)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(_inset(note))
	box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	for def in rooms:
		var card := RoomCard.new(_profile, def)
		card.pressed.connect(room_opened.emit.bind(def.id))
		grid.add_child(card)
		_cards.append(card)
	box.add_child(grid)
	return box


func _inset(c: Control) -> Control:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", CAPTION_INSET)
	m.add_theme_constant_override("margin_right", CAPTION_INSET)
	m.add_child(c)
	return m


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


## The total clears shown in the header ("84").
func cleared_text() -> String:
	return _cleared.text
