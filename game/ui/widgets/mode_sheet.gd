class_name ModeSheet
extends Control
## The mode picker over Home: the dimmed room and a solid paper card under the
## wordmark with a row per game mode (its icon, name, one line of its rules or
## news, a gold badge, a tick on the chosen one). A tap on a row chooses that
## mode and closes; the close button or a tap on the dimmed room just closes.
## Home's big Play button then plays the chosen mode.

signal picked(id: String)
signal closed

const ROW_H := 60.0
const ICON := 40.0
## The card's top edge: under Home's wordmark.
const TOP := 178.0
const SIDE := 12

var _rows := {}


func _init(chosen: String, lines: Dictionary, badges: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	var card := PanelContainer.new()
	card.name = "Card"
	var box := UiTheme.solid(UiTokens.PANEL, UiTokens.RADIUS_M, 0)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", box)
	add_child(card)
	# Under Home's wordmark, well clear of the ceiling and floor spikes.
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_top = TOP
	card.offset_left = SIDE
	card.offset_right = -SIDE
	card.grow_vertical = Control.GROW_DIRECTION_END
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_1)
	card.add_child(col)
	var title := UiKit.label("Choose a mode", &"NameLabel", false)
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(UiKit.card_head(title, closed.emit))
	for m in GameModes.all():
		var row := _row(m, m.id == chosen, str(lines.get(m.id, m.rule)), str(badges.get(m.id, "")))
		_rows[m.id] = row
		col.add_child(row)


func _row(m: GameModes.Mode, on: bool, line: String, badge: String) -> Button:
	var b := Button.new()
	b.name = m.id
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = m.title
	b.custom_minimum_size = Vector2(0, ROW_H)
	var fill := UiTokens.PANEL_RAISED if on else Color(UiTokens.PANEL, 0.0)
	var box := UiTheme.flat(fill, UiTokens.RADIUS_M - 4, 0)
	var down := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_M - 4, 0)
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiTokens.SPACE_3
	row.offset_right = -UiTokens.SPACE_3
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	b.add_child(row)
	var disc := PanelContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.custom_minimum_size = Vector2(ICON, ICON)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override(
		"panel", UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, 0)
	)
	var icon := TextureRect.new()
	icon.texture = m.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(icon)
	row.add_child(disc)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", UiTokens.SPACE_2)
	text.add_child(head)
	head.add_child(UiKit.label(m.title, &"SmallNameLabel", false))
	if not badge.is_empty():
		var tag := Badge.make(badge)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tag)
	var rule := UiKit.label(line, &"MutedLabel", false)
	rule.name = "Line"
	rule.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	rule.clip_text = true
	rule.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(rule)
	if on:
		var tick := TextureRect.new()
		tick.name = "Tick"
		tick.texture = preload("res://assets/ui/icons/check.svg")
		tick.modulate = UiTokens.ON_PANEL
		tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tick.custom_minimum_size = Vector2(20, 20)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tick)
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


func row(id: String) -> Button:
	return _rows.get(id) as Button


func row_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _rows:
		out.append(id)
	return out
