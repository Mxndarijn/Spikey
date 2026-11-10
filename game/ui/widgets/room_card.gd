class_name RoomCard
extends Button
## One room kind on the Rooms screen, a flat paper card: its rounded picture,
## its name and one status line ("Cleared 9 of 14" in ink, "Not cleared yet" or why
## it's locked muted). Locked rooms are disabled (greyed picture with a lock);
## open ones open the room's detail.

const THUMB_HEIGHT := 76.0
const THUMB_RADIUS := 16.0
const PAD := 6
const PAD_BOTTOM := 10
## The name and status sit a little in from the picture's edges.
const TEXT_INSET := 6

var room_id := ""
var locked := false

var _box := VBoxContainer.new()
var _thumb := RoomThumb.new()
var _name := Label.new()
var _status := Label.new()


func _init(profile: Profile, def: RoomDef) -> void:
	room_id = def.id
	locked = not RoomInfo.is_open(profile, def)
	theme_type_variation = &"CardButton"
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disabled = locked
	tooltip_text = RoomInfo.name_of(def.id)
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, 0)
	var down := UiTheme.flat(UiTheme.SELECTED_FILL, UiTokens.RADIUS_M, 0)
	for state in ["normal", "hover", "disabled"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, down)
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = PAD
	_box.offset_top = PAD
	_box.offset_right = -PAD
	_box.offset_bottom = -PAD_BOTTOM
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	_thumb.world = RoomInfo.preview_world(def.id)
	_thumb.glyph = RoomInfo.glyph(def.id)
	_thumb.locked = locked
	_thumb.radius = THUMB_RADIUS
	_thumb.custom_minimum_size = Vector2(0, THUMB_HEIGHT)
	_box.add_child(_thumb)
	_name.theme_type_variation = &"SmallNameLabel"
	_name.add_theme_font_size_override("font_size", 15)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.text = RoomInfo.name_of(def.id)
	_box.add_child(_inset(_name))
	_status.theme_type_variation = &"StatusLabel"
	_status.add_theme_font_override("font", GameFonts.ui(700))
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.text = RoomInfo.status(profile, def)
	var cleared := profile.clears(def.id) > 0
	_status.add_theme_color_override(
		"font_color", UiTokens.ON_PANEL if cleared else UiTokens.ON_PANEL_MUTED
	)
	_box.add_child(_inset(_status))


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_box.minimum_size_changed.connect(_fit)
	_fit()


func _inset(l: Label) -> Control:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", TEXT_INSET)
	m.add_theme_constant_override("margin_right", TEXT_INSET)
	m.add_child(l)
	return m


func _fit() -> void:
	var content := _box.get_combined_minimum_size()
	custom_minimum_size = Vector2(
		maxf(content.x, UiTokens.SIZE_TAP_MIN) + PAD * 2, content.y + PAD + PAD_BOTTOM
	)


func status_text() -> String:
	return _status.text
