class_name UiTheme
extends RefCounted
## Builds the Godot Theme for the HUD and menus from the design kit's UI tokens,
## in the Sticker Pop style: the UI is drawn like the flyers, as white stickers
## with a 3px ink outline and a hard ink drop (StickerBox), and big outlined
## type straight on the sky.
## Controls pick a look with theme_type_variation:
##   Button: ActionButton (gold, one per screen), RoundButton (white disc: pause,
##           back, shop), TabButton, CardButton; plain Button = white pill
##   PanelContainer: StickerPanel (card), BigPanel (game over), PillPanel, HintPill,
##                   GoldPill, UsePill (mint "In use"), TabStrip
##   Label: LogoLabel, TitleLabel, SkyLabel, SkyCaption (outlined, on the sky);
##          NameLabel, SmallNameLabel, CaptionLabel, MutedLabel, CoinLabel,
##          BigScoreLabel, InkLabel, StatusLabel (ink, on stickers)

## Outline widths. Godot draws half of outline_size on each side of a glyph.
const OUTLINE_TITLE := 14
const OUTLINE_LOGO := 16
const OUTLINE_CAPTION := 10
const BORDER := 3
const BORDER_BOLD := 4
## Hard drops: cards down-right, buttons straight down.
const DROP_CARD := Vector2(4, 4)
const DROP_PILL := Vector2(3, 3)
const DROP_BUTTON := Vector2(0, 5)
const DROP_SELECTED := Vector2(6, 6)
const TITLE_SIZE := 40
const LOGO_SIZE := 76
const BIG_SCORE_SIZE := 96
## Selected shop card fill (cream) and the disabled button fill.
const SELECTED_FILL := Color("#FFE3A3")
const DISABLED_FILL := Color("#E9E6F2")

static var _theme: Theme


static func release() -> void:
	_theme = null


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = GameFonts.ui(700)
	t.default_font_size = UiTokens.FONT_SIZE_BODY
	_labels(t)
	_buttons(t)
	_panels(t)
	t.set_constant("separation", "VBoxContainer", UiTokens.SPACE_3)
	t.set_constant("separation", "HBoxContainer", UiTokens.SPACE_2)
	t.set_constant("h_separation", "GridContainer", UiTokens.SPACE_3)
	t.set_constant("v_separation", "GridContainer", UiTokens.SPACE_3)
	return t


## A sticker style: white fill, ink outline, hard drop.
static func sticker(
	fill: Color = UiTokens.PANEL,
	radius: int = UiTokens.RADIUS_M,
	drop: Vector2 = DROP_CARD,
	padding: int = UiTokens.SPACE_3,
	border: int = BORDER
) -> StickerBox:
	return StickerBox.make(fill, radius, border, drop, padding)


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	_panel(t, "StickerPanel", sticker())
	_panel(t, "BigPanel", sticker(UiTokens.PANEL, UiTokens.RADIUS_L + 2, DROP_SELECTED, 20))
	var pill := sticker(UiTokens.PANEL, UiTokens.RADIUS_PILL, DROP_PILL, 4)
	pill.content_margin_left = 6
	pill.content_margin_right = 14
	_panel(t, "PillPanel", pill)
	var hint := sticker(UiTokens.PANEL, UiTokens.RADIUS_PILL, DROP_PILL, 6)
	hint.content_margin_left = 12
	hint.content_margin_right = 12
	_panel(t, "HintPill", hint)
	var gold := sticker(UiTokens.COIN, UiTokens.RADIUS_PILL, Vector2.ZERO, 4)
	gold.content_margin_left = 8
	gold.content_margin_right = 14
	_panel(t, "GoldPill", gold)
	var use := sticker(UiTokens.SUCCESS, UiTokens.RADIUS_PILL, Vector2.ZERO, 1, 2)
	use.content_margin_left = 7
	use.content_margin_right = 8
	_panel(t, "UsePill", use)
	_panel(t, "TabStrip", sticker(UiTokens.PANEL, UiTokens.RADIUS_PILL, DROP_PILL, 2))


static func _panel(t: Theme, type_name: String, box: StyleBox) -> void:
	t.set_type_variation(type_name, "PanelContainer")
	t.set_stylebox("panel", type_name, box)


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", UiTokens.ON_PANEL)
	# On the sky: white with an ink outline, because the sky changes per world.
	_sky_label(t, "LogoLabel", GameFonts.display(), LOGO_SIZE, OUTLINE_LOGO)
	t.set_color("font_shadow_color", "LogoLabel", UiTokens.INK_LINE)
	t.set_constant("shadow_offset_x", "LogoLabel", 0)
	t.set_constant("shadow_offset_y", "LogoLabel", 6)
	t.set_constant("shadow_outline_size", "LogoLabel", OUTLINE_LOGO)
	_sky_label(t, "TitleLabel", GameFonts.display(), TITLE_SIZE, OUTLINE_TITLE)
	t.set_constant("line_spacing", "TitleLabel", -22)
	_sky_label(t, "SkyLabel", GameFonts.display(), 26, OUTLINE_TITLE)
	_sky_label(t, "SkyCaption", GameFonts.ui(800), UiTokens.FONT_SIZE_CAPTION + 1, OUTLINE_CAPTION)
	# On stickers: ink.
	_label(t, "NameLabel", GameFonts.display(), 22, UiTokens.ON_PANEL)
	_label(t, "SmallNameLabel", GameFonts.display(), 15, UiTokens.ON_PANEL)
	_label(t, "CaptionLabel", GameFonts.ui(700), UiTokens.FONT_SIZE_CAPTION + 1, UiTokens.ON_PANEL)
	_label(
		t, "MutedLabel", GameFonts.ui(700), UiTokens.FONT_SIZE_CAPTION + 1, UiTokens.ON_PANEL_MUTED
	)
	_label(t, "CoinLabel", GameFonts.display(), UiTokens.FONT_SIZE_NUMBER_M, UiTokens.ON_PANEL)
	_label(t, "BigScoreLabel", GameFonts.display(), BIG_SCORE_SIZE, UiTokens.ON_PANEL)
	t.set_constant("line_spacing", "BigScoreLabel", -24)
	_label(t, "InkLabel", GameFonts.display(), UiTokens.FONT_SIZE_NUMBER_M, UiTokens.ON_PANEL)
	_label(t, "StatusLabel", GameFonts.ui(800), UiTokens.FONT_SIZE_CAPTION, UiTokens.ON_PANEL)


static func _sky_label(t: Theme, type_name: String, font: Font, size: int, outline: int) -> void:
	_label(t, type_name, font, size, UiTokens.ON_SKY)
	t.set_color("font_outline_color", type_name, UiTokens.INK_LINE)
	t.set_constant("outline_size", type_name, outline)


static func _label(t: Theme, type_name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, color)


static func _buttons(t: Theme) -> void:
	var ink := UiTokens.ON_PANEL
	# Secondary (plain Button): a white pill.
	var white := sticker(UiTokens.PANEL, UiTokens.RADIUS_PILL, Vector2(0, 4), 8)
	white.content_margin_left = UiTokens.SPACE_5
	white.content_margin_right = UiTokens.SPACE_5
	_button(t, "Button", white, ink, GameFonts.ui(900), UiTokens.FONT_SIZE_BUTTON)
	# Action: gold pill, ink outline and ink drop. One per screen.
	var gold := sticker(UiTokens.ACTION, UiTokens.RADIUS_PILL, DROP_BUTTON, 8)
	gold.content_margin_left = UiTokens.SPACE_5
	gold.content_margin_right = UiTokens.SPACE_5
	_button(t, "ActionButton", gold, UiTokens.ON_ACTION, GameFonts.display(), 22)
	var off := sticker(DISABLED_FILL, UiTokens.RADIUS_PILL, Vector2.ZERO, 8)
	t.set_stylebox("disabled", "ActionButton", off)
	t.set_color("font_disabled_color", "ActionButton", UiTokens.ON_PANEL)
	t.set_color("icon_disabled_color", "ActionButton", UiTokens.ON_PANEL)
	# Round white buttons: pause, back, shop. Padding keeps a disc around the icon.
	var pad := (UiTokens.SIZE_TAP_MIN - UiTokens.SIZE_ICON_M) / 2
	var disc := sticker(UiTokens.PANEL, UiTokens.RADIUS_PILL, DROP_PILL, pad)
	_button(t, "RoundButton", disc, ink, GameFonts.ui(900), UiTokens.FONT_SIZE_BUTTON)
	# Tabs inside a TabStrip: ink text, the selected one filled ink with white text.
	t.set_type_variation("TabButton", "Button")
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(UiTokens.INK_LINE, 0.0)
	tab.set_corner_radius_all(UiTokens.RADIUS_PILL)
	tab.set_content_margin_all(UiTokens.SPACE_2)
	tab.anti_aliasing = true
	var tab_on := tab.duplicate() as StyleBoxFlat
	tab_on.bg_color = UiTokens.INK_LINE
	for state in ["normal", "hover"]:
		t.set_stylebox(state, "TabButton", tab)
	for state in ["pressed", "hover_pressed"]:
		t.set_stylebox(state, "TabButton", tab_on)
	t.set_stylebox("focus", "TabButton", StyleBoxEmpty.new())
	t.set_font("font", "TabButton", GameFonts.ui(900))
	t.set_font_size("font_size", "TabButton", 15)
	t.set_color("font_color", "TabButton", ink)
	t.set_color("font_hover_color", "TabButton", ink)
	t.set_color("font_pressed_color", "TabButton", UiTokens.PANEL)
	t.set_color("font_hover_pressed_color", "TabButton", UiTokens.PANEL)
	# Cards: each ItemCard sets its own sticker per state (selected, in use).
	t.set_type_variation("CardButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CardButton", sticker())
	t.set_stylebox("focus", "CardButton", StyleBoxEmpty.new())


static func _button(
	t: Theme, type_name: String, box: StickerBox, text: Color, font: Font, size: int
) -> void:
	if type_name != "Button":
		t.set_type_variation(type_name, "Button")
	t.set_stylebox("normal", type_name, box)
	t.set_stylebox("hover", type_name, box)
	t.set_stylebox("pressed", type_name, box.pressed())
	t.set_stylebox("hover_pressed", type_name, box.pressed())
	t.set_stylebox("disabled", type_name, box.with_fill(DISABLED_FILL))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = UiTokens.FOCUS
	focus.set_corner_radius_all(UiTokens.RADIUS_PILL)
	focus.set_expand_margin_all(4)
	t.set_stylebox("focus", type_name, focus)
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, size)
	for state in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
	]:
		t.set_color(state, type_name, text)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		t.set_color(state, type_name, text)
	t.set_color("font_disabled_color", type_name, Color(text, 0.6))
	t.set_constant("icon_max_width", type_name, UiTokens.SIZE_ICON_M)
	t.set_constant("h_separation", type_name, UiTokens.SPACE_2)
