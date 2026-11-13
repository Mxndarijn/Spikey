class_name ConvertSheet
extends Control
## Turns diamonds into gold (Checkout.convert), one way: a flat paper card over the dimmed room with
## a minus / plus stepper, what the diamonds become, the Convert button; the close button in the
## card's top right leaves. It opens on the amount asked for (the fewest diamonds that cover a
## shortfall), never more than the player has.

## Diamonds were converted (already in the profile): the opener saves.
signal converted(diamonds: int)
signal closed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const SIDE := 28
const STEP_SIZE := 48.0
const NOTE := "One way. Gold can't be turned back into diamonds."

var _profile: Profile
var _checkout: Checkout
var _amount := 0
var _busy := false
var _count := Label.new()
var _becomes := Label.new()
var _minus: Button
var _plus: Button
var _convert := Button.new()


## `why`: a line under the title ("You need 160 more gold for Ember."), or "".
## `checkout`: where the diamonds are spent.
func _init(checkout: Checkout, suggested: int = 1, why: String = "") -> void:
	_checkout = checkout
	_profile = checkout.profile
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	var title := UiKit.wrapped("Turn diamonds into gold", &"NameLabel", 200)
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(UiKit.card_head(title, closed.emit))
	if not why.is_empty():
		var reason := UiKit.wrapped(why, &"MutedLabel", 200)
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(reason)

	var stepper := HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper.add_theme_constant_override("separation", UiTokens.SPACE_2)
	_minus = _step_button("−", "One diamond less", -1)
	stepper.add_child(_minus)
	stepper.add_child(_icon(DIAMOND_ICON, 30))
	_count.theme_type_variation = &"NameLabel"
	_count.add_theme_font_size_override("font_size", 40)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.custom_minimum_size = Vector2(56, 0)
	stepper.add_child(_count)
	_plus = _step_button("+", "One diamond more", 1)
	stepper.add_child(_plus)
	col.add_child(stepper)

	_becomes.theme_type_variation = &"InkLabel"
	_becomes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_becomes)

	_convert.theme_type_variation = &"ActionButton"
	_convert.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	_convert.focus_mode = Control.FOCUS_NONE
	# The count is in the stepper above: the label never widens the card.
	_convert.clip_text = true
	_convert.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_convert.pressed.connect(confirm)
	col.add_child(_convert)
	col.add_child(UiKit.wrapped(NOTE, &"MutedLabel", 200))
	set_amount(suggested)


## A 48px round minus or plus on the soft edge colour.
func _step_button(text: String, tip: String, delta: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"InkButton"
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(STEP_SIZE, STEP_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
	var disc := UiTheme.flat(UiTokens.PANEL_RAISED, UiTokens.RADIUS_PILL, 0)
	var down := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, disc)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	b.pressed.connect(step.bind(delta))
	return b


static func _icon(tex: Texture2D, side: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func amount() -> int:
	return _amount


## Sets the diamonds to convert, kept between 1 and what the player has
## (0 when they have none).
func set_amount(value: int) -> void:
	var most := _profile.diamonds
	_amount = clampi(value, mini(1, most), most)
	_count.text = str(_amount)
	_becomes.text = "Becomes %s gold" % UiKit.thousands(Economy.gold_for(_amount))
	_minus.disabled = _amount <= 1
	_plus.disabled = _amount >= most
	_convert.disabled = _amount <= 0
	if _amount <= 0:
		_convert.text = "No diamonds yet"
	else:
		_convert.text = "Convert"


func step(delta: int) -> void:
	set_amount(_amount + delta)


func can_convert() -> bool:
	return not _convert.disabled


func convert_text() -> String:
	return _convert.text


func becomes_text() -> String:
	return _becomes.text


## Converts the chosen amount and closes. The wallet may ask the server, so
## the button waits; a refused spend changes nothing.
func confirm() -> void:
	var spent := _amount
	if _busy or spent <= 0:
		return
	_busy = true
	_convert.disabled = true
	var ok: bool = await _checkout.convert(spent)
	_busy = false
	if not ok:
		AudioDirector.ui("locked")
		set_amount(_amount)
		if _amount > 0:
			_convert.text = "Try again"
		return
	AudioDirector.sound("purchase")
	converted.emit(spent)
	closed.emit()
