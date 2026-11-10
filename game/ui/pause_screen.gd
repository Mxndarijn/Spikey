class_name PauseScreen
extends ColorRect
## Paused: the dimmed room with "Paused", the score, Music and Sounds toggle
## circles, the round Resume, and Home ("Ends this run"; not in practice).

signal resume_pressed
signal home_pressed
## A sound circle was tapped: `which` is "music" or "sfx".
signal sound_toggled(which: String, on: bool)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const HOME_ICON := preload("res://assets/ui/icons/home.svg")
const MUSIC_ICON := preload("res://assets/ui/icons/music.svg")
const SOUND_ICON := preload("res://assets/ui/icons/sound.svg")
const TOGGLE := 56.0

var _score := Label.new()
var _toggles: Dictionary[String, Button] = {}
var _home: Control


func _init() -> void:
	color = UiTokens.SCRIM
	ScrimBleed.attach(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, UiKit.label("Paused", &"ScrimTitle"), 88)
	_score.theme_type_variation = &"ScrimScore"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.across(self, _score, 146)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.add_child(_toggle("music", MUSIC_ICON))
	row.add_child(_toggle("sfx", SOUND_ICON))
	UiKit.across(self, row, 260)
	var resume := UiKit.primary(PLAY_ICON, "Resume", true)
	resume.name = "Resume"
	resume.anchor_left = 0.5
	resume.anchor_right = 0.5
	resume.offset_left = -UiKit.PRIMARY / 2.0
	resume.offset_right = UiKit.PRIMARY / 2.0
	resume.offset_top = 380
	resume.offset_bottom = 380 + UiKit.PRIMARY
	resume.pressed.connect(resume_pressed.emit)
	add_child(resume)
	_home = UiKit.scrim_link(HOME_ICON, "Home", "Ends this run", true)
	UiKit.link_button(_home).pressed.connect(home_pressed.emit)
	UiKit.across(self, _home, 500)


## Shows the score and the sound switches as they are; `can_go_home`: Home
## shows (practice has its own way back).
func show_state(score_text: String, music_on: bool, sfx_on: bool, can_go_home: bool) -> void:
	_score.text = score_text
	_home.visible = can_go_home
	_toggles["music"].set_pressed_no_signal(music_on)
	_toggles["sfx"].set_pressed_no_signal(sfx_on)
	_show_toggle("music")
	_show_toggle("sfx")


func score_text() -> String:
	return _score.text


func toggle(which: String) -> Button:
	return _toggles[which]


func home_visible() -> bool:
	return _home.visible


## A Music or Sounds circle: paper with an ink icon when on, faint when off.
func _toggle(which: String, icon: Texture2D) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(72, 0)
	var b := Button.new()
	b.name = which
	b.toggle_mode = true
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(TOGGLE, TOGGLE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var off := UiTheme.flat(Color(1, 1, 1, 0.18), UiTokens.RADIUS_PILL, 0)
	var on := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover"]:
		b.add_theme_stylebox_override(state, off)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_constant_override("icon_max_width", 24)
	for state in ["icon_normal_color", "icon_hover_color"]:
		b.add_theme_color_override(state, UiTokens.ON_SCRIM)
	for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	col.add_child(b)
	var l := UiKit.label("", &"ScrimLabel")
	l.add_theme_font_size_override("font_size", 13)
	col.add_child(l)
	b.toggled.connect(_on_toggle.bind(which))
	_toggles[which] = b
	return col


func _on_toggle(on: bool, which: String) -> void:
	_show_toggle(which)
	sound_toggled.emit(which, on)


func _show_toggle(which: String) -> void:
	var b := _toggles[which]
	var l := b.get_parent().get_child(1) as Label
	l.text = (
		"%s %s" % ["Music" if which == "music" else "Sounds", "on" if b.button_pressed else "off"]
	)
	b.tooltip_text = l.text
