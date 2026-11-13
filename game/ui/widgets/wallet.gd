class_name Wallet
extends HBoxContainer
## The player's gold and diamonds side by side (two CoinPills). Tappable, it is
## a button on a paper pill (the same paper as Home's Settings disc) and opens
## the Wallet (Get diamonds); a wallet made with `tappable` off only shows the
## amounts straight on the room, no box (the Wallet's own header).

signal pressed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
## The paper pill's inner padding at each end (the box separation counts too).
const PAD_LEFT := 14.0
const PAD_RIGHT := 18.0

var _gold := CoinPill.new()
var _diamonds := CoinPill.new(DIAMOND_ICON)
## A tappable wallet draws its paper pill.
var _paper := false


func _init(tappable: bool = true) -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", UiTokens.SPACE_3)
	custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	mouse_filter = Control.MOUSE_FILTER_STOP if tappable else Control.MOUSE_FILTER_IGNORE
	if tappable:
		tooltip_text = "Wallet"
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tappable:
		add_child(_pad(PAD_LEFT))
	for pill: CoinPill in [_gold, _diamonds]:
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if tappable:
			pill.on_paper()
		add_child(pill)
	if tappable:
		add_child(_pad(PAD_RIGHT))
	_paper = tappable


func _draw() -> void:
	if _paper:
		var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
		draw_style_box(box, Rect2(Vector2.ZERO, size))


static func _pad(width: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(width - UiTokens.SPACE_3, 0)
	return c


func show_balance(profile: Profile) -> void:
	_gold.set_amount(profile.coins)
	_diamonds.set_amount(profile.diamonds)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


## The amounts without separators, for tests.
func gold_text() -> String:
	return _gold.amount_text()


func diamonds_text() -> String:
	return _diamonds.amount_text()
