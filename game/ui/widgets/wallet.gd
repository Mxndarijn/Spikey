class_name Wallet
extends HBoxContainer
## The player's gold and diamonds side by side, straight on the room (two
## CoinPills, no box). Tapping it opens the Shop; a wallet made with
## `tappable` off only shows the amounts (the Shop's own header).

signal pressed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")

var _gold := CoinPill.new()
var _diamonds := CoinPill.new(DIAMOND_ICON)


func _init(tappable: bool = true) -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", UiTokens.SPACE_3)
	custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	mouse_filter = Control.MOUSE_FILTER_STOP if tappable else Control.MOUSE_FILTER_IGNORE
	if tappable:
		tooltip_text = "Shop"
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for pill: CoinPill in [_gold, _diamonds]:
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(pill)


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
