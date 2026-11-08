class_name ItemChip
extends Button
## A sticker card on the home screen for the flyer or world in use: its picture,
## a small "Flyer" or "World" label and the name. Tapping it opens that shop tab.

const FLYER_PICTURE := 52.0
const WORLD_PICTURE := Vector2(40, 44)
const HEIGHT := 64.0

var kind := ""

var _row := HBoxContainer.new()
var _name := Label.new()


func _init(p_kind: String, id: String, world: ThemeDef) -> void:
	kind = p_kind
	theme_type_variation = &"CardButton"
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var what := "Flyer" if kind == Catalog.FLYER else "World"
	tooltip_text = "Change %s" % what.to_lower()
	var box := UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_CARD, 4)
	for state in ["normal", "hover"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, box.pressed())
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	add_child(_row)
	var thumb := ItemThumb.new()
	thumb.world = world
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if kind == Catalog.FLYER:
		var f := Catalog.flyer(id)
		if f != null:
			thumb.flyer = f.idle
		thumb.bare = true
		thumb.custom_minimum_size = Vector2(FLYER_PICTURE, FLYER_PICTURE)
	else:
		thumb.custom_minimum_size = WORLD_PICTURE
		thumb.world = Catalog.world(id) if Catalog.world(id) != null else world
	_row.add_child(thumb)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	label.text = what
	text.add_child(label)
	_name.theme_type_variation = &"SmallNameLabel"
	_name.add_theme_font_size_override("font_size", 18)
	_name.text = short_name(kind, id)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(70, 0)
	text.add_child(_name)
	_row.add_child(text)


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_row.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	custom_minimum_size = Vector2(
		_row.get_combined_minimum_size().x + 8, maxf(HEIGHT, _row.get_combined_minimum_size().y + 8)
	)


func label_text() -> String:
	return _name.text


## Flyers go by their first name on cards ("Buzz the Bee" -> "Buzz").
static func short_name(p_kind: String, id: String) -> String:
	var full := Catalog.display_name(p_kind, id)
	if p_kind == Catalog.FLYER:
		return full.get_slice(" ", 0)
	return full
