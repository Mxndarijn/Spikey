class_name ModeCarousel
extends Control
## Home's mode carousel (docs/DUEL_MODE.md, "The mode picker"): one paper card
## per game mode, the chosen one in the middle and its neighbours peeking in at
## the screen's sides, page dots under it. A swipe moves one mode along, a tap on
## a side card chooses it, a tap on the middle card starts it.

## The chosen mode changed (a swipe or a tap on a side card).
signal selected(id: String)
## The middle card was tapped: start that mode.
signal activated(id: String)

const CARD_W := 232.0
const CARD_H := 72.0
const GAP := 12.0
const STEP := CARD_W + GAP
const ICON := 30.0
## A press that moves this far sideways is a swipe, not a tap.
const SWIPE := 36.0
const DOT := 6.0
const DOT_ON := 18.0
const DOT_GAP := 6.0
const DOTS_TOP := CARD_H + 8.0
const HEIGHT := DOTS_TOP + DOT + 2.0
const SLIDE_TIME := 0.18

var _ids: Array[String] = []
var _cards: Array[PanelContainer] = []
var _rules: Array[Label] = []
var _badges: Array[Label] = []
var _index := 0
var _press_at := Vector2.ZERO
var _pressing := false
var _tween: Tween


func _init(chosen: String = GameModes.CLASSIC) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	custom_minimum_size = Vector2(0, HEIGHT)
	for m in GameModes.all():
		_ids.append(m.id)
		_add_card(m)
	_index = maxi(_ids.find(chosen), 0)
	_layout(false)


func _add_card(m: GameModes.Mode) -> void:
	var card := PanelContainer.new()
	card.name = m.id
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, 0)
	paper.content_margin_left = UiTokens.SPACE_4
	paper.content_margin_right = UiTokens.SPACE_4
	paper.content_margin_top = UiTokens.SPACE_3
	paper.content_margin_bottom = UiTokens.SPACE_3
	card.add_theme_stylebox_override("panel", paper)
	card.size = Vector2(CARD_W, CARD_H)
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = m.icon
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = UiTokens.ON_PANEL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var title := UiKit.label(m.title, &"NameLabel", false)
	title.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_HEADING)
	col.add_child(title)
	var rule := UiKit.label(m.rule, &"MutedLabel", false)
	rule.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	rule.clip_text = true
	rule.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(rule)
	var badge := UiKit.label("", &"OnInkLabel")
	badge.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	var ink := UiTheme.flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0)
	ink.content_margin_left = UiTokens.SPACE_2
	ink.content_margin_right = UiTokens.SPACE_2
	ink.content_margin_top = 2
	ink.content_margin_bottom = 2
	badge.add_theme_stylebox_override("normal", ink)
	badge.add_theme_color_override("font_color", UiTokens.ON_PRIMARY)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.visible = false
	row.add_child(badge)
	add_child(card)
	_cards.append(card)
	_rules.append(rule)
	_badges.append(badge)


func _layout(animated: bool) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	var left := (float(UiTokens.SIZE_VIEWPORT_W) - CARD_W) / 2.0
	var slide := animated and is_inside_tree()
	if slide:
		_tween = create_tween().set_parallel(true)
	for i in _cards.size():
		var to := Vector2(left + (i - _index) * STEP, 0.0)
		var fade := 1.0 if i == _index else 0.8
		if slide:
			_tween.tween_property(_cards[i], "position", to, SLIDE_TIME)
			_tween.tween_property(_cards[i], "modulate:a", fade, SLIDE_TIME)
		else:
			_cards[i].position = to
			_cards[i].modulate.a = fade
	queue_redraw()


func _draw() -> void:
	var n := _ids.size()
	var width := (n - 1) * (DOT + DOT_GAP) + DOT_ON
	var x := (float(UiTokens.SIZE_VIEWPORT_W) - width) / 2.0
	for i in n:
		var w := DOT_ON if i == _index else DOT
		var color := UiTokens.PRIMARY if i == _index else UiTokens.SCORE_GHOST
		draw_rect(Rect2(x, DOTS_TOP, w, DOT), color)
		x += w + DOT_GAP


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	var at := Vector2.ZERO
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == 1:
		pressed = (event as InputEventMouseButton).pressed
		released = not pressed
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		released = not pressed
		at = (event as InputEventScreenTouch).position
	else:
		return
	if pressed:
		_pressing = true
		_press_at = at
	elif released and _pressing:
		_pressing = false
		var dx := at.x - _press_at.x
		if absf(dx) >= SWIPE:
			swipe(dx)
		else:
			tap_at(at.x)
	accept_event()


## A sideways swipe: to the left shows the next mode, to the right the one before.
func swipe(dx: float) -> void:
	choose(_index + (1 if dx < 0.0 else -1))


## A tap at x (in the carousel): the middle card starts its mode, a side card is
## chosen.
func tap_at(x: float) -> void:
	var left := (float(UiTokens.SIZE_VIEWPORT_W) - CARD_W) / 2.0
	if x >= left and x <= left + CARD_W:
		AudioDirector.ui("tap")
		activated.emit(chosen())
	elif x < left:
		choose(_index - 1)
	else:
		choose(_index + 1)


## Chooses the mode at index i (kept in range); emits `selected` when it changed.
func choose(i: int) -> void:
	var to := clampi(i, 0, _ids.size() - 1)
	if to == _index:
		return
	_index = to
	AudioDirector.ui("tap")
	_layout(true)
	selected.emit(chosen())


## Chooses a mode by id without a sound or a slide (the All modes sheet).
func choose_id(id: String) -> void:
	var i := _ids.find(id)
	if i < 0 or i == _index:
		return
	_index = i
	_layout(false)
	selected.emit(chosen())


func chosen() -> String:
	return _ids[_index]


func card(id: String) -> PanelContainer:
	var i := _ids.find(id)
	return _cards[i] if i >= 0 else null


func rule_text(id: String) -> String:
	var i := _ids.find(id)
	return _rules[i].text if i >= 0 else ""


func badge_text(id: String) -> String:
	var i := _ids.find(id)
	return _badges[i].text if i >= 0 and _badges[i].visible else ""


## Sets a card's line and badge ("" hides the badge).
func set_line(id: String, rule: String, badge: String) -> void:
	var i := _ids.find(id)
	if i < 0:
		return
	_rules[i].text = rule
	_badges[i].text = badge
	_badges[i].visible = not badge.is_empty()
