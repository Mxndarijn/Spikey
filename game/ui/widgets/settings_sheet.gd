class_name SettingsSheet
extends Control
## The settings sheet over Home (the dock's Settings): a paper card on the
## dimmed room with a close X.
##   Sound: Music and Sounds, each a round on/off button with its icon, the
##          name, a volume slider (0 to 100) and the value.
##   Play:  Haptics, Reduced flashing, Color-blind spikes, Large buttons.
##   Credits at the bottom (opens the credits in the same card).
##   Ad choices, only where the player has an ad privacy choice to change
##   (Europe), opens Google's form; it shares the Credits row.
##   Debug (DebugPage), also in the same card: the Debug link in that row
##   (every build), or tap the "Settings" title seven times.
## Every change goes straight into the profile and emits `changed`; main saves
## and applies it (audio, RoomView.flash_enabled, button size, spikes).

signal changed
signal closed
## The debug page's room picker: practise room `id` with `variant`.
signal practice_requested(id: String, variant: String)
## The debug page's seed picker: play seed `seed_value` in `season` as practice.
signal seed_requested(seed_value: int, season: int)

const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const CHEVRON_ICON := preload("res://assets/ui/icons/chevron.svg")
const MUSIC_ICON := preload("res://assets/ui/icons/music.svg")
const SOUND_ICON := preload("res://assets/ui/icons/sound.svg")
const MARGIN_TOP := 40
const MARGIN_BOTTOM := 30
const SIDE := 14
const TOGGLE := 44.0
## Settings > Play: PlayerSettings.Switch -> [name, hint], in screen order.
const SWITCHES: Dictionary[PlayerSettings.Switch, Array] = {
	PlayerSettings.Switch.HAPTICS: ["Haptics", "A little buzz on flap and crash"],
	PlayerSettings.Switch.REDUCED_FLASHING:
	["Reduced flashing", "No room flash or shake, slow sky fades"],
	PlayerSettings.Switch.COLOR_BLIND_SPIKES:
	["Color-blind spikes", "Spikes turn dark with a white edge"],
	PlayerSettings.Switch.LARGE_BUTTONS: ["Large buttons", "Pause and HUD buttons grow to 56px"],
	PlayerSettings.Switch.BOARD_ALERTS:
	["Board alerts", "A notification when you lose a prize spot"],
}
const CREDITS := [
	["Font", "Archivo by the Archivo Project Authors, SIL Open Font License 1.1."],
	["Engine", "Made with Godot Engine, MIT license, (c) the Godot Engine contributors."],
]

var _profile: Profile
var _services: AppServices
var _sliders := {}
var _toggles := {}
var _values := {}
var _switches: Dictionary[PlayerSettings.Switch, SettingSwitch] = {}
var _main_page := VBoxContainer.new()
var _credits_page := VBoxContainer.new()
var _debug_page := VBoxContainer.new()
var _debug: DebugPage
var _title_taps := 0


func _init(profile: Profile, services: AppServices) -> void:
	_profile = profile
	_services = services
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
	for page: VBoxContainer in [_main_page, _credits_page, _debug_page]:
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
	var head := _head("Settings", UiKit.icon_button(CLOSE_ICON, "Close"), close_dialog)
	var title := head.get_node("Title") as Label
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_title_input)
	_main_page.add_child(head)
	_main_page.add_child(_section("Sound"))
	_main_page.add_child(_volume_row("music", "Music", MUSIC_ICON))
	_main_page.add_child(_volume_row("sfx", "Sounds", SOUND_ICON))
	var play := _section("Play")
	play.custom_minimum_size.y += 6
	play.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_main_page.add_child(play)
	for key: PlayerSettings.Switch in SWITCHES:
		var s := SettingSwitch.new(SWITCHES[key][0], SWITCHES[key][1])
		s.name = PlayerSettings.Switch.find_key(key)
		s.toggled.connect(_on_switch.bind(key))
		_main_page.add_child(s)
		_switches[key] = s
	_main_page.add_child(UiKit.spacer(0, true))
	var credits := _link("Credits", "Credits")
	credits.pressed.connect(show_credits.bind(true))
	_main_page.add_child(_divider())
	var ads := _services.ads
	var links: Array[Button] = []
	if ads != null and ads.privacy_options_required():
		var choices := _link("AdChoices", "Ad choices")
		choices.pressed.connect(ads.show_privacy_options)
		links.append(choices)
	links.append(credits)
	var debug := _link("Debug", "Debug")
	debug.pressed.connect(show_debug.bind(true))
	links.append(debug)
	# Side by side, so the extra links don't push the sheet off the screen.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_4)
	for b: Button in links:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_main_page.add_child(row)


## A plain ink row with a chevron that opens something.
func _link(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.theme_type_variation = &"PlainButton"
	b.text = text
	b.icon = CHEVRON_ICON
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("icon_max_width", 14)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.focus_mode = Control.FOCUS_NONE
	return b


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
	t.name = "Title"
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
	var vols := {"music": _profile.settings.music_volume, "sfx": _profile.settings.sfx_volume}
	var ons := {"music": _profile.settings.music_on, "sfx": _profile.settings.sfx_on}
	for which: String in ["music", "sfx"]:
		(_sliders[which] as VolumeSlider).set_value_no_signal(vols[which])
		(_toggles[which] as Button).set_pressed_no_signal(ons[which])
		_show(which)
	for key: PlayerSettings.Switch in SWITCHES:
		_switches[key].set_pressed_no_signal(_profile.settings.is_on(key))
		_switches[key].queue_redraw()


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
		_profile.settings.music_volume = int(v)
	else:
		_profile.settings.sfx_volume = int(v)
	_show(which)
	changed.emit()


func _on_toggle(on: bool, which: String) -> void:
	if which == "music":
		_profile.settings.music_on = on
	else:
		_profile.settings.sfx_on = on
	_show(which)
	changed.emit()


func _on_switch(on: bool, key: PlayerSettings.Switch) -> void:
	_profile.settings.set_on(key, on)
	changed.emit()


## For tests and keys: set a volume as if dragged.
func set_volume(which: String, v: int) -> void:
	(_sliders[which] as VolumeSlider).value = v


## For tests and keys: flip a sound on or off as if tapped.
func set_on(which: String, on: bool) -> void:
	(_toggles[which] as Button).button_pressed = on


## For tests: flip a Play setting as if tapped.
func set_switch(key: PlayerSettings.Switch, on: bool) -> void:
	_switches[key].button_pressed = on


func value_text(which: String) -> String:
	return (_values[which] as Label).text


func slider(which: String) -> VolumeSlider:
	return _sliders[which] as VolumeSlider


func switch(key: PlayerSettings.Switch) -> SettingSwitch:
	return _switches.get(key)


func show_credits(value: bool) -> void:
	_show_page(_credits_page if value else _main_page)


## The debug page (built the first time it opens), or back to the settings.
func show_debug(value: bool) -> void:
	if value and _debug == null:
		var back := UiKit.icon_button(BACK_ICON, "Back")
		_debug_page.add_child(_head("Debug", back, show_debug.bind(false), true))
		_debug = DebugPage.new(_profile, _services)
		_debug.changed.connect(changed.emit)
		_debug.practice_requested.connect(practice_requested.emit)
		_debug.seed_requested.connect(seed_requested.emit)
		_debug_page.add_child(_debug)
	_title_taps = 0
	_show_page(_debug_page if value else _main_page)


## The open debug page, or null.
func debug_page() -> DebugPage:
	return _debug if _debug_page.visible else null


## One tap on the "Settings" title; enough of them open the debug page.
func tap_title() -> void:
	_title_taps += 1
	if _title_taps >= DebugPage.TAPS_TO_OPEN:
		show_debug(true)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		tap_title()


func _show_page(page: Control) -> void:
	for p: Control in [_main_page, _credits_page, _debug_page]:
		p.visible = p == page


func is_showing_credits() -> bool:
	return _credits_page.visible


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_dialog()


func close_dialog() -> void:
	closed.emit()
	queue_free()
