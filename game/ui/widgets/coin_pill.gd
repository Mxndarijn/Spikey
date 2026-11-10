class_name CoinPill
extends PanelContainer
## A coin (or another icon) and a number straight on the room, no box: the coin
## balance top right and the run's coins in the HUD. Ink on most rooms, white
## on night rooms (the screen's theme decides). The name stays from the
## sticker kit, where this was a pill.

const COIN_ICON := preload("res://assets/ui/coin.svg")
const ICON_SIZE := 22.0

var _label := Label.new()


func _init(icon: Texture2D = COIN_ICON, word: String = "") -> void:
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
		w.theme_type_variation = &"RoomMuted"
		w.text = word
		row.add_child(w)
	_label.theme_type_variation = &"RoomCoin"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)


## Coins read with thousands separators, as on the canvas ("1,240"); from
## 10,000 on they are short ("12.3k") so a wallet leaves the header room.
func set_amount(value: int) -> void:
	_label.text = UiKit.short_amount(value)


func amount_text() -> String:
	return _label.text.replace(",", "")
