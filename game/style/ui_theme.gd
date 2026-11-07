class_name UiTheme
extends RefCounted
## Builds the Godot Theme for the HUD and menus from the design kit's UI tokens.
## Controls pick a look with theme_type_variation:
##   Button: ActionButton (gold, one per screen), PauseButton; plain Button = secondary
##   PanelContainer: SheetPanel
##   Label: TitleLabel, ScoreLabel, MutedLabel, TagLabel, SkyLabel

const LIFT_ALPHA := 0.35

static var _theme: Theme


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
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	t.set_type_variation("SheetPanel", "PanelContainer")
	t.set_stylebox("panel", "SheetPanel", _box(UiTokens.PANEL, UiTokens.RADIUS_L, UiTokens.SPACE_5))
	t.set_constant("separation", "VBoxContainer", UiTokens.SPACE_3)
	return t


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", UiTokens.ON_PANEL)
	_label(t, "TitleLabel", GameFonts.display(), UiTokens.FONT_SIZE_TITLE_L, UiTokens.ON_PANEL)
	_label(t, "ScoreLabel", GameFonts.display(), UiTokens.FONT_SIZE_SCORE_FINAL, UiTokens.ON_PANEL)
	_label(t, "MutedLabel", GameFonts.ui(700), UiTokens.FONT_SIZE_LABEL, UiTokens.ON_PANEL_MUTED)
	_label(t, "TagLabel", GameFonts.ui(800), UiTokens.FONT_SIZE_TAG, UiTokens.PANEL)
	var tag := _box(UiTokens.SUCCESS, UiTokens.RADIUS_S, 0)
	tag.content_margin_left = UiTokens.SPACE_2
	tag.content_margin_right = UiTokens.SPACE_2
	tag.content_margin_top = 2
	tag.content_margin_bottom = 2
	t.set_stylebox("normal", "TagLabel", tag)
	# Text straight on the sky always gets a 3px ink outline (kit: on-sky).
	_label(t, "SkyLabel", GameFonts.ui(800), UiTokens.FONT_SIZE_HEADING, UiTokens.ON_SKY)
	t.set_color("font_outline_color", "SkyLabel", UiTokens.INK_900)
	t.set_constant("outline_size", "SkyLabel", 6)


static func _label(t: Theme, type_name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, color)


static func _buttons(t: Theme) -> void:
	var lift := Color(UiTokens.INK_900, LIFT_ALPHA)
	# Secondary (plain Button)
	_button(t, "Button", UiTokens.PANEL_RAISED, lift, UiTokens.ON_PANEL, UiTokens.RADIUS_M)
	# Action: gold with its own solid edge
	t.set_type_variation("ActionButton", "Button")
	_button(
		t,
		"ActionButton",
		UiTokens.ACTION,
		UiTokens.ACTION_EDGE,
		UiTokens.ON_ACTION,
		UiTokens.RADIUS_M
	)
	# Round HUD button
	t.set_type_variation("PauseButton", "Button")
	# Padding (44 - 24) / 2 keeps it a 44px disc around the 24px icon.
	var icon_pad := (UiTokens.SIZE_TAP_MIN - UiTokens.SIZE_ICON_M) / 2
	_button(
		t,
		"PauseButton",
		UiTokens.PANEL,
		lift,
		UiTokens.ON_PANEL,
		UiTokens.SIZE_TAP_MIN / 2,
		icon_pad,
		icon_pad
	)
	t.set_constant("icon_max_width", "PauseButton", UiTokens.SIZE_ICON_M)


static func _button(
	t: Theme,
	type_name: String,
	fill: Color,
	edge: Color,
	text: Color,
	radius: int,
	pad_x: int = UiTokens.SPACE_5,
	pad_y: int = UiTokens.SPACE_2
) -> void:
	var normal := _box(fill, radius, pad_x)
	normal.content_margin_top = pad_y
	normal.content_margin_bottom = pad_y
	normal.shadow_color = edge
	normal.shadow_offset = Vector2(0, 4)
	normal.shadow_size = 0
	# Pressed: the button drops 3px and its edge shrinks to 1px (kit: lift-pressed).
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.shadow_offset = Vector2(0, 1)
	pressed.expand_margin_top = -3
	pressed.expand_margin_bottom = 3
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = UiTokens.FOCUS
	focus.set_corner_radius_all(radius + 3)
	focus.set_expand_margin_all(3)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(fill, UiTokens.OPACITY_DISABLED)
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, normal)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("hover_pressed", type_name, pressed)
	t.set_stylebox("focus", type_name, focus)
	t.set_stylebox("disabled", type_name, disabled)
	t.set_font("font", type_name, GameFonts.ui(800))
	t.set_font_size("font_size", type_name, UiTokens.FONT_SIZE_BUTTON)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, type_name, text)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		t.set_color(state, type_name, text)
	t.set_color("font_disabled_color", type_name, Color(text, UiTokens.OPACITY_DISABLED))


static func _box(fill: Color, radius: int, padding: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(padding)
	b.anti_aliasing = true
	return b
