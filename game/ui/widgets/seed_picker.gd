class_name SeedPicker
extends VBoxContainer
## On the debug page, in every build: type a run's seed (the game over screen
## shows it) and Play runs it again from the first room, as practice: the same
## rooms, spikes and coins, but no coins, best score or leaderboards. Pasting
## the whole "Seed 123456 · v11" line works too. The last seed is kept while
## the app runs.

## Play pressed with a valid seed.
signal play_pressed(seed_value: int)

## Seeds of real runs are randi(): 0 up to this.
const MAX_SEED := 4294967295
const FIELD_H := 44

## The last seed played from the picker (-1 = none yet).
static var last_seed := -1

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
	_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_field.text = str(last_seed) if last_seed >= 0 else ""
	_field.text_changed.connect(_check.unbind(1))
	_field.text_submitted.connect(play.unbind(1))
	row.add_child(_field)
	_play = _play_button()
	row.add_child(_play)
	add_child(row)
	_note = UiKit.label("", &"MutedLabel", false)
	_note.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	add_child(_note)
	_check()


## The seed in `text`: its first run of digits ("Seed 123 · v11" -> 123), or
## -1 when there is none or it is too big for a seed.
static func parse(text: String) -> int:
	var digits := ""
	for c in text:
		if c >= "0" and c <= "9":
			digits += c
		elif not digits.is_empty():
			break
	# More than 10 digits never fits; checked first so the int can't overflow.
	if digits.is_empty() or digits.length() > 10:
		return -1
	var value := digits.to_int()
	return value if value <= MAX_SEED else -1


## The seed typed now, or -1.
func seed_value() -> int:
	return parse(_field.text)


func set_text(text: String) -> void:
	_field.text = text
	_check()


## Plays the typed seed, if it is one, and keeps it.
func play() -> void:
	var s := seed_value()
	if s < 0:
		return
	last_seed = s
	play_pressed.emit(s)


func _check() -> void:
	var s := seed_value()
	_play.disabled = s < 0
	if _field.text.strip_edges().is_empty():
		_note.text = "A seed from the game over screen"
	elif s < 0:
		_note.text = "Not a seed: a number from 0 to %d" % MAX_SEED
	else:
		_note.text = "Plays seed %d from the first room, as practice" % s


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
	_field.placeholder_text = "Seed"


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
