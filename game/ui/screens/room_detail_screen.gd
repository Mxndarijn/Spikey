class_name RoomDetailScreen
extends Control
## One room kind (minimal kit): a back arrow and the room's name, its rounded
## picture, one paper card with its group and start score, the pitch, the
## difficulty and how many times it was cleared in real runs, and the practice
## note; then the round ink Practice button. A locked room shows why in place
## of its clears and its Practice button is disabled.

signal closed
signal practice_pressed(id: String)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const PREVIEW := Vector2(200, 180)
const PREVIEW_RADIUS := 22.0
const TOP := 40
## The Practice button ends this far above the bottom of the screen.
const BOTTOM := 40
const SIDE := 20
const CARD_PAD_X := 18
const CARD_PAD_Y := 14
## Names longer than this get a smaller title so they clear the back arrow.
const LONG_NAME := 11

var room_id := ""

var _profile: Profile
var _def: RoomDef
var _cleared := Label.new()
var _practice: Button
var _why: Label


func _init(profile: Profile, id: String) -> void:
	_profile = profile
	room_id = id
	_def = RoomCatalog.find(id)


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE - 6)
	margin.add_theme_constant_override("margin_right", SIDE - 6)
	margin.add_theme_constant_override("margin_top", TOP)
	margin.add_theme_constant_override("margin_bottom", BOTTOM)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)
	var header := UiKit.header(RoomInfo.name_of(room_id), closed.emit)
	if RoomInfo.name_of(room_id).length() > LONG_NAME:
		(header.get_node("Title") as Label).add_theme_font_size_override("font_size", 26)
	UiKit.back_of(header).tooltip_text = "Back to rooms"
	col.add_child(header)
	col.add_child(UiKit.spacer(10))
	col.add_child(_preview())
	col.add_child(UiKit.spacer(14))
	col.add_child(_card())
	col.add_child(UiKit.spacer(8, true))
	_practice = UiKit.primary(PLAY_ICON, "Practice")
	_practice.disabled = not _is_open()
	if _practice.disabled:
		_practice.modulate.a = UiTokens.OPACITY_DISABLED
	_practice.pressed.connect(practice_pressed.emit.bind(room_id))
	col.add_child(_practice)


func _is_open() -> bool:
	return _def != null and RoomInfo.is_open(_profile, _def)


## Why a locked room can't be practised yet ("Reach 90 points").
func _reason() -> String:
	if _def == null:
		return ""
	return RoomInfo.status(_profile, _def)


func _preview() -> Control:
	var thumb := RoomThumb.new()
	thumb.world = RoomInfo.preview_world(room_id)
	thumb.glyph = RoomInfo.glyph(room_id)
	thumb.radius = PREVIEW_RADIUS
	thumb.custom_minimum_size = PREVIEW
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return thumb


## The one paper card: group and start, the pitch, difficulty and clears, the note.
func _card() -> Control:
	var inner := float(UiTokens.SIZE_VIEWPORT_W - SIDE * 2 - CARD_PAD_X * 2)
	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("margin_left", 6)
	outer.add_theme_constant_override("margin_right", 6)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, CARD_PAD_Y)
	box.content_margin_left = CARD_PAD_X
	box.content_margin_right = CARD_PAD_X
	card.add_theme_stylebox_override("panel", box)
	outer.add_child(card)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var where := UiKit.label(_where(), &"MutedLabel", false)
	where.add_theme_font_override("font", GameFonts.ui(800))
	col.add_child(where)
	var pitch := UiKit.label(RoomInfo.pitch(room_id), &"CaptionLabel", false)
	pitch.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BODY)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size = Vector2(inner, 0)
	col.add_child(pitch)
	col.add_child(_facts())
	var foot := VBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var line := ColorRect.new()
	line.color = UiTokens.EDGE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(line)
	var note := UiKit.label(
		"Practice never counts for gold, best score or cleared rooms.", &"MutedLabel", false
	)
	note.add_theme_font_override("font", GameFonts.ui(600))
	note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(inner, 0)
	foot.add_child(note)
	col.add_child(foot)
	return outer


## "Mid-game, from 30 points" (seasonal rooms: "October only, ...").
func _where() -> String:
	if _def == null:
		return ""
	var first := RoomInfo.group_label(_def)
	if _def.season != Seasons.NONE:
		first = "%s only" % RoomInfo.season_name(_def)
	if _def.from_score <= 0:
		return "%s, from the start" % first
	return "%s, from %d points" % [first, _def.from_score]


## The difficulty pips over "Difficulty 3 of 5", and the clears over "cleared".
func _facts() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	var diff := VBoxContainer.new()
	diff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diff.alignment = BoxContainer.ALIGNMENT_CENTER
	diff.add_theme_constant_override("separation", 4)
	var level := RoomInfo.difficulty(room_id)
	var pips := DifficultyPips.new(level)
	pips.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	diff.add_child(pips)
	diff.add_child(UiKit.label("Difficulty %d of 5" % level, &"CaptionLabel", false))
	row.add_child(diff)
	var clears := VBoxContainer.new()
	clears.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clears.add_theme_constant_override("separation", 0)
	_cleared.theme_type_variation = &"NameLabel"
	_cleared.add_theme_font_size_override("font_size", 22)
	_cleared.text = cleared_text()
	_cleared.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clears.add_child(_cleared)
	clears.add_child(UiKit.label("cleared", &"CaptionLabel", false))
	row.add_child(clears)
	if not _is_open():
		# A locked room says why in place of its clears (it has none yet).
		clears.visible = false
		var locked := VBoxContainer.new()
		locked.mouse_filter = Control.MOUSE_FILTER_IGNORE
		locked.add_theme_constant_override("separation", 0)
		var head := UiKit.label("Locked", &"NameLabel", false)
		head.add_theme_font_size_override("font_size", 22)
		locked.add_child(head)
		_why = UiKit.label(_reason(), &"CaptionLabel", false)
		locked.add_child(_why)
		row.add_child(locked)
	return row


func cleared_text() -> String:
	var n := _profile.clears(room_id)
	return "%d×" % n if n > 0 else "Not yet"


## Why a locked room can't be practised ("" when it is open).
func locked_reason() -> String:
	return _why.text if _why != null else ""


## The Practice button (disabled for locked rooms), for tests.
func practice_button() -> Button:
	return _practice
