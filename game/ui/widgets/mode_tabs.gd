class_name ModeTabs
extends Control
## Home's mode picker (docs/DUEL_MODE.md, "The mode picker"): one paper tab bar
## with a tab per game mode (Classic | Daily | Battle | Duel), the chosen one
## filled ink, and under it the chosen mode's rules in one line. A tab can wear
## a gold badge: the Daily Run's tries left, the battles waiting for your turn,
## UPDATE when the app is too old for that mode. Play (the dock) follows the
## chosen tab; a tap on a tab only chooses it.

## The chosen mode changed (a tap on another tab).
signal selected(id: String)

const BAR_H := float(UiTokens.SIZE_TAP_MIN) + 6.0
## The rules line under the bar.
const LINE_TOP := BAR_H + UiTokens.SPACE_2
const LINE_H := 18.0
const HEIGHT := LINE_TOP + LINE_H
## How far a badge sits above the bar's top edge and in from a tab's right.
const BADGE_LIFT := 12.0
const BADGE_INSET := 2.0

var _ids: Array[String] = []
var _tabs: Array[Button] = []
var _badges: Array[Label] = []
var _rules: Array[String] = []
var _index := 0
var _bar: PanelContainer
var _line: Label


func _init(chosen: String = GameModes.CLASSIC) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	_bar = PanelContainer.new()
	_bar.name = "Bar"
	_bar.theme_type_variation = &"TabStrip"
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = BAR_H
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_bar.add_child(row)
	var group := ButtonGroup.new()
	for m in GameModes.all():
		_ids.append(m.id)
		_rules.append(m.rule)
		var tab := Button.new()
		tab.name = m.id
		tab.text = m.tab_title
		tab.tooltip_text = m.title
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.clip_text = true
		tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tab.pressed.connect(choose.bind(_tabs.size()))
		row.add_child(tab)
		_tabs.append(tab)
		_badges.append(_badge(tab))
	_line = UiKit.label("", &"SkyCaption")
	_line.name = "Rule"
	_line.clip_text = true
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_line.offset_top = LINE_TOP
	_line.offset_bottom = LINE_TOP + LINE_H
	add_child(_line)
	_index = maxi(_ids.find(chosen), 0)
	_show()


## A gold tag on the tab's top right corner, over the bar's edge.
func _badge(tab: Button) -> Label:
	var badge := UiKit.label("", &"OnInkLabel")
	badge.name = "Badge"
	badge.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	badge.add_theme_color_override("font_color", UiTokens.ON_ACTION)
	var gold := UiTheme.flat(UiTokens.ACTION, UiTokens.RADIUS_PILL, 0)
	gold.content_margin_left = 6
	gold.content_margin_right = 6
	gold.content_margin_top = 1
	gold.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", gold)
	badge.add_theme_constant_override("line_spacing", 0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	tab.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_left -= BADGE_INSET
	badge.offset_right -= BADGE_INSET
	badge.offset_top = -BADGE_LIFT
	badge.offset_bottom = -BADGE_LIFT + badge.get_combined_minimum_size().y
	return badge


func _show() -> void:
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == _index)
	_line.text = _rules[_index]


## Chooses the mode at index i (kept in range); emits `selected` when it changed.
func choose(i: int) -> void:
	var to := clampi(i, 0, _ids.size() - 1)
	if to == _index:
		_show()
		return
	_index = to
	AudioDirector.ui("tap")
	_show()
	selected.emit(chosen())


## Chooses a mode by id without a sound (a test, a link from elsewhere).
func choose_id(id: String) -> void:
	var i := _ids.find(id)
	if i < 0 or i == _index:
		return
	_index = i
	_show()
	selected.emit(chosen())


func chosen() -> String:
	return _ids[_index]


func tab(id: String) -> Button:
	var i := _ids.find(id)
	return _tabs[i] if i >= 0 else null


func tab_ids() -> Array[String]:
	return _ids.duplicate()


## The rules line a mode shows under the bar while chosen.
func rule_text(id: String) -> String:
	var i := _ids.find(id)
	return _rules[i] if i >= 0 else ""


## The line under the bar now (the chosen mode's).
func line_text() -> String:
	return _line.text


func badge_text(id: String) -> String:
	var i := _ids.find(id)
	return _badges[i].text if i >= 0 and _badges[i].visible else ""


## Sets a mode's rules line and badge ("" hides the badge).
func set_line(id: String, rule: String, badge: String) -> void:
	var i := _ids.find(id)
	if i < 0:
		return
	_rules[i] = rule
	var b := _badges[i]
	b.text = badge
	b.visible = not badge.is_empty()
	b.offset_left = b.offset_right - b.get_combined_minimum_size().x
	if i == _index:
		_line.text = rule
