class_name CoinPill
extends PanelContainer
## A number in a white sticker pill with an icon in front: the coin balance (design kit:
## CoinPill), or with a word too, like the best score on the home screen.

const COIN_ICON := preload("res://assets/ui/coin.svg")
const ICON_SIZE := 24.0

var _label := Label.new()


func _init(icon: Texture2D = COIN_ICON, word: String = "") -> void:
	theme_type_variation = &"PillPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	add_child(row)
	var pic := TextureRect.new()
	pic.texture = icon
	pic.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pic)
	if not word.is_empty():
		var w := Label.new()
		w.theme_type_variation = &"StatusLabel"
		w.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_LABEL)
		w.text = word
		row.add_child(w)
	_label.theme_type_variation = &"CoinLabel"
	row.add_child(_label)


func set_amount(value: int) -> void:
	_label.text = str(value)


func amount_text() -> String:
	return _label.text
