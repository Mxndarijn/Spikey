class_name StoreScreen
extends Control
## The Wallet's first tab, Get diamonds (it was the Shop): where diamonds are
## bought and turned into gold. A back arrow, the title "Wallet" and the
## balance; the Wallet's tabs (Earn free opens EarnScreen); the once-only Starter pack as a wide
## paper card; the Revive Pass as a wide paper card (an ink "Owned" pill once
## bought); the four diamond packs as a 2 x 2 grid of paper cards, each with
## its real price on an ink button; a row that opens the convert sheet; one
## line on the room saying it is all looks only; and "Restore purchases" while
## the pass isn't owned. Everything under the header scrolls (it is taller than
## the smallest phone). Items themselves are bought in Customize
## (CollectionScreen).
## Buying goes through the StoreService; main grants the pack when the store
## confirms, and this screen only shows the result. While the store is closed
## (no app-store billing yet) the packs still show with their prices, but
## their buttons are off and the line under them says why.

signal closed
## The Wallet's Earn free tab was tapped.
signal earn_pressed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const COIN_ICON := preload("res://assets/ui/coin.svg")
const HEART_ICON := preload("res://assets/ui/icons/heart.svg")
const CHECK_ICON := preload("res://assets/ui/icons/check.svg")
const PASS_TAG := "One per run"
const PASS_LINE := "Free revives, no ads"
const PASS_BOUGHT := "Revive Pass unlocked. Every revive is free."
const RESTORED := "Your Revive Pass is back."
const NOTHING_RESTORED := "No earlier purchases to restore."
const SIDE := UiKit.SCREEN_SIDE
const TITLE := "Wallet"
const GRID_GAP := 10
const PRICE_HEIGHT := float(UiTokens.SIZE_TAP_MIN)
const LOOKS_ONLY := "Looks only. Nothing here changes how you play."

## Where diamonds are spent; main sets it before the screen is shown (the
## local wallet when left alone).

var _profile: Profile
var _store: StoreService
var _wallet: Wallet
var _checkout: Checkout
var _starter: Control
var _pass_owned: Control
var _restore: Button
var _scroll: SmoothScroll
var _message: Label
var _sheet: ConvertSheet
var _tabs: PanelContainer
## pack id -> its price button.
var _buttons := {}


func _init(checkout: Checkout, store: StoreService) -> void:
	_checkout = checkout
	_profile = checkout.profile
	_store = store


func _ready() -> void:
	_wallet = Wallet.new(false)
	_message = Label.new()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiKit.SCREEN_TOP)
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_7)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", GRID_GAP)
	margin.add_child(col)
	col.add_child(UiKit.header(TITLE, closed.emit, _wallet))
	_tabs = UiKit.wallet_tabs(0, func(_i: int) -> void: earn_pressed.emit())
	col.add_child(_tabs)
	_scroll = SmoothScroll.new()
	_scroll.blocked = func() -> bool: return _sheet != null
	col.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", GRID_GAP)
	_scroll.add_child(body)
	col = body

	_starter = _starter_card()
	col.add_child(_starter)
	col.add_child(_pass_card())
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
	# A closed store shows its packs, but they can't be bought yet.
	_message.text = LOOKS_ONLY if _store.is_open() else StoreService.CLOSED
	col.add_child(_message)
	col.add_child(_restore_link())

	_store.purchased.connect(_on_purchased)
	_store.failed.connect(_on_failed)
	_store.restored.connect(_on_restored)
	refresh()


func _exit_tree() -> void:
	if _store.purchased.is_connected(_on_purchased):
		_store.purchased.disconnect(_on_purchased)
	if _store.failed.is_connected(_on_failed):
		_store.failed.disconnect(_on_failed)
	if _store.restored.is_connected(_on_restored):
		_store.restored.disconnect(_on_restored)


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


## The Revive Pass, laid out like the Starter pack: "Revive Pass · One per
## run" over a heart and what it does, the price (or the ink "Owned" pill) at
## the right.
func _pass_card() -> Control:
	var pack := DiamondPacks.find(DiamondPacks.REVIVE_PASS)
	var card := PanelContainer.new()
	card.name = "RevivePass"
	card.theme_type_variation = &"Card"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	text.add_child(UiKit.label("%s · %s" % [pack.name, PASS_TAG], &"MutedLabel", false))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	var heart := _icon(HEART_ICON, 20)
	heart.modulate = UiTokens.ON_PANEL
	line.add_child(heart)
	var what := UiKit.label(PASS_LINE, &"SmallNameLabel", false)
	what.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BODY)
	line.add_child(what)
	text.add_child(line)
	row.add_child(text)
	var buy := _price_button(DiamondPacks.REVIVE_PASS)
	buy.custom_minimum_size.x = 96
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buy)
	_pass_owned = _owned_pill()
	row.add_child(_pass_owned)
	return card


## The ink "Owned" pill with a check, as on an owned item card.
func _owned_pill() -> Control:
	var pill := PanelContainer.new()
	pill.name = "Owned"
	pill.theme_type_variation = &"UsePill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var check := _icon(CHECK_ICON, 12)
	check.modulate = UiTokens.ON_PRIMARY
	row.add_child(check)
	var l := Label.new()
	l.theme_type_variation = &"OnInkLabel"
	l.text = "Owned"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	pill.add_child(row)
	return pill


## "Restore purchases" in bare ink on the room: asks the store for a Revive
## Pass bought before (another phone, a reinstall).
func _restore_link() -> Button:
	_restore = Button.new()
	_restore.name = "Restore"
	_restore.theme_type_variation = &"PlainButton"
	_restore.text = "Restore purchases"
	_restore.tooltip_text = "Get back a Revive Pass bought before"
	_restore.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restore.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	_restore.focus_mode = Control.FOCUS_NONE
	_restore.pressed.connect(restore)
	return _restore


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


## "Turn diamonds into gold": a row with a chevron. Opens the sheet.
func _convert_row() -> Control:
	var b := UiKit.row_button("Turn diamonds into gold")
	b.name = "Convert"
	b.tooltip_text = "1 diamond becomes %d gold" % Economy.GOLD_PER_DIAMOND
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


## Shows the balance, hides the Starter pack once it is bought and shows the
## Revive Pass as owned once it is (also after a restore or a sync).
func refresh() -> void:
	_wallet.show_balance(_profile)
	_starter.visible = DiamondPacks.can_buy(_profile, DiamondPacks.STARTER)
	for id: String in _buttons:
		(_buttons[id] as Button).disabled = not _store.is_open()
	var owned := DiamondPacks.has_revive_pass(_profile)
	(_buttons[DiamondPacks.REVIVE_PASS] as Button).visible = not owned
	_pass_owned.visible = owned
	_restore.visible = _store.is_open() and not owned


## Asks the store for a pack; the result comes back as a signal.
func buy(id: String) -> void:
	if not DiamondPacks.can_buy(_profile, id):
		AudioDirector.ui("locked")
		return
	if not _store.is_open():
		AudioDirector.ui("locked")
		_message.text = StoreService.CLOSED
		return
	_store.buy(id)


## Asks the store for purchases made before; the answer comes back as a
## signal (main hands out what came back, then this says how it went).
func restore() -> void:
	_store.restore()


func _on_purchased(id: String) -> void:
	var pack := DiamondPacks.find(id)
	if id == DiamondPacks.REVIVE_PASS:
		_message.text = PASS_BOUGHT
	elif not pack.is_empty():
		_message.text = "Added %d diamonds." % int(pack.diamonds)
	refresh()


## Main connected first, so what came back is already handed out.
func _on_restored(pack_ids: Array[String]) -> void:
	_message.text = RESTORED if DiamondPacks.REVIVE_PASS in pack_ids else NOTHING_RESTORED
	refresh()


func _on_failed(_id: String, reason: String) -> void:
	AudioDirector.ui("locked")
	_message.text = reason


## The convert sheet over the Shop, on one diamond.
func open_convert() -> ConvertSheet:
	if _sheet == null:
		_sheet = ConvertSheet.new(_checkout, 1, "")
		_sheet.converted.connect(_on_converted)
		_sheet.closed.connect(_close_sheet)
		add_child(_sheet)
	return _sheet


func _on_converted(_diamonds: int) -> void:
	refresh()


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


## The pass card shows the "Owned" pill instead of its price.
func pass_owned_visible() -> bool:
	return _pass_owned.visible


func restore_button() -> Button:
	return _restore


## The price button of a pack, for tests.
func price_button(id: String) -> Button:
	return _buttons.get(id) as Button


## The Wallet tab that opens Earn free.
func earn_tab() -> Button:
	return _tabs.get_child(0).get_child(1) as Button
