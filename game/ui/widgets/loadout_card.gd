class_name LoadoutCard
extends Button
## The home screen's one loadout card (Sticker Pop): a picture of the player's
## flyer flying in their world with their trail behind it, the four names
## (flyer, world, trail, portal), and
## a cream "Customize" pill. The whole card opens Customize.

const CUSTOMIZE_ICON := preload("res://assets/ui/icons/customize.svg")
const PICTURE := Vector2(128, 110)
const LABEL_WIDTH := 38.0
const LINES: Array[String] = [Catalog.FLYER, Catalog.WORLD, Catalog.TRAIL, Catalog.PORTAL]
const LINE_LABELS := {
	Catalog.FLYER: "Flyer", Catalog.WORLD: "World", Catalog.TRAIL: "Trail", Catalog.PORTAL: "Portal"
}

var _row := HBoxContainer.new()
var _thumb := ItemThumb.new()
var _names := {}


func _init(profile: Profile) -> void:
	theme_type_variation = &"CardButton"
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = "Customize"
	var box := UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_CARD, 6)
	for state in ["normal", "hover"]:
		add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, box.pressed())
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 10)
	add_child(_row)
	var world := Catalog.world(profile.equipped_id(Catalog.WORLD))
	var flyer := Catalog.flyer(profile.equipped_id(Catalog.FLYER))
	var trail := Catalog.trail(profile.equipped_id(Catalog.TRAIL))
	_thumb.world = world if world != null else ThemeCatalog.default_theme()
	if flyer != null:
		_thumb.flyer = flyer.flap
	_thumb.trail = trail if trail != null else TrailStyle.world_ribbon()
	_thumb.custom_minimum_size = PICTURE
	_row.add_child(_thumb)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind: String in LINES:
		text.add_child(_line(kind, profile))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(gap)
	text.add_child(_pill())
	_row.add_child(text)


func _line(kind: String, profile: Profile) -> Control:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.text = LINE_LABELS[kind]
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	var value := Label.new()
	value.theme_type_variation = &"SmallNameLabel"
	value.add_theme_font_size_override("font_size", 16)
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.custom_minimum_size = Vector2(60, 0)
	value.text = ItemChip.short_name(kind, profile.equipped_id(kind))
	line.add_child(value)
	_names[kind] = value
	return line


func _pill() -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override(
		"panel", UiTheme.sticker(UiTheme.SELECTED_FILL, UiTokens.RADIUS_PILL, Vector2(0, 3), 6)
	)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = CUSTOMIZE_ICON
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UiTokens.INK_LINE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var l := Label.new()
	l.theme_type_variation = &"StatusLabel"
	l.add_theme_font_size_override("font_size", 15)
	l.text = "Customize"
	row.add_child(l)
	pill.add_child(row)
	return pill


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_row.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var content := _row.get_combined_minimum_size()
	custom_minimum_size = Vector2(content.x + 12, content.y + 12)


## The name shown for a kind ("Buzz", "Sunset Glow", "Rainbow Ribbon").
func name_text(kind: String) -> String:
	return (_names[kind] as Label).text if _names.has(kind) else ""
