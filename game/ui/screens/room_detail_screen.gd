class_name RoomDetailScreen
extends Control
## One room kind (minimal kit): a back arrow and the room's name, its rounded
## picture, one paper card with its group and start score (and the clear rate
## on the right), the pitch, the room's measured difficulty score (RoomScores,
## the mean over its variants) beside its stats from real runs (reached,
## cleared, deaths); then the round ink Practice button on the action line and
## the practice note under it. An open room no real run reached yet says so in place of
## its stats. A locked room shows why instead, and its Practice button is
## disabled.

signal closed
signal practice_pressed(id: String)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const PREVIEW := Vector2(200, 150)
const PREVIEW_RADIUS := 22.0
const TOP := UiKit.SCREEN_TOP
## The Practice button ends this far above the bottom of the screen.
const BOTTOM := 40
const SIDE := 20
const CARD_PAD_X := 18
const CARD_PAD_Y := 14
## Names longer than this get a smaller title so they clear the back arrow.
const LONG_NAME := 11
## The practice note under the round button.
const NOTE := "Practice never counts for gold, best score or cleared rooms."
const NOTE_W := 280.0
## The stats' numbers: small enough that three fit beside the score.
const STAT_SIZE := UiTokens.FONT_SIZE_HEADING

var room_id := ""

var _profile: Profile
var _def: RoomDef
## Stat name ("reached", "cleared", "deaths") -> the label with its number.
var _stats := {}
var _score: Label
var _rate: Label
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
	col.add_child(UiKit.spacer(8))
	col.add_child(_preview())
	col.add_child(UiKit.spacer(12))
	col.add_child(_card())
	# Practice on the action line, the practice note under it on the room.
	_practice = UiKit.primary(PLAY_ICON, "Practice")
	_practice.disabled = not _is_open()
	if _practice.disabled:
		_practice.modulate.a = UiTokens.OPACITY_DISABLED
	_practice.pressed.connect(practice_pressed.emit.bind(room_id))
	UiKit.place_primary(self, _practice)
	var note := UiKit.wrapped(NOTE, &"SkyCaption", NOTE_W)
	note.name = "Note"
	note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	note.anchor_right = 1.0
	note.offset_left = (UiTokens.SIZE_VIEWPORT_W - NOTE_W) / 2.0
	note.offset_right = -note.offset_left
	note.offset_top = UiKit.TEXT_BUTTON_Y
	add_child(note)


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


## The one paper card: group and start, the pitch, score and clears, the note.
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
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var where := UiKit.label(_where(), &"MutedLabel", false)
	where.add_theme_font_override("font", GameFonts.ui(800))
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(where)
	if _is_open() and _reached() > 0:
		_rate = UiKit.label("%s cleared" % rate_text(), &"MutedLabel", false)
		_rate.name = "ClearRate"
		_rate.add_theme_font_override("font", GameFonts.ui(800))
		_rate.add_theme_color_override("font_color", UiTokens.ON_PANEL)
		top.add_child(_rate)
	col.add_child(top)
	var pitch := UiKit.label(RoomInfo.pitch(room_id), &"CaptionLabel", false)
	pitch.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BODY)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size = Vector2(inner, 0)
	col.add_child(pitch)
	col.add_child(_facts())
	return outer


## "Middle, from 30 points" (seasonal rooms: "October only, ...").
func _where() -> String:
	if _def == null:
		return ""
	var first := RoomInfo.group_label(_def)
	if _def.season != Seasons.NONE:
		first = "%s only" % RoomInfo.season_name(_def)
	if _def.from_score <= 0:
		return "%s, from the start" % first
	return "%s, from %d points" % [first, _def.from_score]


## The room's score, then the stats (a locked room says why instead).
func _facts() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	row.add_child(_score_tile(RoomScores.of(room_id)))
	if _is_open():
		_add_stats(row)
	else:
		# A locked room says why in place of its stats (it has none yet).
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


## The measured difficulty on a raised tile, "Score" over its number ("—" for a
## room no bot can measure), so it reads apart from the run stats beside it.
func _score_tile(score: int) -> Control:
	var tile := PanelContainer.new()
	tile.name = "Score"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := UiTheme.flat(UiTokens.PANEL_RAISED, UiTokens.RADIUS_S, UiTokens.SPACE_1)
	box.content_margin_left = UiTokens.SPACE_3
	box.content_margin_right = UiTokens.SPACE_3
	# 3 px over and under: the page has no height to spare on a 640 px screen.
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	tile.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := UiKit.label("Score", &"CaptionLabel", false)
	head.add_theme_font_override("font", GameFonts.ui(800))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	_score = UiKit.label(str(score) if score >= 0 else "—", &"NameLabel", false)
	_score.add_theme_font_size_override("font_size", STAT_SIZE)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_score)
	tile.add_child(col)
	return tile


## Reached, cleared and deaths side by side, each a number over its name; a
## room no real run reached yet says so instead.
func _add_stats(row: HBoxContainer) -> void:
	if _reached() <= 0 and _profile.deaths(room_id) <= 0:
		var empty := UiKit.label("Not reached in a run yet", &"CaptionLabel", false)
		empty.name = "NoStats"
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(empty)
		return
	var values := {
		"reached": _reached(),
		"cleared": _profile.clears(room_id),
		"deaths": _profile.deaths(room_id),
	}
	for key: String in values:
		var stat := _number(UiKit.thousands(values[key]), key)
		stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats[key] = stat.get_child(0)
		row.add_child(stat)


## A big number over its caption.
func _number(value: String, caption: String) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := UiKit.label(value, &"NameLabel", false)
	n.add_theme_font_size_override("font_size", STAT_SIZE)
	box.add_child(n)
	box.add_child(UiKit.label(caption, &"CaptionLabel", false))
	return box


## Times reached; never fewer than the clears (each clear was reached).
func _reached() -> int:
	return maxi(_profile.reached(room_id), _profile.clears(room_id))


## "64%": clears per reach ("" before the first reach).
func rate_text() -> String:
	return "%d%%" % _profile.clear_rate(room_id) if _reached() > 0 else ""


## The number shown for "reached", "cleared" or "deaths" ("" when the stats
## don't show: locked or not reached yet), for tests.
func stat_text(key: String) -> String:
	var l := _stats.get(key) as Label
	return l.text if l != null else ""


## Whether the clear rate shows (an open room reached in a real run), for tests.
func shows_rate() -> bool:
	return _rate != null


## Why a locked room can't be practised ("" when it is open).
func locked_reason() -> String:
	return _why.text if _why != null else ""


## The room's score as shown ("" when it has none), for tests.
func score_text() -> String:
	return _score.text if _score != null else ""


## The Practice button (disabled for locked rooms), for tests.
func practice_button() -> Button:
	return _practice
