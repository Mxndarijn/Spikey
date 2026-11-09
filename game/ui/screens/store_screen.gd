class_name StoreScreen
extends Control
## The Shop (minimal kit): where diamonds are bought and turned into gold.
## A back arrow, the title and the wallet; the once-only Starter pack as a wide
## paper card; the four diamond packs as a 2 x 2 grid of paper cards, each with
## its real price on an ink button; a row that opens the convert sheet; and one
## line on the room saying it is all looks only. Items themselves are bought in
## Customize (CollectionScreen).
## Buying goes through the StoreService; main grants the pack when the store
## confirms, and this screen only shows the result.

signal closed
## The wallet changed here (a conversion): main saves.
signal changed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const COIN_ICON := preload("res://assets/ui/coin.svg")
const SIDE := 14
const GRID_GAP := 10
const PRICE_HEIGHT := float(UiTokens.SIZE_TAP_MIN)
const LOOKS_ONLY := "Looks only. Nothing here changes how you play."

## Where diamonds are spent; main sets it before the screen is shown (the
## local wallet when left alone).
var wallet_service: WalletService

var _profile: Profile
var _store: StoreService
var _wallet := Wallet.new(false)
var _starter: Control
var _message := Label.new()
var _sheet: ConvertSheet
## pack id -> its price button.
var _buttons := {}


func _init(profile: Profile, store: StoreService) -> void:
	_profile = profile
	_store = store


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_7)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", GRID_GAP)
	margin.add_child(col)
	col.add_child(UiKit.header("Shop", closed.emit, _wallet))

	_starter = _starter_card()
	col.add_child(_starter)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	for id in DiamondPacks.ids():
		if id != DiamondPacks.STARTER:
			grid.add_child(_pack_card(id))
	col.add_child(grid)
	col.add_child(_convert_row())

	_message.theme_type_variation = &"SkyCaption"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(200, 0)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.text = LOOKS_ONLY
	col.add_child(_message)

	_store.purchased.connect(_on_purchased)
	_store.failed.connect(_on_failed)
	refresh()


## Free the widgets made in the member list if the screen never got ready.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for n: Node in [_wallet, _message]:
		if is_instance_valid(n) and n.get_parent() == null:
			n.free()


func _exit_tree() -> void:
	if _store.purchased.is_connected(_on_purchased):
		_store.purchased.disconnect(_on_purchased)
	if _store.failed.is_connected(_on_failed):
		_store.failed.disconnect(_on_failed)


## The Starter pack: its tag, name and contents at the left, the price right.
func _starter_card() -> Control:
	var pack := DiamondPacks.find(DiamondPacks.STARTER)
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	text.add_child(UiKit.label("%s · %s" % [pack.name, pack.note], &"MutedLabel", false))
	var amounts := HBoxContainer.new()
	amounts.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	amounts.add_child(_icon(DIAMOND_ICON, 20))
	amounts.add_child(_amount_label(int(pack.diamonds), 20))
	amounts.add_child(UiKit.label("and", &"MutedLabel", false))
	amounts.add_child(_icon(COIN_ICON, 20))
	amounts.add_child(_amount_label(int(pack.gold), 20))
	text.add_child(amounts)
	row.add_child(text)
	var buy := _price_button(DiamondPacks.STARTER)
	buy.custom_minimum_size.x = 96
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buy)
	return card


## One diamond pack: its name (and extra), the diamonds, the price button.
func _pack_card(id: String) -> Control:
	var pack := DiamondPacks.find(id)
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	card.add_child(box)
	var note := str(pack.note)
	var title := str(pack.name) if note.is_empty() else "%s · %s" % [pack.name, note]
	box.add_child(UiKit.label(title, &"MutedLabel", false))
	var amount := HBoxContainer.new()
	amount.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	amount.add_child(_icon(DIAMOND_ICON, 24))
	amount.add_child(_amount_label(int(pack.diamonds), 26))
	box.add_child(amount)
	box.add_child(_price_button(id))
	return card


func _price_button(id: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ActionButton"
	b.text = _store.price_text(id)
	b.tooltip_text = "Buy %s" % DiamondPacks.find(id).name
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, PRICE_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(buy.bind(id))
	_buttons[id] = b
	return b


## "Turn diamonds into gold", with the rate at the right. Opens the sheet.
func _convert_row() -> Control:
	var b := Button.new()
	b.theme_type_variation = &"CardButton"
	b.name = "Convert"
	b.text = "Turn diamonds into gold"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = "1 diamond becomes %d gold" % Economy.GOLD_PER_DIAMOND
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	b.focus_mode = Control.FOCUS_NONE
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	box.content_margin_left = UiTokens.SPACE_5
	box.content_margin_right = UiTokens.SPACE_5
	var down := box.duplicate() as StyleBoxFlat
	down.bg_color = UiTheme.SELECTED_FILL
	for state in ["normal", "hover"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	b.add_theme_font_override("font", GameFonts.ui(800))
	b.add_theme_font_size_override("font_size", 15)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	b.pressed.connect(open_convert)
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


static func _amount_label(value: int, font_size: int) -> Label:
	var l := UiKit.label(UiKit.thousands(value), &"NameLabel", false)
	l.add_theme_font_size_override("font_size", font_size)
	return l


## Shows the balance and hides the Starter pack once it is bought.
func refresh() -> void:
	_wallet.show_balance(_profile)
	_starter.visible = DiamondPacks.can_buy(_profile, DiamondPacks.STARTER)


## Asks the store for a pack; the result comes back as a signal.
func buy(id: String) -> void:
	if not DiamondPacks.can_buy(_profile, id):
		AudioDirector.ui("locked")
		return
	_store.buy(id)


func _on_purchased(id: String) -> void:
	var pack := DiamondPacks.find(id)
	if not pack.is_empty():
		_message.text = "Added %d diamonds." % int(pack.diamonds)
	refresh()


func _on_failed(_id: String, reason: String) -> void:
	AudioDirector.ui("locked")
	_message.text = reason


## The convert sheet over the Shop, on one diamond.
func open_convert() -> ConvertSheet:
	if _sheet == null:
		_sheet = ConvertSheet.new(_profile, 1, "", wallet_service)
		_sheet.converted.connect(_on_converted)
		_sheet.closed.connect(_close_sheet)
		add_child(_sheet)
	return _sheet


func _on_converted(_diamonds: int) -> void:
	refresh()
	changed.emit()


func _close_sheet() -> void:
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null


func sheet() -> ConvertSheet:
	return _sheet


func wallet() -> Wallet:
	return _wallet


func message_text() -> String:
	return _message.text


func starter_visible() -> bool:
	return _starter.visible


## The price button of a pack, for tests.
func price_button(id: String) -> Button:
	return _buttons.get(id) as Button
