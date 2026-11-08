class_name SoundSettings
extends Control
## The sound settings popup (Sticker Pop), opened by the gear on the home screen:
## a card over the scrim with a Music row and a Sounds row, each a volume
## slider (0 to 100) with its value and an On/Off pill, then Done.
## Every change goes straight into the profile and emits `changed`, so the
## player hears it at once; the home screen saves and applies it.

signal changed
signal closed

const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
const TOP := 150
const SWITCH := Vector2(64, 36)

var _profile: Profile
var _sliders := {}
var _switches := {}
var _values := {}


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
	margin.add_theme_constant_override("margin_left", UiTokens.SPACE_5)
	margin.add_theme_constant_override("margin_right", UiTokens.SPACE_5)
	margin.add_theme_constant_override("margin_top", TOP)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)
	margin.add_child(Tilt.new(card, -1.0))

	var head := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"NameLabel"
	title.add_theme_font_size_override("font_size", 28)
	title.text = "Sound"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var close := Button.new()
	close.theme_type_variation = &"RoundButton"
	close.icon = CLOSE_ICON
	close.tooltip_text = "Close"
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_dialog)
	head.add_child(close)
	col.add_child(head)
	col.add_child(_row("music", "Music"))
	col.add_child(_row("sfx", "Sounds"))
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close_dialog)
	col.add_child(done)
	_sync()


## One setting: its name, the value and the On/Off pill over the slider.
## `which` is "music" or "sfx".
func _row(which: String, label: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var name_label := Label.new()
	name_label.theme_type_variation = &"InkLabel"
	name_label.add_theme_font_override("font", GameFonts.ui(900))
	name_label.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BUTTON)
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_label)
	var value := Label.new()
	value.theme_type_variation = &"CoinLabel"
	value.custom_minimum_size = Vector2(36, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(value)
	_values[which] = value
	var switch := Button.new()
	switch.toggle_mode = true
	switch.focus_mode = Control.FOCUS_NONE
	switch.custom_minimum_size = SWITCH
	switch.tooltip_text = "%s on or off" % label
	switch.add_theme_font_override("font", GameFonts.ui(900))
	switch.add_theme_font_size_override("font_size", 15)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var on := state.contains("pressed")
		var fill := UiTokens.SUCCESS if on else UiTokens.PANEL
		var pill := UiTheme.sticker(fill, UiTokens.RADIUS_PILL, Vector2(0, 3), 4)
		switch.add_theme_stylebox_override(state, pill)
	switch.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	switch.add_theme_color_override("font_hover_color", UiTokens.ON_PANEL_MUTED)
	switch.add_theme_color_override("font_pressed_color", UiTokens.ON_PANEL)
	switch.add_theme_color_override("font_hover_pressed_color", UiTokens.ON_PANEL)
	switch.toggled.connect(_on_switch.bind(which))
	line.add_child(switch)
	_switches[which] = switch
	box.add_child(line)
	var slider := StickerSlider.new()
	slider.tooltip_text = "%s volume" % label
	slider.value_changed.connect(_on_slider.bind(which))
	box.add_child(slider)
	_sliders[which] = slider
	return box


## Shows the profile's values without emitting `changed`.
func _sync() -> void:
	var vols := {"music": _profile.music_volume, "sfx": _profile.sfx_volume}
	var ons := {"music": _profile.music_on, "sfx": _profile.sfx_on}
	for which: String in ["music", "sfx"]:
		(_sliders[which] as StickerSlider).set_value_no_signal(vols[which])
		(_switches[which] as Button).set_pressed_no_signal(ons[which])
		_show(which)


func _show(which: String) -> void:
	var slider := _sliders[which] as StickerSlider
	var switch := _switches[which] as Button
	(_values[which] as Label).text = str(int(slider.value))
	switch.text = "On" if switch.button_pressed else "Off"
	slider.faded = not switch.button_pressed
	slider.queue_redraw()


func _on_slider(v: float, which: String) -> void:
	if which == "music":
		_profile.music_volume = int(v)
	else:
		_profile.sfx_volume = int(v)
	_show(which)
	changed.emit()


func _on_switch(on: bool, which: String) -> void:
	if which == "music":
		_profile.music_on = on
	else:
		_profile.sfx_on = on
	_show(which)
	changed.emit()


## For tests and keys: set a volume as if dragged.
func set_volume(which: String, v: int) -> void:
	(_sliders[which] as StickerSlider).value = v


## For tests and keys: flip a sound on or off as if tapped.
func set_on(which: String, on: bool) -> void:
	(_switches[which] as Button).button_pressed = on


func value_text(which: String) -> String:
	return (_values[which] as Label).text


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_dialog()


func close_dialog() -> void:
	closed.emit()
	queue_free()
