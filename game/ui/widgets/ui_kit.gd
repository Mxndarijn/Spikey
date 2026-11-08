class_name UiKit
extends RefCounted
## Small builders for the minimal kit's pieces, so every screen makes them the
## same way: bare icon buttons (pause, back, close), the 100px round main
## action, the back-arrow header of sub-screens, labels and spacers.

const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
## Bare icon buttons are 48px: bigger than the 44px tap minimum.
const ICON_BUTTON := 48.0
## The one main action per screen.
const PRIMARY := float(UiTokens.SIZE_ROUND_BUTTON)
## Sub-screen header: the back arrow at the left, the title centred.
const HEADER_HEIGHT := 48.0
const PRIMARY_ICON := 30
## "Large buttons" in Settings grows bare icon buttons to this.
const LARGE_BUTTON := 56.0

## Settings > Large buttons, read by every icon button made after it changes.
static var large_buttons := false


## A bare icon (no box) that is still a 48px tap target. `variation`:
## RoundButton (ink, or white on night rooms) or ScrimButton (white).
static func icon_button(
	icon: Texture2D, tip: String, variation: StringName = &"RoundButton", side: float = -1.0
) -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.icon = icon
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.focus_mode = Control.FOCUS_NONE
	var s := side if side > 0.0 else (LARGE_BUTTON if large_buttons else ICON_BUTTON)
	b.custom_minimum_size = Vector2(s, s)
	return b


## The 100px round main action: its icon over its name (Play, Again, Resume,
## Practice, Try again). `light`: paper with ink, for the dimmed room.
static func primary(icon: Texture2D, text: String, light: bool = false) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"PrimaryLight" if light else &"PrimaryButton"
	b.icon = icon
	b.text = text
	b.tooltip_text = text
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(PRIMARY, PRIMARY)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A label of a theme variation.
static func label(text: String, variation: StringName, center: bool = true) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A label that wraps inside `width` px (sentences).
static func wrapped(text: String, variation: StringName, width: float = 0.0) -> Label:
	var l := label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	return l


## Empty room in a box column.
static func spacer(height: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(0, height)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## A sub-screen header: back arrow left, the title centred on the screen,
## `right` (coins, a count) at the right. Returns the row; `back` is wired to
## `on_back`.
static func header(title: String, on_back: Callable, right: Control = null) -> Control:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	var t := label(title, &"TitleLabel")
	t.name = "Title"
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(t)
	var back := icon_button(BACK_ICON, "Back", &"RoundButton", ICON_BUTTON)
	back.name = "Back"
	back.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	back.offset_left = -6
	back.offset_right = ICON_BUTTON - 6
	back.offset_top = -ICON_BUTTON / 2.0
	back.offset_bottom = ICON_BUTTON / 2.0
	back.pressed.connect(on_back)
	row.add_child(back)
	if right != null:
		row.add_child(right)
		right.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE
		)
		right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right.grow_vertical = Control.GROW_DIRECTION_BOTH
		right.offset_left -= 4
		right.offset_right -= 4
	return row


## The header's back button, for tests.
static func back_of(header_row: Control) -> Button:
	return header_row.get_node_or_null("Back") as Button


## 1240 -> "1,240".
static func thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if value < 0 else "") + s + out
