class_name UiTheme
extends RefCounted
## Builds the Godot Theme for the HUD and menus from the design kit's UI tokens,
## in the minimal style: no outlines and no drop shadows, except the run's HUD
## (below). Text and
## numbers sit straight on the room in dark ink; cream paper cards only where
## there is a grid or a form; one main action per screen as a 100px round ink
## button. Archivo is the only font (GameFonts).
##
## Text on the room is ink, except in worlds whose sky is too dark for ink
## (night worlds): their screens use room_theme(world), where the room labels
## are white. Cards keep ink text in every world.
##
## Controls pick a look with theme_type_variation:
##   Button: PrimaryButton (100px round ink, icon over its name), PrimaryLight
##           (the same in paper, on the dimmed room), ActionButton (flat ink
##           pill: Unlock, Save), RoundButton (a bare ink icon: pause, back,
##           close), InkButton (the same, always ink: on paper cards), ScrimButton
##           (bare white icon and text on the dimmed room),
##           PlainButton (bare ink text on the room), DockButton (icon over a
##           small name, in the dock), TabButton, CardButton; plain Button = a
##           flat paper pill
##   PanelContainer: StickerPanel / Card (flat paper card), BigPanel (popup or
##                   sheet), PillPanel, HintPill, GoldPill, UsePill (ink "In
##                   use"), TabStrip (paper pill bar)
##   Label on the room: LogoLabel, TitleLabel, SkyLabel, SkyCaption, RoomScore,
##                      RoomBigScore, RoomStat, RoomMuted, RoomCoin
##   The run's HUD, white in an ink halo in every world: HudScore, HudCoin,
##     HudLabel; HudButton (a bare icon button whose HaloIcon draws the icon)
##   Label on the dimmed room: ScrimTitle, ScrimScore, ScrimLabel, ScrimCaption
##   Label on paper: NameLabel, SmallNameLabel, CaptionLabel, MutedLabel,
##                   CoinLabel, BigScoreLabel, InkLabel, StatusLabel, OnInkLabel

const TITLE_SIZE := 30
const LOGO_SIZE := 74
const BIG_SCORE_SIZE := 140
const SCRIM_TITLE_SIZE := 44
## The live score at the top of the run.
const RUN_SCORE_SIZE := 72
## The round main action: the margins above its icon and below its name.
const PRIMARY_PAD_TOP := 22
const PRIMARY_PAD_BOTTOM := 16
## Selected and disabled fills on paper.
const SELECTED_FILL := UiTokens.PANEL_RAISED
const DISABLED_FILL := UiTokens.EDGE
## A room is "dark" when ink reads worse on its sky than white does, or below
## this contrast on any sky stop (big text: 3:1).
const ROOM_INK_MIN := 3.0
## The run's HUD (score, coins, pause, hints, boss bar, countdown): white glyphs
## in an ink-900 halo, the same in every world. Whatever is behind a glyph, one
## of the two stands out from it: the fill from dark spikes and skies, the halo
## from light ones. Only UI tokens, so no world changes it.
const HUD_FILL := UiTokens.ON_SCRIM
const HUD_HALO := UiTokens.INK_900
## Halo widths, px (Godot outline sizes): the score and countdown, smaller
## labels, and how far an icon's ring of ink copies reaches.
const HALO_BIG := 10
const HALO_SMALL := 6
const HALO_ICON := 2.5
## The soft drop under the score.
const HUD_SHADOW := Color(UiTokens.INK_900, 0.35)

static var _theme: Theme
static var _light: Theme


static func release() -> void:
	_theme = null
	_light = null


## The theme for ink text on the room (most worlds).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build(UiTokens.ON_SKY)
	return _theme


## The theme for this world's rooms: white room labels on dark skies.
static func room_theme(world: ThemeDef) -> Theme:
	if not is_dark_room(world):
		return get_theme()
	if _light == null:
		_light = _build(UiTokens.ON_SCRIM)
	return _light


## The colour of text drawn straight on this world's room.
static func room_ink(world: ThemeDef) -> Color:
	return UiTokens.ON_SCRIM if is_dark_room(world) else UiTokens.ON_SKY


## True when ink can't be read on some of this world's sky stops.
static func is_dark_room(world: ThemeDef) -> bool:
	if world == null:
		return false
	var ink := INF
	var white := INF
	for stop in [world.sky_top, world.sky_mid]:
		ink = minf(ink, Contrast.ratio(UiTokens.ON_SKY, stop))
		white = minf(white, Contrast.ratio(UiTokens.ON_SCRIM, stop))
	return ink < ROOM_INK_MIN and white > ink


static func _build(room_ink_color: Color) -> Theme:
	var t := Theme.new()
	t.default_font = GameFonts.ui(700)
	t.default_font_size = UiTokens.FONT_SIZE_BODY
	_labels(t, room_ink_color)
	_buttons(t, room_ink_color)
	_panels(t)
	t.set_constant("separation", "VBoxContainer", UiTokens.SPACE_3)
	t.set_constant("separation", "HBoxContainer", UiTokens.SPACE_2)
	t.set_constant("h_separation", "GridContainer", UiTokens.SPACE_3)
	t.set_constant("v_separation", "GridContainer", UiTokens.SPACE_3)
	return t


## A flat box: a fill, round corners, padding. No outline, no drop.
static func flat(
	fill: Color = UiTokens.PANEL, radius: int = UiTokens.RADIUS_M, padding: int = UiTokens.SPACE_3
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(padding)
	s.anti_aliasing = true
	s.corner_detail = 12
	return s


## A ring inside the edge (the "In use" card): a flat box with a border.
static func ringed(
	fill: Color = UiTokens.PANEL,
	radius: int = UiTokens.RADIUS_M,
	padding: int = UiTokens.SPACE_3,
	ring: Color = UiTokens.INK_LINE,
	width: int = 3
) -> StyleBoxFlat:
	var s := flat(fill, radius, padding)
	s.set_border_width_all(width)
	s.border_color = ring
	return s


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	_panel(t, "StickerPanel", flat())
	_panel(t, "Card", flat())
	_panel(t, "BigPanel", flat(UiTokens.PANEL, UiTokens.RADIUS_M, 20))
	var pill := flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 4)
	pill.content_margin_left = 10
	pill.content_margin_right = 14
	_panel(t, "PillPanel", pill)
	var hint := flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 6)
	hint.content_margin_left = 14
	hint.content_margin_right = 14
	_panel(t, "HintPill", hint)
	var gold := flat(UiTokens.ACTION, UiTokens.RADIUS_PILL, 4)
	gold.content_margin_left = 12
	gold.content_margin_right = 14
	_panel(t, "GoldPill", gold)
	var use := flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, 2)
	use.content_margin_left = 8
	use.content_margin_right = 8
	_panel(t, "UsePill", use)
	_panel(t, "TabStrip", flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 3))


static func _panel(t: Theme, type_name: String, box: StyleBox) -> void:
	t.set_type_variation(type_name, "PanelContainer")
	t.set_stylebox("panel", type_name, box)


static func _labels(t: Theme, room: Color) -> void:
	var ink := UiTokens.ON_PANEL
	var white := UiTokens.ON_SCRIM
	t.set_color("font_color", "Label", ink)
	# On the room: ink (white on night rooms), no outline.
	_label(t, "LogoLabel", GameFonts.display(), LOGO_SIZE, room)
	_label(t, "TitleLabel", GameFonts.display(), TITLE_SIZE, room)
	_label(t, "SkyLabel", GameFonts.ui(800), 18, room)
	_label(t, "SkyCaption", GameFonts.ui(800), 15, room)
	_label(t, "RoomScore", GameFonts.display(), RUN_SCORE_SIZE, room)
	_label(t, "RoomBigScore", GameFonts.display(), BIG_SCORE_SIZE, room)
	t.set_constant("line_spacing", "RoomBigScore", -30)
	_label(t, "RoomStat", GameFonts.display(), 26, room)
	_label(t, "RoomMuted", GameFonts.ui(700), 13, room)
	_label(t, "RoomCoin", GameFonts.ui(800), 18, room)
	# The run's HUD: white in an ink halo, the same over every world.
	_hud_label(t, "HudScore", GameFonts.display(), RUN_SCORE_SIZE, HALO_BIG)
	t.set_color("font_shadow_color", "HudScore", HUD_SHADOW)
	t.set_constant("shadow_offset_x", "HudScore", 0)
	t.set_constant("shadow_offset_y", "HudScore", 3)
	t.set_constant("shadow_outline_size", "HudScore", HALO_BIG)
	_hud_label(t, "HudCoin", GameFonts.ui(800), 18, HALO_SMALL)
	_hud_label(t, "HudLabel", GameFonts.ui(800), 18, HALO_SMALL)
	# On the dimmed room: white.
	_label(t, "ScrimTitle", GameFonts.display(), SCRIM_TITLE_SIZE, white)
	_label(t, "ScrimScore", GameFonts.display(), 80, white)
	_label(t, "ScrimLabel", GameFonts.ui(800), 15, white)
	_label(t, "ScrimCaption", GameFonts.ui(600), 13, white)
	# On paper: ink.
	_label(t, "NameLabel", GameFonts.display(), 26, ink)
	_label(t, "SmallNameLabel", GameFonts.ui(800), 14, ink)
	_label(t, "CaptionLabel", GameFonts.ui(700), 13, ink)
	_label(t, "MutedLabel", GameFonts.ui(700), 13, UiTokens.ON_PANEL_MUTED)
	_label(t, "CoinLabel", GameFonts.ui(800), UiTokens.FONT_SIZE_NUMBER_M, ink)
	_label(t, "BigScoreLabel", GameFonts.display(), BIG_SCORE_SIZE, ink)
	t.set_constant("line_spacing", "BigScoreLabel", -30)
	_label(t, "InkLabel", GameFonts.ui(800), 15, ink)
	_label(t, "StatusLabel", GameFonts.ui(800), UiTokens.FONT_SIZE_CAPTION, ink)
	_label(t, "OnInkLabel", GameFonts.ui(800), UiTokens.FONT_SIZE_CAPTION, white)


static func _label(t: Theme, type_name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, color)
	t.set_constant("outline_size", type_name, 0)


static func _hud_label(t: Theme, type_name: String, font: Font, size: int, halo: int) -> void:
	_label(t, type_name, font, size, HUD_FILL)
	t.set_color("font_outline_color", type_name, HUD_HALO)
	t.set_constant("outline_size", type_name, halo)


static func _buttons(t: Theme, room: Color) -> void:
	var ink := UiTokens.ON_PANEL
	var clear := StyleBoxEmpty.new()
	# Secondary (plain Button): a flat paper pill.
	var paper := flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 10)
	paper.content_margin_left = UiTokens.SPACE_5
	paper.content_margin_right = UiTokens.SPACE_5
	_button(t, "Button", paper, flat(UiTokens.PANEL_RAISED, UiTokens.RADIUS_PILL, 10), ink)
	_fonts(t, "Button", GameFonts.ui(800), UiTokens.FONT_SIZE_BUTTON)
	# Action: a flat ink pill (Unlock, Save name), white text.
	var solid := flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 10)
	solid.content_margin_left = UiTokens.SPACE_5
	solid.content_margin_right = UiTokens.SPACE_5
	var solid_down := solid.duplicate() as StyleBoxFlat
	solid_down.bg_color = UiTokens.PRIMARY.lightened(0.15)
	_button(t, "ActionButton", solid, solid_down, UiTokens.ON_PRIMARY)
	_fonts(t, "ActionButton", GameFonts.wide(900, 112), 20)
	var off := flat(DISABLED_FILL, UiTokens.RADIUS_PILL, 10)
	t.set_stylebox("disabled", "ActionButton", off)
	t.set_color("font_disabled_color", "ActionButton", ink)
	t.set_color("icon_disabled_color", "ActionButton", ink)
	# The main action: a 100px round ink button, its icon over its name.
	_primary(t, "PrimaryButton", UiTokens.PRIMARY, UiTokens.ON_PRIMARY)
	_primary(t, "PrimaryLight", UiTokens.PANEL, UiTokens.ON_PANEL)
	# Bare buttons: no box at all, just the icon (and text) in ink or white.
	_button(t, "RoundButton", clear, clear, room)
	t.set_constant("icon_max_width", "RoundButton", UiTokens.SIZE_ICON_M)
	# The HUD's bare icon button: its HaloIcon child draws the icon, so the
	# button's own icon (kept for its size and name) is clear.
	_button(t, "HudButton", clear, clear, HUD_FILL)
	for state in [
		"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"
	]:
		t.set_color(state, "HudButton", Color(HUD_FILL, 0.0))
	t.set_color("icon_disabled_color", "HudButton", Color(HUD_FILL, 0.0))
	_button(t, "PlainButton", clear, clear, room)
	_fonts(t, "PlainButton", GameFonts.ui(800), UiTokens.FONT_SIZE_BUTTON)
	# The same on paper cards: always ink, also on night rooms.
	_button(t, "InkButton", clear, clear, ink)
	t.set_constant("icon_max_width", "InkButton", UiTokens.SIZE_ICON_M)
	_fonts(t, "InkButton", GameFonts.ui(800), UiTokens.FONT_SIZE_BUTTON)
	_button(t, "ScrimButton", clear, clear, UiTokens.ON_SCRIM)
	_fonts(t, "ScrimButton", GameFonts.ui(800), UiTokens.FONT_SIZE_BUTTON)
	# Dock items: icon over a small name; the current one on a soft edge tile.
	var tile := flat(UiTokens.EDGE, 16, 2)
	_button(t, "DockButton", clear, flat(UiTokens.PANEL_RAISED, 16, 2), ink)
	t.set_stylebox("disabled", "DockButton", tile)
	_fonts(t, "DockButton", GameFonts.ui(800), UiTokens.FONT_SIZE_CAPTION)
	t.set_constant("h_separation", "DockButton", 2)
	t.set_constant("icon_max_width", "DockButton", 22)
	# Tabs inside a TabStrip: ink text, the selected one filled ink, white text.
	t.set_type_variation("TabButton", "Button")
	var tab := flat(Color(UiTokens.INK_LINE, 0.0), UiTokens.RADIUS_PILL, UiTokens.SPACE_2)
	var tab_on := flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, UiTokens.SPACE_2)
	for state in ["normal", "hover"]:
		t.set_stylebox(state, "TabButton", tab)
	for state in ["pressed", "hover_pressed"]:
		t.set_stylebox(state, "TabButton", tab_on)
	t.set_stylebox("focus", "TabButton", StyleBoxEmpty.new())
	_fonts(t, "TabButton", GameFonts.ui(800), 14)
	t.set_color("font_color", "TabButton", ink)
	t.set_color("font_hover_color", "TabButton", ink)
	t.set_color("font_pressed_color", "TabButton", UiTokens.ON_PRIMARY)
	t.set_color("font_hover_pressed_color", "TabButton", UiTokens.ON_PRIMARY)
	# Cards: each card sets its own box per state (selected, in use).
	t.set_type_variation("CardButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CardButton", flat())
	t.set_stylebox("focus", "CardButton", StyleBoxEmpty.new())


static func _primary(t: Theme, type_name: String, fill: Color, text: Color) -> void:
	var disc := flat(fill, UiTokens.RADIUS_PILL, 8)
	# A Button pins a top icon to the top margin and centres the name in what is
	# left below it. These margins put the icon and its name together in the
	# middle of the disc (icon 22..52, name 61..77 of 100); more margin would
	# grow the button past 100px.
	disc.content_margin_top = PRIMARY_PAD_TOP
	disc.content_margin_bottom = PRIMARY_PAD_BOTTOM
	var down := disc.duplicate() as StyleBoxFlat
	down.bg_color = fill.lightened(0.15) if fill.get_luminance() < 0.5 else fill.darkened(0.06)
	_button(t, type_name, disc, down, text)
	_fonts(t, type_name, GameFonts.wide(900, 112), 14)
	t.set_constant("icon_max_width", type_name, 30)
	t.set_constant("h_separation", type_name, 2)


static func _button(
	t: Theme, type_name: String, box: StyleBox, down: StyleBox, text: Color
) -> void:
	if type_name != "Button":
		t.set_type_variation(type_name, "Button")
	t.set_stylebox("normal", type_name, box)
	t.set_stylebox("hover", type_name, box)
	t.set_stylebox("pressed", type_name, down)
	t.set_stylebox("hover_pressed", type_name, down)
	t.set_stylebox("disabled", type_name, box)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = UiTokens.FOCUS
	focus.set_corner_radius_all(UiTokens.RADIUS_PILL)
	focus.set_expand_margin_all(3)
	t.set_stylebox("focus", type_name, focus)
	for state in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
	]:
		t.set_color(state, type_name, text)
	for state in [
		"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"
	]:
		t.set_color(state, type_name, text)
	t.set_color("font_disabled_color", type_name, Color(text, 0.6))
	t.set_color("icon_disabled_color", type_name, Color(text, 0.6))
	t.set_constant("icon_max_width", type_name, UiTokens.SIZE_ICON_M)
	t.set_constant("h_separation", type_name, UiTokens.SPACE_2)
	t.set_constant("outline_size", type_name, 0)


static func _fonts(t: Theme, type_name: String, font: Font, size: int) -> void:
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, size)
