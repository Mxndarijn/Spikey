class_name ReviveOffer
extends ColorRect
## The revive offer after a crash, on the dimmed room (laid out like Paused):
## "Crashed", the score, one pip per free revive of the day, what Revive costs
## (a free one, or a short ad), the round Revive on the action line and the
## text button End run under it (the same button as on Paused). With the Revive Pass there are no pips: the line says the pass makes
## it free and a small "PASS" pill sits where the "AD" one would. It waits: no
## countdown. Hud owns it.

signal revive_pressed
signal skip_pressed
## show_offer() put it on screen.
signal shown

const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
const AD_ICON := preload("res://assets/ui/icons/ad.svg")
const PIP := 10.0
const PIP_OFF := Color(1, 1, 1, 0.3)
const REVIVE_TOP := UiKit.ACTION_TOP
const FREE_NOTE := "Keep your score and fly on"
const AD_LINE := "Watch a short ad to keep going"
const PASS_LINE := "Revive free with your Revive Pass"

var _score := Label.new()
var _pips := HBoxContainer.new()
var _line := Label.new()
var _note := Label.new()
var _revive: Button
var _ad_tag := PanelContainer.new()
var _pass_tag := PanelContainer.new()
var _skip: Button


func _init() -> void:
	color = UiTokens.SCRIM
	ScrimBleed.attach(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_at(UiKit.label("Crashed", &"ScrimTitle"), 88)
	_score.theme_type_variation = &"ScrimScore"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_score, 146)
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.add_theme_constant_override("separation", 8)
	for i in DailyRevives.PER_DAY:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(PIP, PIP)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pips.add_child(pip)
	_at(_pips, 250)
	_line.theme_type_variation = &"ScrimLabel"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.text = AD_LINE
	_at(_line, 272)
	_note.theme_type_variation = &"ScrimCaption"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.text = FREE_NOTE
	_at(_note, 296)
	_build_revive()
	_build_skip()


func _build_revive() -> void:
	_revive = UiKit.primary(HEART_ICON, "Revive", true)
	_revive.name = "Revive"
	_revive.anchor_left = 0.5
	_revive.anchor_right = 0.5
	_revive.offset_left = -UiKit.PRIMARY / 2.0
	_revive.offset_right = UiKit.PRIMARY / 2.0
	_revive.offset_top = REVIVE_TOP
	_revive.offset_bottom = REVIVE_TOP + UiKit.PRIMARY
	_revive.pressed.connect(revive_pressed.emit)
	add_child(_revive)
	# A small ink "AD" pill on the button's shoulder, so nobody is surprised;
	# "PASS" there when the Revive Pass pays.
	_shoulder_pill(_ad_tag, "AD", 24)
	_shoulder_pill(_pass_tag, "PASS", 34)
	_pass_tag.visible = false


func _shoulder_pill(tag_box: PanelContainer, text: String, inset: float) -> void:
	var pill := UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, 0)
	pill.content_margin_left = 8
	pill.content_margin_right = 8
	tag_box.add_theme_stylebox_override("panel", pill)
	tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := UiKit.label(text, &"OnInkLabel")
	tag.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	tag.custom_minimum_size = Vector2(0, 20)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_box.add_child(tag)
	tag_box.anchor_left = 0.5
	tag_box.anchor_right = 0.5
	tag_box.offset_left = UiKit.PRIMARY / 2.0 - inset
	tag_box.offset_top = REVIVE_TOP + 2
	add_child(tag_box)


func _build_skip() -> void:
	_skip = UiKit.text_button(PauseScreen.END_RUN)
	_skip.name = "Skip"
	_skip.pressed.connect(skip_pressed.emit)
	UiKit.place_text_button(self, _skip)


func _at(c: Control, top: float) -> void:
	add_child(c)
	c.anchor_right = 1.0
	c.offset_top = top
	c.offset_bottom = top + c.get_combined_minimum_size().y


## Shows the offer for a run that crashed on `score`. With `free_left` > 0 the
## revive is free; otherwise it costs an ad. With `has_pass` it is always free
## and the day's count doesn't show.
func show_offer(score: int, free_left: int, has_pass: bool = false) -> void:
	_score.text = str(score)
	_pips.visible = not has_pass
	_pass_tag.visible = has_pass
	if has_pass:
		_line.text = PASS_LINE
		_note.text = FREE_NOTE
		_revive.icon = HEART_ICON
		_ad_tag.visible = false
		visible = true
		shown.emit()
		return
	var total := DailyRevives.PER_DAY
	for i in _pips.get_child_count():
		var on := i < free_left
		var box := UiTheme.flat(UiTokens.ON_SCRIM if on else PIP_OFF, UiTokens.RADIUS_PILL, 0)
		(_pips.get_child(i) as Panel).add_theme_stylebox_override("panel", box)
	var free := free_left > 0
	_line.text = free_line(free_left) if free else AD_LINE
	_note.text = FREE_NOTE if free else "%d free revives are back tomorrow" % total
	_revive.icon = HEART_ICON if free else AD_ICON
	_ad_tag.visible = not free
	visible = true
	shown.emit()


## "2 free revives left today".
static func free_line(free_left: int) -> String:
	return "%d free revive%s left today" % [free_left, "" if free_left == 1 else "s"]


func is_free() -> bool:
	return not _ad_tag.visible


## The "PASS" pill shows: the Revive Pass pays for this revive.
func shows_pass() -> bool:
	return _pass_tag.visible


func pips_visible() -> bool:
	return _pips.visible


func line_text() -> String:
	return _line.text


func note_text() -> String:
	return _note.text


func score_text() -> String:
	return _score.text


func revive_button() -> Button:
	return _revive


func skip_button() -> Button:
	return _skip
