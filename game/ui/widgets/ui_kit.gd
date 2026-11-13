class_name UiKit
extends RefCounted
## Small builders for the minimal kit's pieces, so every screen makes them the
## same way. The button system (A3) has seven types, each with one place:
## - round primary (primary(), place_primary()): the one main action, centred
##   on the action line (ACTION_Y) on every screen that has one;
## - flat primary (action_button()): the main action inside a popup or sheet;
## - text button (text_button(), place_text_button()): the one other choice,
##   no icon and no chevron, under the round primary on overlays;
## - corner button (icon_button() in the CORNER slot, header()): leaves the
##   screen. Top left always goes up: back, pause in a run, Home on Game over,
##   Settings on Home (which has nowhere to go back to). Popups close in
##   their card's top right (close_button());
## - icon button (disc_button()): an action on one row or one thing;
## - row (row_button()): a list item that opens something, with a chevron;
## - tab and chip (TabStrip, chips).

## Looks of a disc_button().
enum Disc { FILL, TONAL, BARE }

## The Wallet's two tabs (wallet_tabs()).
const WALLET_TABS: Array[String] = ["Get diamonds", "Earn free"]
const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
## Bare icon buttons are 48px: bigger than the 44px tap minimum.
const ICON_BUTTON := 48.0
## The one main action per screen.
const PRIMARY := float(UiTokens.SIZE_ROUND_BUTTON)
## Sub-screen header: the back arrow in the corner slot, the title after it.
const HEADER_HEIGHT := 48.0
## The smallest a header title shrinks to beside a wide right side.
const TITLE_MIN := 18
const PRIMARY_ICON := 30
## "Large buttons" in Settings grows bare icon buttons to this.
const LARGE_BUTTON := 56.0
## A3 placement, room px. The corner slot (a 48px target) is shared by every
## back arrow, the HUD's pause, Game over's Home and Home's Settings.
const CORNER := Vector2(24, 40)
## Sub-screens' side margin and the top of their header row (= CORNER.y).
const SCREEN_SIDE := 14
const SCREEN_TOP := 40
## Header titles start here, after the corner button.
const TITLE_X := 80.0
## The action line: the centre of the round primary on every screen with one.
const ACTION_Y := 500.0
const ACTION_TOP := ACTION_Y - PRIMARY / 2.0
## The one text button under the round primary on overlays.
const TEXT_BUTTON_Y := 558.0
## No control reaches lower than this, clear of the floor spikes (606).
const BOTTOM_LIMIT := 602.0
## Icon buttons on rows and in cards, and popups' close button.
const DISC := 44.0
## The flat primary in popups and sheets (button-h).
const ACTION_H := float(UiTokens.SIZE_BUTTON_H)
## Rows that open something.
const ROW_H := 52.0
const CHEVRON_ICON := preload("res://assets/ui/icons/chevron.svg")

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


## The text button: the one other choice next to a main action. No icon and
## no chevron: its words say what happens ("End run", "Rooms"). `variation`:
## ScrimButton on the dimmed room, InkButton on paper, PlainButton on the room.
static func text_button(text: String, variation: StringName = &"ScrimButton") -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## Puts a round primary on the action line of a full-room `parent`, centred.
static func place_primary(parent: Control, b: Button, top: float = ACTION_TOP) -> void:
	parent.add_child(b)
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.anchor_top = 0.0
	b.anchor_bottom = 0.0
	b.offset_left = -PRIMARY / 2.0
	b.offset_right = PRIMARY / 2.0
	b.offset_top = top
	b.offset_bottom = top + PRIMARY


## Puts an overlay's one text button under the action line, centred. Returns
## the row that holds it.
static func place_text_button(parent: Control, b: Button) -> Control:
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(b)
	across(parent, row, TEXT_BUTTON_Y)
	return row


## Puts a corner button in the top-left slot of a full-room `parent`. A bigger
## one (Large buttons) grows in place around the slot's centre.
static func place_corner(parent: Control, b: Button) -> void:
	parent.add_child(b)
	var s := b.custom_minimum_size.x
	var c := CORNER + Vector2(ICON_BUTTON, ICON_BUTTON) / 2.0
	b.position = c - Vector2(s, s) / 2.0
	b.size = Vector2(s, s)


## The flat primary of a popup or sheet: a full-width 56px ink pill. Its icon
## (a coin, a diamond) sits before the label, centred with it as one group.
static func action_button(text: String, icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ActionButton"
	b.text = text
	b.icon = icon
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ACTION_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("icon_max_width", 26)
	center_icon_group(b)
	return b


## Keeps a button's icon right before its text with the pair centred as one
## group: equal side margins, set again whenever the button resizes. A Button
## alone pins a left icon to its edge and centres the text in what is left.
static func center_icon_group(b: Button) -> void:
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var fit := func() -> void:
		if b.icon == null or b.size.x <= 0.0:
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			return
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var t := UiTheme.get_theme()
		var font := t.get_font("font", b.theme_type_variation)
		var fs := (
			b.get_theme_font_size("font_size")
			if b.has_theme_font_size_override("font_size")
			else t.get_font_size("font_size", b.theme_type_variation)
		)
		var text_w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon_w := minf(b.icon.get_width(), b.get_theme_constant("icon_max_width"))
		var group := icon_w + t.get_constant("h_separation", b.theme_type_variation) + text_w
		var side := maxf(UiTokens.SPACE_4, floorf((b.size.x - group) / 2.0))
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			# The boxes come from the UI theme itself: a button can resize before
			# its theme reaches it, and would then copy the engine's grey ones.
			var box := t.get_stylebox(state, b.theme_type_variation)
			box = box.duplicate() as StyleBox
			box.content_margin_left = side
			box.content_margin_right = side
			b.add_theme_stylebox_override(state, box)
	b.resized.connect(fit)


## An icon button on a row or in a card, 44px: FILL (an ink disc: the row's
## main action, one per row), TONAL (a paper-raised disc) or BARE (the icon).
static func disc_button(icon: Texture2D, tip: String, look: Disc = Disc.TONAL) -> Button:
	var b := icon_button(icon, tip, &"InkButton", DISC)
	if look == Disc.BARE:
		return b
	var fill := UiTokens.INK_LINE if look == Disc.FILL else UiTokens.PANEL_RAISED
	var down := fill.lightened(0.15) if look == Disc.FILL else UiTokens.EDGE
	var disc := UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0)
	var disc_down := UiTheme.flat(down, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, disc)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, disc_down)
	if look == Disc.FILL:
		for state in [
			"icon_normal_color",
			"icon_hover_color",
			"icon_pressed_color",
			"icon_hover_pressed_color"
		]:
			b.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	return b


## A popup's or sheet's close button for its card's top right: a 44px
## paper-raised disc with the close icon. It sounds like a way back.
static func close_button(tip: String = "Close") -> Button:
	var b := disc_button(CLOSE_ICON, tip, Disc.TONAL)
	mark_back(b)
	return b


## A popup's or sheet's top row: `title` at the left, the close button in the
## card's top right, wired to `on_close`. Returns the row.
static func card_head(title: Control, on_close: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Head"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var close := close_button()
	close.name = "Close"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(on_close)
	row.add_child(close)
	return row


## The close button of a card_head() row.
static func close_of(head: Control) -> Button:
	return head.get_node_or_null("Close") as Button


## A row that opens something: a full-width paper pill with its text at the
## left and a chevron at the right. `fill`: paper-raised inside a paper card.
static func row_button(text: String, fill: Color = UiTokens.PANEL) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = CHEVRON_ICON
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0)
	box.content_margin_left = UiTokens.SPACE_5
	box.content_margin_right = UiTokens.SPACE_4
	var down := box.duplicate() as StyleBoxFlat
	down.bg_color = UiTokens.PANEL_RAISED if fill == UiTokens.PANEL else UiTokens.EDGE
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	b.add_theme_constant_override("icon_max_width", 20)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in [
		"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"
	]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	return b


## The Wallet's two tabs (the Shop and Earn diamonds are one Wallet): "Get
## diamonds" and "Earn free". `on`: the selected one (0 or 1); `pick` is called
## with the other tab's index when it is tapped.
static func wallet_tabs(on: int, pick: Callable) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.name = "WalletTabs"
	bar.theme_type_variation = &"TabStrip"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)
	var group := ButtonGroup.new()
	for i in WALLET_TABS.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = WALLET_TABS[i]
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = i == on
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		if i != on:
			tab.pressed.connect(pick.bind(i))
		row.add_child(tab)
	return bar


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


## A bare icon button for the run's HUD (pause, back, restart, close): the
## icon in the HUD halo (HaloIcon), white with an ink ring in every world.
static func hud_icon_button(icon: Texture2D, tip: String) -> Button:
	var b := icon_button(icon, tip, &"HudButton")
	var halo := HaloIcon.new(icon)
	halo.name = "Halo"
	b.add_child(halo)
	halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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


## A sub-screen header: the back arrow in the corner slot (x 24 with the
## screen's side margin at SCREEN_SIDE), the title left from TITLE_X, and
## `right` (the wallet, a count) at the right. The title shrinks, then trims,
## rather than run under either. Returns the row; `back` is wired to `on_back`.
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
	back.offset_left = CORNER.x - SCREEN_SIDE
	back.offset_right = CORNER.x - SCREEN_SIDE + ICON_BUTTON
	back.offset_top = -ICON_BUTTON / 2.0
	back.offset_bottom = ICON_BUTTON / 2.0
	back.pressed.connect(on_back)
	row.add_child(back)
	# A long title trims instead of running under the back button or `right`.
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.offset_left = TITLE_X - SCREEN_SIDE
	t.offset_right = 0
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
		# The title keeps clear of the right side as the counts grow.
		var keep_clear := func() -> void:
			t.offset_right = -(right.get_combined_minimum_size().x + 12)
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
