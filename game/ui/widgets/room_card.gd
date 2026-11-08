class_name RoomCard
extends Button
## One room kind on the Rooms screen: its picture, its name and one status
## line ("Cleared 12×", "Not cleared yet", or why it's locked). Locked rooms
## are disabled; open ones open the room's detail.

const THUMB_HEIGHT := 112.0
const PAD := 5

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
	var box := UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_CARD, PAD)
	for state in ["normal", "hover", "disabled"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, box.pressed())
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, PAD)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 3)
	add_child(_box)
	_thumb.world = RoomInfo.preview_world(def.id)
	_thumb.glyph = RoomInfo.glyph(def.id)
	_thumb.locked = locked
	_thumb.custom_minimum_size = Vector2(0, THUMB_HEIGHT)
	_box.add_child(_thumb)
	_name.theme_type_variation = &"SmallNameLabel"
	_name.add_theme_font_size_override("font_size", 16)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(60, 30)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.text = RoomInfo.name_of(def.id)
	_box.add_child(_name)
	_status.theme_type_variation = &"StatusLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = RoomInfo.status(profile, def)
	var cleared := profile.clears(def.id) > 0
	_status.add_theme_color_override(
		"font_color", UiTokens.ON_PANEL if cleared else UiTokens.ON_PANEL_MUTED
	)
	_box.add_child(_status)


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_box.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var content := _box.get_combined_minimum_size()
	custom_minimum_size = Vector2(
		maxf(content.x, UiTokens.SIZE_TAP_MIN) + PAD * 2, content.y + PAD * 2
	)


func status_text() -> String:
	return _status.text
