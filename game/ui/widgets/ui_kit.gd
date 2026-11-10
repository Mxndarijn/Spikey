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
## The smallest a header title shrinks to beside a wide right side.
const TITLE_MIN := 18
const PRIMARY_ICON := 30
## "Large buttons" in Settings grows bare icon buttons to this.
const LARGE_BUTTON := 56.0

## Buttons in this group click with the falling "back" pop instead of the
## rising tap (AudioDirector): back, close and home buttons. See mark_back().
const BACK_GROUP := &"back_buttons"

## Settings > Large buttons: the one place it is read (button_size()). Main
## sets it; buttons that live on (the HUD's) are resized by refresh_button_size.
static var large_buttons := false


## The size of a bare icon button now: LARGE_BUTTON with Settings > Large
## buttons, else ICON_BUTTON.
static func button_size() -> float:
	return LARGE_BUTTON if large_buttons else ICON_BUTTON


## Puts `c` across `parent`'s width at `top` px.
static func across(parent: Control, c: Control, top: float) -> void:
	parent.add_child(c)
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = top
	c.offset_bottom = top + c.get_combined_minimum_size().y


## A bare white button with an icon and text over the dimmed room, and a small
## note under it; link_button() gives the button. `back`: it sounds like a way
## back (mark_back).
static func scrim_link(icon: Texture2D, text: String, note: String = "", back := false) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	var b := Button.new()
	b.theme_type_variation = &"ScrimButton"
	b.text = text
	b.icon = icon
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_constant_override("icon_max_width", 20)
	if back:
		mark_back(b)
	col.add_child(b)
	if not note.is_empty():
		var n := label(note, &"ScrimCaption")
		n.add_theme_font_size_override("font_size", 12)
		col.add_child(n)
	return col


## The button inside a scrim_link().
static func link_button(link: Control) -> Button:
	return link.get_child(0) as Button


## Makes `b` sound like a way back (back, close, home).
static func mark_back(b: BaseButton) -> void:
	b.add_to_group(BACK_GROUP)


## A bare icon (no box) that is still a 48px tap target. `variation`:
## RoundButton (ink, or white on night rooms) or ScrimButton (white).
static func icon_button(
	icon: Texture2D, tip: String, variation: StringName = &"RoundButton", side: float = -1.0
) -> Button:
	var b := Button.new()
	if icon == BACK_ICON or icon == CLOSE_ICON:
		mark_back(b)
	b.theme_type_variation = variation
	b.icon = icon
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.focus_mode = Control.FOCUS_NONE
	var s := side if side > 0.0 else button_size()
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
## `right` (coins, a count) at the right; with `right` the title sits left,
## after the back arrow, and trims rather than run under either. Returns the row; `back` is wired to
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
	# A long title trims instead of running under the back button or `right`.
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.offset_left = ICON_BUTTON
	t.offset_right = -ICON_BUTTON
	row.resized.connect(func() -> void: _fit_title(t, row.size.x + t.offset_right - t.offset_left))
	if right != null:
		row.add_child(right)
		right.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE
		)
		right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right.grow_vertical = Control.GROW_DIRECTION_BOTH
		right.offset_left -= 4
		right.offset_right -= 4
		# Next to a wide right side (the wallet) the title sits left, after
		# the back arrow; it keeps clear as the counts grow.
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var keep_clear := func() -> void:
			t.offset_right = -maxf(ICON_BUTTON, right.get_combined_minimum_size().x + 12)
			_fit_title(t, row.size.x + t.offset_right - t.offset_left)
		right.minimum_size_changed.connect(keep_clear)
		keep_clear.call()
	return row


## The header title at its size, smaller (down to 18px) when it would not
## fit `room` px; past that it trims. Starts from the size the screen set.
static func _fit_title(t: Label, room: float) -> void:
	if room <= 0.0:
		return
	var font := UiTheme.get_theme().get_font("font", &"TitleLabel")
	if not t.has_meta(&"full_size"):
		t.set_meta(&"full_size", t.get_theme_font_size("font_size"))
	var full: int = t.get_meta(&"full_size")
	t.add_theme_font_size_override("font_size", fit_font_size(t.text, font, full, room, TITLE_MIN))


## The header's back button, for tests.
static func back_of(header_row: Control) -> Button:
	return header_row.get_node_or_null("Back") as Button


## The largest font size from `size` down to `smallest` (in steps of 2) at
## which one line of `text` is at most `room` px wide.
static func fit_font_size(text: String, font: Font, size: int, room: float, smallest: int) -> int:
	while size > smallest:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
			break
		size -= 2
	return maxi(size, smallest)


## Lets one line of `l` grow with its text up to `room` px, then trims it with
## an ellipsis instead of widening its parent.
static func cap_width(l: Label, room: float) -> void:
	var font := UiTheme.get_theme().get_font("font", l.theme_type_variation)
	var size := (
		l.get_theme_font_size("font_size")
		if l.has_theme_font_size_override("font_size")
		else UiTheme.get_theme().get_font_size("font_size", l.theme_type_variation)
	)
	var need := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	l.clip_text = true
	l.custom_minimum_size.x = ceilf(minf(need, room))


## 1240 -> "1,240", 12345 -> "12.3k", 250000 -> "250k", 1234567 -> "1.2M".
static func short_amount(value: int) -> String:
	if absi(value) < 10000:
		return thousands(value)
	for unit: Array in [[1000000, "M"], [1000, "k"]]:
		var n: int = unit[0]
		if absi(value) >= n:
			var tenths := value * 10 / n
			if absi(tenths) >= 1000 or tenths % 10 == 0:
				return "%d%s" % [tenths / 10, unit[1]]
			return "%d.%d%s" % [tenths / 10, absi(tenths) % 10, unit[1]]
	return thousands(value)


## 1240 -> "1,240".
static func thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if value < 0 else "") + s + out
