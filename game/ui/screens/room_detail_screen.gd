class_name RoomDetailScreen
extends Control
## One room kind (Sticker Pop): its name, a big tilted preview, its group and
## start score, the pitch, difficulty, how many times it was cleared in real
## runs, and a gold Practice button.

signal closed
signal practice_pressed(id: String)

const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const PREVIEW := Vector2(150, 184)

var room_id := ""

var _profile: Profile
var _def: RoomDef
var _cleared := Label.new()


func _init(profile: Profile, id: String) -> void:
	_profile = profile
	room_id = id
	_def = RoomCatalog.find(id)


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", UiTokens.SPACE_4 + 4)
	margin.add_theme_constant_override("margin_right", UiTokens.SPACE_4 + 4)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_6 + 8)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	col.add_child(_header())
	col.add_child(_preview())
	col.add_child(_pills())
	col.add_child(_pitch())
	col.add_child(_stats())
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var practice := Button.new()
	practice.theme_type_variation = &"ActionButton"
	practice.text = "Practice"
	practice.icon = PLAY_ICON
	practice.add_theme_font_size_override("font_size", 24)
	practice.custom_minimum_size = Vector2(0, 60)
	practice.focus_mode = Control.FOCUS_NONE
	practice.disabled = _def == null or not RoomInfo.is_open(_profile, _def)
	practice.pressed.connect(practice_pressed.emit.bind(room_id))
	col.add_child(practice)
	var note := Label.new()
	note.theme_type_variation = &"SkyCaption"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "Practice never counts for coins, best score or cleared rooms."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	col.add_child(note)


func _header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	var back := Button.new()
	back.theme_type_variation = &"RoundButton"
	back.icon = BACK_ICON
	back.tooltip_text = "Back to rooms"
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(closed.emit)
	row.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 32)
	title.text = RoomInfo.name_of(room_id)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tilt := Tilt.new(title, -2.0)
	tilt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tilt)
	return row


func _preview() -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"StickerPanel"
	card.add_theme_stylebox_override(
		"panel", UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_SELECTED, 6)
	)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb := RoomThumb.new()
	thumb.world = RoomInfo.preview_world(room_id)
	thumb.glyph = RoomInfo.glyph(room_id)
	thumb.custom_minimum_size = PREVIEW
	card.add_child(thumb)
	var tilt := Tilt.new(card, -1.5)
	tilt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return tilt


func _pills() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _def == null:
		return row
	var first := RoomInfo.group_label(_def)
	if _def.season != Seasons.NONE:
		first = "%s only" % RoomInfo.season_name(_def)
	for text in [first, "From %d points" % _def.from_score]:
		var pill := PanelContainer.new()
		pill.theme_type_variation = &"HintPill"
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.theme_type_variation = &"StatusLabel"
		l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION + 1)
		l.text = text
		pill.add_child(l)
		row.add_child(pill)
	return row


func _pitch() -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"StickerPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.theme_type_variation = &"CaptionLabel"
	l.add_theme_font_size_override("font_size", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = RoomInfo.pitch(room_id)
	card.add_child(l)
	var tilt := Tilt.new(card, 0.8)
	tilt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return tilt


func _stats() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	var diff := _stat_card("Difficulty", -1.0)
	var pips := DifficultyPips.new(RoomInfo.difficulty(room_id))
	diff.add_child(pips)
	var of := Label.new()
	of.theme_type_variation = &"StatusLabel"
	of.text = "%d of 5" % RoomInfo.difficulty(room_id)
	diff.add_child(of)
	grid.add_child(diff.get_parent().get_parent())
	var cleared := _stat_card("Cleared in real runs", 1.0)
	_cleared.theme_type_variation = &"NameLabel"
	_cleared.add_theme_font_size_override("font_size", 28)
	_cleared.text = cleared_text()
	cleared.add_child(_cleared)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.add_theme_font_size_override("font_size", 11)
	hint.text = "All 10 points survived"
	cleared.add_child(hint)
	grid.add_child(cleared.get_parent().get_parent())
	return grid


## A small sticker card with a caption; returns the column to fill.
func _stat_card(caption: String, tilt: float) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"StickerPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override(
		"panel", UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_CARD, 8)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.theme_type_variation = &"MutedLabel"
	l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	l.text = caption
	box.add_child(l)
	card.add_child(box)
	var holder := Tilt.new(card, tilt)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


func cleared_text() -> String:
	var n := _profile.clears(room_id)
	return "%d×" % n if n > 0 else "Not yet"
