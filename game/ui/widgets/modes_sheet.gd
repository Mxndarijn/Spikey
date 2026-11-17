class_name ModesSheet
extends Control
## The All modes sheet over Home (docs/DUEL_MODE.md, "The mode picker"): a
## paper card over the dimmed room with every game mode as a tile in two
## columns, the chosen one outlined in ink. A tap on a tile chooses that mode
## and closes; the close button or a tap on the dimmed room just closes.

signal picked(id: String)
signal closed

const SIDE := 20
const TILE_H := 104.0

var _tiles := {}


func _init(chosen: String, daily: DailyRunInfo = null) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)
	var title := UiKit.label("Modes", &"NameLabel", false)
	col.add_child(UiKit.card_head(title, closed.emit))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiTokens.SPACE_2)
	grid.add_theme_constant_override("v_separation", UiTokens.SPACE_2)
	col.add_child(grid)
	for m in GameModes.all():
		var tile := _tile(m, m.id == chosen, daily)
		_tiles[m.id] = tile
		grid.add_child(tile)


func _tile(m: GameModes.Mode, on: bool, daily: DailyRunInfo) -> Button:
	var b := Button.new()
	b.name = m.id
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = m.title
	b.custom_minimum_size = Vector2(0, TILE_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := UiTokens.ON_PRIMARY if on else UiTokens.PANEL_RAISED
	var box := UiTheme.flat(fill, UiTokens.RADIUS_M - 4, 0)
	if on:
		box.border_color = UiTokens.ON_PANEL
		box.set_border_width_all(3)
	var down := box.duplicate() as StyleBoxFlat
	down.bg_color = UiTokens.EDGE
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UiTokens.SPACE_3
	col.offset_right = -UiTokens.SPACE_3
	col.offset_top = UiTokens.SPACE_3
	col.offset_bottom = -UiTokens.SPACE_3
	col.add_theme_constant_override("separation", 2)
	b.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var icon := TextureRect.new()
	icon.texture = m.icon
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UiTokens.ON_PANEL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(icon)
	var spring := Control.new()
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spring)
	var badge_text := GameModes.badge(m.id, daily)
	if not badge_text.is_empty():
		var badge := UiKit.label(badge_text, &"OnInkLabel")
		badge.name = "Badge"
		badge.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
		var ink := UiTheme.flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0)
		ink.content_margin_left = UiTokens.SPACE_2
		ink.content_margin_right = UiTokens.SPACE_2
		ink.content_margin_top = 2
		ink.content_margin_bottom = 2
		badge.add_theme_stylebox_override("normal", ink)
		badge.add_theme_color_override("font_color", UiTokens.ON_PRIMARY)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(badge)
	var name_label := UiKit.label(m.title, &"SmallNameLabel", false)
	name_label.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_NUMBER_M)
	col.add_child(name_label)
	var rule := UiKit.wrapped(GameModes.rule_line(m.id, daily), &"MutedLabel")
	rule.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	b.pressed.connect(pick.bind(m.id))
	return b


func _on_scrim_input(event: InputEvent) -> void:
	var tap := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if tap or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		closed.emit()


## Chooses a mode and closes.
func pick(id: String) -> void:
	AudioDirector.ui("tap")
	picked.emit(id)
	closed.emit()


func tile(id: String) -> Button:
	return _tiles.get(id) as Button


func tile_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _tiles:
		out.append(id)
	return out
