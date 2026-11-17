class_name HomeBar
extends PanelContainer
## Home's bottom bar: one solid paper bar with Rooms, Style, Ranks and Runs,
## each an icon over its name. Ranks can wear today's rank as a gold tag.

signal pressed(id: String)

const HEIGHT := 60.0
## A tag starts this far right of the item's centre (the icon is 22 px).
const TAG_X := 12.0
const ITEMS := [
	["rooms", "Rooms", preload("res://assets/ui/icons/rooms.svg"), "Rooms"],
	["style", "Style", preload("res://assets/ui/icons/customize.svg"), "Your look"],
	["rank", "Ranks", preload("res://assets/ui/icons/trophy.svg"), "Leaderboards"],
	["runs", "Runs", preload("res://assets/ui/icons/history.svg"), "Your runs"],
]

var _buttons := {}
var _tags := {}


func _init() -> void:
	name = "Bar"
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_stylebox_override("panel", UiTheme.solid(UiTokens.PANEL, UiTokens.RADIUS_M, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	for item: Array in ITEMS:
		var b := Button.new()
		b.name = item[0]
		b.theme_type_variation = &"DockButton"
		b.icon = item[2]
		b.text = item[1]
		b.tooltip_text = item[3]
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, HEIGHT - UiTheme.RING * 2)
		b.pressed.connect(pressed.emit.bind(item[0] as String))
		row.add_child(b)
		_buttons[item[0]] = b
		var tag := Badge.make("")
		tag.visible = false
		b.add_child(tag)
		# Beside the icon's top right, clear of the icon and the name.
		tag.anchor_left = 0.5
		tag.anchor_right = 0.5
		tag.offset_left = TAG_X
		tag.offset_top = 2
		tag.offset_bottom = 2 + tag.get_combined_minimum_size().y
		_tags[item[0]] = tag


func button(id: String) -> Button:
	return _buttons.get(id) as Button


## A gold tag on an item ("" hides it): today's rank on Ranks.
func set_tag(id: String, text: String) -> void:
	var tag := _tags.get(id) as Label
	if tag == null:
		return
	tag.text = text
	tag.visible = not text.is_empty()
	tag.offset_right = tag.offset_left + tag.get_combined_minimum_size().x


func tag_text(id: String) -> String:
	var tag := _tags.get(id) as Label
	return tag.text if tag != null and tag.visible else ""
