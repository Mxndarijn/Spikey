class_name SeedPicker
extends VBoxContainer
## On the debug page, in every build: type a run's seed code (the game over
## screen shows it, SeedCode) and Play runs it again from the first room, as
## practice: the same rooms, spikes and coins, in the code's own season, but
## no coins, best score or leaderboards. Pasting the whole game over line
## works too, and so do old seed numbers (no season). The note under the field
## says which season and version the code holds. The last seed is kept while
## the app runs.

## Play pressed with a valid seed: its random part and season.
signal play_pressed(seed_value: int, season: int)

const FIELD_H := 44

## The last seed typed and played from the picker ("" = none yet).
static var last_text := ""

var _field := LineEdit.new()
var _play: Button
var _note: Label


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	_style_field()
	_field.name = "SeedField"
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.custom_minimum_size = Vector2(0, FIELD_H)
	_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_field.text = last_text
	_field.text_changed.connect(_check.unbind(1))
	_field.text_submitted.connect(play.unbind(1))
	row.add_child(_field)
	_play = _play_button()
	row.add_child(_play)
	add_child(row)
	_note = UiKit.label("", &"MutedLabel", false)
	_note.name = "SeedNote"
	_note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	_check()


## The seed in `text` (SeedCode.decode), or null.
static func parse(text: String) -> SeedCode.Parts:
	return SeedCode.decode(text)


## The note under the field for `text`.
static func note_for(text: String) -> String:
	if text.strip_edges().is_empty():
		return "A seed code from the game over screen"
	var parts := parse(text)
	if parts == null:
		return SeedCode.problem(text)
	var now := SimConfig.GAMEPLAY_VERSION
	if parts.legacy:
		return "Old seed: plays with no season on v%d" % now
	var held := SeedCode.describe(parts)
	if parts.version != now:
		return "%s. This build plays v%d: the map will differ" % [held, now]
	return "%s. Plays from the first room, as practice" % held


## The seed typed now, or null.
func parts() -> SeedCode.Parts:
	return parse(_field.text)


func set_text(text: String) -> void:
	_field.text = text
	_check()


## Plays the typed seed, if it is one, and keeps it.
func play() -> void:
	var p := parts()
	if p == null:
		return
	last_text = _field.text
	play_pressed.emit(p.random, p.season)


func _check() -> void:
	_play.disabled = parts() == null
	_note.text = note_for(_field.text)


func _style_field() -> void:
	var box := UiTheme.ringed(Color.WHITE, UiTokens.RADIUS_PILL, 0, UiTokens.INK_LINE, 3)
	box.content_margin_left = UiTokens.SPACE_4
	box.content_margin_right = UiTokens.SPACE_4
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = UiTokens.INK_900
	_field.add_theme_stylebox_override("normal", box)
	_field.add_theme_stylebox_override("focus", focus)
	_field.add_theme_font_override("font", GameFonts.ui(800))
	_field.add_theme_font_size_override("font_size", 16)
	_field.add_theme_color_override("font_color", UiTokens.ON_PANEL)
	_field.add_theme_color_override("caret_color", UiTokens.ON_PANEL)
	_field.add_theme_color_override("font_placeholder_color", UiTokens.ON_PANEL_MUTED)
	_field.placeholder_text = "K7Q2M-9XH4D"


## The ink Play button beside the field.
func _play_button() -> Button:
	var b := Button.new()
	b.name = "PlaySeed"
	b.text = "Play"
	b.theme_type_variation = &"PlainButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, FIELD_H)
	b.add_theme_font_override("font", GameFonts.ui(800))
	b.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BUTTON)
	var ink := UiTheme.flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, UiTokens.SPACE_4)
	var off := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, UiTokens.SPACE_4)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, ink)
	b.add_theme_stylebox_override("disabled", off)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		b.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	b.add_theme_color_override("font_disabled_color", UiTokens.ON_PANEL_MUTED)
	b.pressed.connect(play)
	return b
