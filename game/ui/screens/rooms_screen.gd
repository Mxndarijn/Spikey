class_name RoomsScreen
extends Control
## Every room kind, for practice (minimal kit), in two steps. First the room
## groups: a back arrow, the title and how many rooms the player has cleared in
## real runs (a check and the number), how many rooms are open, and a card per
## group (RoomGroupCard, two per row). A group then opens on its
## own: the group's name as the title, its "5 of 8 open" line and a scrolling
## two-column grid of flat paper room cards. A room opens for practice once a
## real run has met it.

signal closed
signal room_opened(id: String)
## A group card was tapped: show that group's rooms.
signal group_opened(group: String)

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
var _group := ""
var _scroll := SmoothScroll.new()
var _group_cards: Array[RoomGroupCard] = []
var _cards: Array[RoomCard] = []
var _cleared := Label.new()
var _dev: Control


## `group`: a RoomInfo group to show its rooms, or "" for the group cards.
func _init(profile: Profile, group: String = "") -> void:
	_profile = profile
	_group = group


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
	var title := "Rooms" if _group.is_empty() else str(RoomInfo.GROUP_NAMES.get(_group, _group))
	var header := UiKit.header(title, closed.emit, _clears())
	if not _group.is_empty():
		UiKit.back_of(header).tooltip_text = "Back to the room groups"
	col.add_child(header)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", GAP)
	_scroll.add_child(list)
	col.add_child(FadeMask.new(_scroll))
	if _group.is_empty():
		_build_groups(list)
	else:
		list.add_child(_section(_group))
	list.add_child(UiKit.spacer(FadeMask.FADE))


## The group cards, two to a row; the last one alone takes the whole row.
func _build_groups(list: VBoxContainer) -> void:
	var open := 0
	for def in RoomCatalog.all():
		if RoomInfo.is_open(_profile, def):
			open += 1
	var intro := UiKit.label(
		(
			"%d of %d rooms open. Meet a room in a run to practice it."
			% [open, RoomCatalog.all().size()]
		),
		&"SkyCaption",
		false
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(200, 0)
	list.add_child(_inset(intro))
	var row: HBoxContainer = null
	for i in RoomInfo.GROUPS.size():
		if i % COLUMNS == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", GAP)
			list.add_child(row)
		var card := RoomGroupCard.new(_profile, RoomInfo.GROUPS[i])
		card.pressed.connect(group_opened.emit.bind(RoomInfo.GROUPS[i]))
		row.add_child(card)
		_group_cards.append(card)


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
	var count := UiKit.label("%d of %d open" % [open, rooms.size()], &"SkyCaption", false)
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


## The group this screen shows, or "" on the group cards.
func group() -> String:
	return _group


func group_cards() -> Array[RoomGroupCard]:
	return _group_cards


func cards() -> Array[RoomCard]:
	return _cards


## The total clears shown in the header ("84").
func cleared_text() -> String:
	return _cleared.text
