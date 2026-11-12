class_name RoomGroupCard
extends Button
## One room group on the Rooms screen ("Easy"), a flat paper card: three
## small rooms from the group side by side, the group's name and how many of
## its rooms are open ("7 of 8"), a bar for that, and one line about the group
## (its difficulty, or the score its first room shows up at). A group with no
## open room yet is faded, but still opens (its rooms say why they're locked).

const PICTURES := 3
const THUMB_HEIGHT := 64.0
const THUMB_RADIUS := 12.0
const PAD := 6
const PAD_BOTTOM := 10
const TEXT_INSET := 6
const BAR_H := 6.0
## A group with nothing open yet.
const EMPTY_ALPHA := 0.6

var group := ""
var open_count := 0
var total := 0

var _box := VBoxContainer.new()
var _note := Label.new()


func _init(profile: Profile, p_group: String) -> void:
	group = p_group
	var rooms := RoomInfo.rooms_in(group)
	total = rooms.size()
	for def in rooms:
		if RoomInfo.is_open(profile, def):
			open_count += 1
	theme_type_variation = &"CardButton"
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = "%s rooms" % name_text()
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, 0)
	var down := UiTheme.flat(UiTheme.SELECTED_FILL, UiTokens.RADIUS_M, 0)
	for state in ["normal", "hover"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, down)
	if open_count == 0:
		modulate.a = EMPTY_ALPHA
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = PAD
	_box.offset_top = PAD
	_box.offset_right = -PAD
	_box.offset_bottom = -PAD_BOTTOM
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", UiTokens.SPACE_2)
	add_child(_box)
	_box.add_child(_pictures(rooms))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var title := Label.new()
	title.theme_type_variation = &"SmallNameLabel"
	title.add_theme_font_size_override("font_size", 17)
	title.text = name_text()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(title)
	var count := Label.new()
	count.theme_type_variation = &"StatusLabel"
	count.add_theme_font_override("font", GameFonts.ui(800))
	count.text = count_text()
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(count)
	_box.add_child(_inset(line))
	_box.add_child(_inset(_bar()))
	_note.theme_type_variation = &"StatusLabel"
	_note.add_theme_font_override("font", GameFonts.ui(700))
	_note.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	_note.clip_text = true
	_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_note.text = note_for(profile, group)
	_box.add_child(_inset(_note))


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_box.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var content := _box.get_combined_minimum_size()
	custom_minimum_size = Vector2(
		maxf(content.x, UiTokens.SIZE_TAP_MIN) + PAD * 2, content.y + PAD + PAD_BOTTOM
	)


## Three rooms in different worlds where the group has them, so the card
## shows its variety.
func _pictures(rooms: Array[RoomDef]) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	for def in pick_rooms(rooms):
		var t := RoomThumb.new()
		t.world = RoomInfo.preview_world(def.id)
		t.glyph = RoomInfo.glyph(def.id)
		t.radius = THUMB_RADIUS
		t.custom_minimum_size = Vector2(0, THUMB_HEIGHT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
	return row


static func pick_rooms(rooms: Array[RoomDef]) -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	var worlds := {}
	for def in rooms:
		var w := RoomInfo.preview_world(def.id)
		var key := w.id if w != null else ""
		if not worlds.has(key) and out.size() < PICTURES:
			worlds[key] = true
			out.append(def)
	for def in rooms:
		if out.size() >= PICTURES:
			break
		if not out.has(def):
			out.append(def)
	return out


## How much of the group is open, as a thin pill bar.
func _bar() -> Control:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(total, 1)
	bar.value = open_count
	bar.custom_minimum_size = Vector2(0, BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UiTheme.flat(UiTokens.EDGE, 999, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.flat(UiTokens.ACTION, 999, 0))
	return bar


func _inset(c: Control) -> Control:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", TEXT_INSET)
	m.add_theme_constant_override("margin_right", TEXT_INSET)
	m.add_child(c)
	return m


func name_text() -> String:
	return str(RoomInfo.GROUP_NAMES.get(group, group.capitalize()))


## "7 of 8".
func count_text() -> String:
	return "%d of %d" % [open_count, total]


func note_text() -> String:
	return _note.text


## One line about a group: when its rooms come round for seasonal rooms, the
## score its first room shows up at while none is open, else its difficulty
## ("Difficulty 1 to 3").
static func note_for(profile: Profile, p_group: String) -> String:
	if p_group == "seasonal":
		return "In runs during their season"
	var rooms := RoomInfo.rooms_in(p_group)
	if rooms.is_empty():
		return ""
	var any_open := false
	var first := -1
	var low := 99
	var high := 0
	for def in rooms:
		any_open = any_open or RoomInfo.is_open(profile, def)
		first = def.from_score if first < 0 else mini(first, def.from_score)
		low = mini(low, RoomInfo.difficulty(def.id))
		high = maxi(high, RoomInfo.difficulty(def.id))
	if not any_open:
		return "From %d points" % first
	if low == high:
		return "Difficulty %d" % low
	return "Difficulty %d to %d" % [low, high]
