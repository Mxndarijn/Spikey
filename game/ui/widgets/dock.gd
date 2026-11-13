class_name Dock
extends Control
## The cradle dock along the bottom of Home and Game over: a flat paper bar
## that curves around the round main action (8px gap), with two small icon
## items on each side. Both screens use the same slots: Rooms, Style | Play or
## Again | Ranks, Runs. The main action sits on the action line
## (UiKit.ACTION_Y). `current` marks the screen you are on with a soft edge tile.
## Items are dictionaries: {"id": String, "icon": Texture2D, "text": String}.

signal pressed(id: String)

## The dock's own height, measured from the bottom of the screen: its main
## action's centre is on the action line, y 500.
const HEIGHT := UiTokens.SIZE_VIEWPORT_H - UiKit.ACTION_TOP
## The bar: 80px tall, 60px above the screen's bottom edge (floor spikes).
const BAR_TOP := 50.0
const BAR_H := 80.0
const SIDE := 14.0
const CORNER := 28.0
## The bite around the 100px main action: radius 50 + an 8px gap.
const BITE := 58.0
const ITEM := Vector2(46, 58)
## Each side's two items share this width (as on the canvas).
const GROUP_W := 100.0

var _buttons := {}
var _primary: Button


func _init(left: Array, right: Array, center: Dictionary, current: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -HEIGHT
	custom_minimum_size = Vector2(0, HEIGHT)
	_add_group(left, false, current)
	_add_group(right, true, current)
	_primary = UiKit.primary(center.icon, center.text)
	_primary.name = center.id
	_primary.anchor_left = 0.5
	_primary.anchor_right = 0.5
	_primary.offset_left = -UiKit.PRIMARY / 2.0
	_primary.offset_right = UiKit.PRIMARY / 2.0
	_primary.offset_top = 0.0
	_primary.offset_bottom = UiKit.PRIMARY
	_primary.pressed.connect(pressed.emit.bind(center.id as String))
	add_child(_primary)
	_buttons[center.id] = _primary


func _add_group(items: Array, at_right: bool, current: String) -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_top = BAR_TOP + (BAR_H - ITEM.y) / 2.0
	box.offset_bottom = box.offset_top + ITEM.y
	if at_right:
		box.anchor_left = 1.0
		box.anchor_right = 1.0
		box.offset_left = -SIDE - 4.0 - GROUP_W
		box.offset_right = -SIDE - 4.0
	else:
		box.offset_left = SIDE + 4.0
		box.offset_right = SIDE + 4.0 + GROUP_W
	for item: Dictionary in items:
		var b := Button.new()
		b.name = item.id
		if item.get("back", false):
			UiKit.mark_back(b)
		b.theme_type_variation = &"DockButton"
		b.icon = item.icon
		b.text = item.text
		b.tooltip_text = item.get("tip", item.text)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = ITEM
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = false
		if item.id == current:
			var tile := UiTheme.flat(UiTokens.EDGE, 16, 2)
			for state in ["normal", "hover", "pressed", "hover_pressed"]:
				b.add_theme_stylebox_override(state, tile)
		b.pressed.connect(pressed.emit.bind(item.id as String))
		box.add_child(b)
		_buttons[item.id] = b
	add_child(box)


func button(id: String) -> Button:
	return _buttons.get(id) as Button


func primary() -> Button:
	return _primary


## Changes an item's label (today's rank arrives after the screen opens).
func set_text(id: String, text: String) -> void:
	var b := button(id)
	if b != null:
		b.text = text


func _draw() -> void:
	draw_colored_polygon(bar_outline(size.x), UiTokens.PANEL)


## The bar's outline in local px: a rounded bar with a round bite at the top
## middle, around the main action.
static func bar_outline(width: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var l := SIDE
	var r := width - SIDE
	var top := BAR_TOP
	var bot := BAR_TOP + BAR_H
	var mid := width / 2.0
	_arc(pts, Vector2(l + CORNER, top + CORNER), CORNER, PI, PI * 1.5)
	# Along the top to the bite, around under the main action, and on.
	_arc(pts, Vector2(mid, top), BITE, PI, 0.0, 24)
	_arc(pts, Vector2(r - CORNER, top + CORNER), CORNER, -PI / 2.0, 0.0)
	_arc(pts, Vector2(r - CORNER, bot - CORNER), CORNER, 0.0, PI / 2.0)
	_arc(pts, Vector2(l + CORNER, bot - CORNER), CORNER, PI / 2.0, PI)
	return pts


static func _arc(
	pts: PackedVector2Array, c: Vector2, rad: float, from: float, to: float, steps: int = 8
) -> void:
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
