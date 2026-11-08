class_name SettingsSheet
extends Control
## The settings sheet over Home (the dock's Settings): a paper card on the
## dimmed room with a close X.
##   Sound: Music and Sounds, each a round on/off button with its icon, the
##          name, a volume slider (0 to 100) and the value.
##   Play:  Haptics, Reduced flashing, Color-blind spikes, Large buttons.
##   Credits and licenses at the bottom (opens the credits in the same card).
## Every change goes straight into the profile and emits `changed`; main saves
## and applies it (audio, RoomView.flash_enabled, button size, spikes).

signal changed
signal closed

const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const CHEVRON_ICON := preload("res://assets/ui/icons/chevron.svg")
const MUSIC_ICON := preload("res://assets/ui/icons/music.svg")
const SOUND_ICON := preload("res://assets/ui/icons/sound.svg")
const MARGIN_TOP := 40
const MARGIN_BOTTOM := 30
const SIDE := 14
const TOGGLE := 44.0
## Settings > Play: profile field -> [name, hint].
const SWITCHES := {
	"haptics": ["Haptics", "A little buzz on flap and crash"],
	"reduced_flashing": ["Reduced flashing", "No room flash or shake, slow sky fades"],
	"color_blind_spikes": ["Color-blind spikes", "Spikes turn dark with a white edge"],
	"large_buttons": ["Large buttons", "Pause and HUD buttons grow to 56px"],
}
const CREDITS := [
	["Font", "Archivo by the Archivo Project Authors, SIL Open Font License 1.1."],
	["Engine", "Made with Godot Engine, MIT license, (c) the Godot Engine contributors."],
]

var _profile: Profile
var _sliders := {}
var _toggles := {}
var _values := {}
var _switches := {}
var _main_page := VBoxContainer.new()
var _credits_page := VBoxContainer.new()


func _init(profile: Profile) -> void:
	_profile = profile
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", MARGIN_TOP)
	margin.add_theme_constant_override("margin_bottom", MARGIN_BOTTOM)
	add_child(margin)
	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", _card_box())
	margin.add_child(card)
	# One page shows at a time; a hidden page takes no room.
	var pages := VBoxContainer.new()
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pages)
	for page: VBoxContainer in [_main_page, _credits_page]:
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", UiTokens.SPACE_2)
		pages.add_child(page)
	_build_main()
	_build_credits()
	show_credits(false)
	_sync()


static func _card_box() -> StyleBoxFlat:
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, 16)
	box.content_margin_left = 18
	box.content_margin_right = 18
	return box


func _build_main() -> void:
	_main_page.add_child(_head("Settings", UiKit.icon_button(CLOSE_ICON, "Close"), close_dialog))
	_main_page.add_child(_section("Sound"))
	_main_page.add_child(_volume_row("music", "Music", MUSIC_ICON))
	_main_page.add_child(_volume_row("sfx", "Sounds", SOUND_ICON))
	var play := _section("Play")
	play.custom_minimum_size.y += 6
	play.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_main_page.add_child(play)
	for key: String in SWITCHES:
		var s := SettingSwitch.new(SWITCHES[key][0], SWITCHES[key][1])
		s.name = key
		s.toggled.connect(_on_switch.bind(key))
		_main_page.add_child(s)
		_switches[key] = s
	_main_page.add_child(UiKit.spacer(0, true))
	var credits := Button.new()
	credits.name = "Credits"
	credits.theme_type_variation = &"PlainButton"
	credits.text = "Credits and licenses"
	credits.icon = CHEVRON_ICON
	credits.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits.alignment = HORIZONTAL_ALIGNMENT_LEFT
	credits.add_theme_constant_override("icon_max_width", 14)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		credits.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		credits.add_theme_color_override(state, UiTokens.ON_PANEL)
	credits.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	credits.focus_mode = Control.FOCUS_NONE
	credits.pressed.connect(show_credits.bind(true))
	_main_page.add_child(_divider())
	_main_page.add_child(credits)


func _build_credits() -> void:
	var back := UiKit.icon_button(BACK_ICON, "Back")
	_credits_page.add_child(_head("Credits", back, show_credits.bind(false), true))
	for row: Array in CREDITS:
		_credits_page.add_child(_section(row[0]))
		var l := UiKit.wrapped(row[1], &"CaptionLabel", 280)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.add_theme_font_size_override("font_size", 14)
		_credits_page.add_child(l)


## The card's title row: title at the left (display 28), a bare icon button.
func _head(title: String, button: Button, on_press: Callable, back_first: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UiKit.label(title, &"NameLabel", false)
	t.add_theme_font_size_override("font_size", 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	_ink_icon(button)
	button.pressed.connect(on_press)
	if back_first:
		row.add_child(button)
		row.add_child(t)
	else:
		row.add_child(t)
		row.add_child(button)
	return row


## Bare buttons on paper stay ink, also on night rooms.
static func _ink_icon(b: Button) -> void:
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)


func _section(text: String) -> Label:
	var l := UiKit.label(text, &"MutedLabel", false)
	l.add_theme_font_override("font", GameFonts.ui(800))
	return l


func _divider() -> Control:
	var line := ColorRect.new()
	line.color = UiTokens.EDGE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## A sound row: a round on/off button with the icon, the name, the slider and
## the value. `which` is "music" or "sfx".
func _volume_row(which: String, label: String, icon: Texture2D) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var toggle := Button.new()
	toggle.name = which + "_on"
	toggle.toggle_mode = true
	toggle.icon = icon
	toggle.tooltip_text = "%s on or off" % label
	toggle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(TOGGLE, TOGGLE)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var off := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
	var on := UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover", "disabled"]:
		toggle.add_theme_stylebox_override(state, off)
	for state in ["pressed", "hover_pressed"]:
		toggle.add_theme_stylebox_override(state, on)
	toggle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	toggle.add_theme_constant_override("icon_max_width", 20)
	for state in ["icon_normal_color", "icon_hover_color"]:
		toggle.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
		toggle.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	toggle.toggled.connect(_on_toggle.bind(which))
	row.add_child(toggle)
	_toggles[which] = toggle
	var name_label := UiKit.label(label, &"InkLabel", false)
	name_label.custom_minimum_size = Vector2(60, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_FILL
	row.add_child(name_label)
	var slider := VolumeSlider.new()
	slider.tooltip_text = "%s volume" % label
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider.bind(which))
	row.add_child(slider)
	_sliders[which] = slider
	var value := UiKit.label("", &"InkLabel", false)
	value.custom_minimum_size = Vector2(34, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_vertical = Control.SIZE_FILL
	row.add_child(value)
	_values[which] = value
	return row


## Shows the profile's values without emitting `changed`.
func _sync() -> void:
	var vols := {"music": _profile.music_volume, "sfx": _profile.sfx_volume}
	var ons := {"music": _profile.music_on, "sfx": _profile.sfx_on}
	for which: String in ["music", "sfx"]:
		(_sliders[which] as VolumeSlider).set_value_no_signal(vols[which])
		(_toggles[which] as Button).set_pressed_no_signal(ons[which])
		_show(which)
	for key: String in SWITCHES:
		(_switches[key] as SettingSwitch).set_pressed_no_signal(bool(_profile.get(key)))
		(_switches[key] as SettingSwitch).queue_redraw()


func _show(which: String) -> void:
	var slider := _sliders[which] as VolumeSlider
	var toggle := _toggles[which] as Button
	var value := _values[which] as Label
	value.text = str(int(slider.value))
	var on := toggle.button_pressed
	slider.faded = not on
	value.modulate.a = 1.0 if on else UiTokens.OPACITY_DISABLED
	toggle.tooltip_text = (
		"%s %s" % ["Music" if which == "music" else "Sounds", "on" if on else "off"]
	)


func _on_slider(v: float, which: String) -> void:
	if which == "music":
		_profile.music_volume = int(v)
	else:
		_profile.sfx_volume = int(v)
	_show(which)
	changed.emit()


func _on_toggle(on: bool, which: String) -> void:
	if which == "music":
		_profile.music_on = on
	else:
		_profile.sfx_on = on
	_show(which)
	changed.emit()


func _on_switch(on: bool, key: String) -> void:
	_profile.set(key, on)
	changed.emit()


## For tests and keys: set a volume as if dragged.
func set_volume(which: String, v: int) -> void:
	(_sliders[which] as VolumeSlider).value = v


## For tests and keys: flip a sound on or off as if tapped.
func set_on(which: String, on: bool) -> void:
	(_toggles[which] as Button).button_pressed = on


## For tests: flip a Play setting (a profile field name) as if tapped.
func set_switch(key: String, on: bool) -> void:
	(_switches[key] as SettingSwitch).button_pressed = on


func value_text(which: String) -> String:
	return (_values[which] as Label).text


func slider(which: String) -> VolumeSlider:
	return _sliders[which] as VolumeSlider


func switch(key: String) -> SettingSwitch:
	return _switches.get(key) as SettingSwitch


func show_credits(value: bool) -> void:
	_main_page.visible = not value
	_credits_page.visible = value


func is_showing_credits() -> bool:
	return _credits_page.visible


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_dialog()


func close_dialog() -> void:
	closed.emit()
	queue_free()
