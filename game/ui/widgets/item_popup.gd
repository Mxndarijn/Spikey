class_name ItemPopup
extends Control
## The popup for a tapped item in Customize: dims the room; a paper card with
## the item's name and a bare close X, a clean picture, the detail, a badge
## line and its one action (ItemOffer). Tapping outside or the X closes it.

## The action button was tapped.
signal action_pressed

const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
const COIN_ICON := preload("res://assets/ui/coin.svg")
const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
## The clean picture, as wide as the card's inside.
const PICTURE := Vector2(264, 160)
## The card's side margins.
const SIDE := 28
const ACTION_HEIGHT := float(UiTokens.SIZE_BUTTON_H)

var _name := Label.new()
var _detail := Label.new()
var _badge := Label.new()
var _action := Button.new()
var _picture := ItemThumb.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = UiTokens.SCRIM
	ScrimBleed.attach(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var side := MarginContainer.new()
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("margin_left", SIDE)
	side.add_theme_constant_override("margin_right", SIDE)
	add_child(side)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BigPanel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SPACE_3)
	panel.add_child(box)
	var head := HBoxContainer.new()
	_name.theme_type_variation = &"NameLabel"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_name)
	var close := UiKit.icon_button(CLOSE_ICON, "Close", &"InkButton", UiTokens.SIZE_TAP_MIN)
	# Ink on the paper card, also in night worlds.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		close.add_theme_color_override(state, UiTokens.INK_LINE)
	close.pressed.connect(close_popup)
	head.add_child(close)
	box.add_child(head)
	_picture.custom_minimum_size = Vector2(0, PICTURE.y)
	_picture.outlined = false
	box.add_child(_picture)
	_detail.theme_type_variation = &"InkLabel"
	_detail.add_theme_font_size_override("font_size", 15)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(200, 0)
	box.add_child(_detail)
	_badge.theme_type_variation = &"MutedLabel"
	_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_badge.custom_minimum_size = Vector2(200, 0)
	box.add_child(_badge)
	_action.theme_type_variation = &"ActionButton"
	_action.custom_minimum_size = Vector2(0, ACTION_HEIGHT)
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_constant_override("icon_max_width", 22)
	# A long label trims instead of widening the popup past the screen edge.
	_action.clip_text = true
	_action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_action.pressed.connect(action_pressed.emit)
	box.add_child(_action)


## Shows item `id` of `kind` for `profile`: its name, a clean picture (flyers
## and worlds on a sky with a far hill in `backdrop` or the tapped world, the
## other kinds as their small picture), its words and its action.
func show_item(profile: Profile, kind: String, id: String, backdrop: ThemeDef) -> void:
	_name.text = Catalog.display_name(kind, id)
	_detail.text = ItemText.detail(kind, id)
	_badge.text = ItemText.badge(kind, id)
	_badge.visible = not _badge.text.is_empty()
	_picture.world = backdrop
	_picture.scenic = kind == ItemKind.FLYER or kind == ItemKind.WORLD
	_picture.show_item(kind, id, Catalog.flyer_art(profile.equipped_id(ItemKind.FLYER)))
	_show_action(ItemOffer.label(profile, kind, id), Shop.diamond_price(kind, id) > 0)


func _show_action(label: Array, premium: bool) -> void:
	var text: String = label[0]
	var enabled: bool = label[1]
	_action.text = text
	# "In use" stays tappable: it just closes the popup.
	_action.disabled = not enabled and text != ItemOffer.IN_USE
	var buy := enabled and text.begins_with("Unlock")
	var short := not enabled and text != ItemOffer.IN_USE
	var pay_icon := DIAMOND_ICON if premium else COIN_ICON
	if text == ItemOffer.CONVERT:
		pay_icon = DIAMOND_ICON
		buy = true
	_action.icon = pay_icon if buy else (LOCK_ICON if short else null)
	# The coin keeps its own colours on the ink button (white tints nothing).
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		_action.add_theme_color_override(state, Color.WHITE)


func open_popup() -> void:
	visible = true


func close_popup() -> void:
	visible = false


func is_open() -> bool:
	return visible


## The clean picture, the badge line and the action button, for tests.
func picture() -> ItemThumb:
	return _picture


func badge_text() -> String:
	return _badge.text if _badge.visible else ""


func action_button() -> Button:
	return _action


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_popup()
