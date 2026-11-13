class_name CollectionScreen
extends Control
## One kind's list in Customize (minimal kit): the shop and the player's own
## items of that kind in one screen, over the live room. It opens from a card on
## LookScreen ("Your look"), and Back returns there. A back arrow, the kind's
## name as the title and the coins; the LookPreview (the look in use with the
## tapped item swapped in); and the items as flat paper tiles, yours first, then
## the shop's. Tapping an item opens its ItemPopup with its one action (Use,
## Get for free, Unlock for N, Need N more; see ItemOffer). Buying goes through
## Checkout. Music items are playlist rows whose play button previews the track
## (MusicPreview); the track that was playing comes back when the preview stops
## or the screen closes (equipping hands over to main, which plays the new pick).

signal closed
## Something was bought or put to use in the shop.
signal equipped(kind: String, id: String)
## A world was tapped: the room behind the menu shows it until the screen closes.
signal previewed(kind: String, id: String)
## The wallet in the header was tapped: main opens Earn diamonds.
signal earn_pressed

## Only the shop is left (the first-start pickers were removed).
enum Mode { SHOP }

## The screen's title per kind.
const TITLES := {
	ItemKind.FLYER: "Flyers",
	ItemKind.WORLD: "Worlds",
	ItemKind.TRAIL: "Trails",
	ItemKind.PORTAL: "Portals",
	ItemKind.MUSIC: "Music",
	ItemKind.CRASH: "Crashes",
	ItemKind.PLATE: "Plates",
	ItemOffer.HATS: "Hats",
}
const SHOP_COLUMNS := 3
const GRID_GAP := 10
const SIDE := UiKit.SCREEN_SIDE

var mode: Mode
var kind: String
## Plays music previews; null in tests (only the state changes then).
var audio: AudioDirector

var _profile: Profile
## Buying and converting (the wallet may ask the server).
var _checkout: Checkout
var _selected := ""
var _cards: Array[ItemCard] = []
var _wallet: Wallet
## The header row; its "Title" label names the kind shown.
var _header: Control
var _look: LookPreview
## Every item of the kind, yours first.
var _owned_grid: GridContainer
var _empty: PanelContainer
var _empty_text: Label
var _popup: ItemPopup
## The convert sheet, while it is open.
var _sheet: ConvertSheet
## A premium purchase is waiting for the wallet's answer.
var _paying := false
var _music: MusicPreview


func _init(checkout: Checkout, p_mode: Mode, tab: String = ItemKind.FLYER) -> void:
	_checkout = checkout
	_profile = checkout.profile
	mode = p_mode
	kind = tab


func _ready() -> void:
	_music = MusicPreview.new(audio)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiKit.SCREEN_TOP)
	# Keeps the grid above the floor spikes.
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_7)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	margin.add_child(col)
	_wallet = Wallet.new()
	_wallet.pressed.connect(earn_pressed.emit)
	_header = UiKit.header(title_for(kind), closed.emit, _wallet)
	col.add_child(_header)
	_look = LookPreview.new()
	col.add_child(_look)
	col.add_child(_build_grid())
	_popup = ItemPopup.new()
	_popup.action_pressed.connect(_on_action)
	add_child(_popup)
	_show_kind(kind)


## The items as tiles (one column of rows for music) in a soft scroll.
func _build_grid() -> Control:
	var scroll := SmoothScroll.new()
	scroll.blocked = is_popup_open
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", int(FadeMask.FADE))
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_grid = GridContainer.new()
	_owned_grid.columns = SHOP_COLUMNS
	_owned_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_owned_grid.add_theme_constant_override("v_separation", GRID_GAP)
	stack.add_child(_owned_grid)
	_empty = PanelContainer.new()
	_empty.theme_type_variation = &"Card"
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_text = Label.new()
	_empty_text.theme_type_variation = &"MutedLabel"
	_empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_text.custom_minimum_size = Vector2(240, 0)
	_empty_text.text = "Hats are coming. Every flyer will wear them on the same hitbox."
	_empty.add_child(_empty_text)
	stack.add_child(_empty)
	pad.add_child(stack)
	scroll.add_child(pad)
	return FadeMask.new(scroll)


## Customize: tapping an item previews it and opens its popup.
func open_popup() -> void:
	if not _selected.is_empty():
		_popup.open_popup()


func close_popup() -> void:
	_popup.close_popup()


func is_popup_open() -> bool:
	return _popup != null and _popup.is_open()


func popup() -> ItemPopup:
	return _popup


func _tap(id: String) -> void:
	_select(id)
	open_popup()


## Ids this screen offers for the current kind: yours first, then the ones in
## the shop.
func item_ids() -> Array[String]:
	var owned: Array[String] = []
	var rest: Array[String] = []
	for id in Catalog.ids(kind):
		if _profile.owns(kind, id):
			owned.append(id)
		else:
			rest.append(id)
	return owned + rest


func selected_id() -> String:
	return _selected


## Moves the selection by one (wraps around); for keys and controllers.
func step(delta: int) -> void:
	var ids := item_ids()
	if ids.is_empty():
		return
	var i := maxi(ids.find(_selected), 0)
	_select(ids[posmod(i + delta, ids.size())])


func _show_kind(k: String) -> void:
	stop_preview()
	kind = k
	_owned_grid.columns = 1 if k == ItemKind.MUSIC else SHOP_COLUMNS
	(_header.get_node("Title") as Label).text = title_for(k)
	for c in _cards:
		_owned_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	var backdrop := _backdrop()
	var ids := item_ids()
	for id in ids:
		var card := ItemCard.new(kind, id, backdrop)
		card.pressed.connect(_tap.bind(id))
		card.preview_pressed.connect(toggle_preview)
		_owned_grid.add_child(card)
		_cards.append(card)
	close_popup()
	_empty.visible = ids.is_empty()
	var current := _profile.equipped_id(kind)
	_select(current if current in ids else (ids[0] if not ids.is_empty() else ""))


## "Crashes" for ItemKind.CRASH: the title of a kind's list.
static func title_for(k: String) -> String:
	return str(TITLES.get(k, "Customize"))


## The title in the header, for tests.
func title_text() -> String:
	return (_header.get_node("Title") as Label).text if _header != null else ""


## Flyers and trails are shown on the player's world.
func _backdrop() -> ThemeDef:
	var w := Catalog.world(_profile.equipped_id(ItemKind.WORLD))
	return w if w != null else ThemeCatalog.default_theme()


func _select(id: String) -> void:
	_selected = id
	refresh()
	if not id.is_empty():
		previewed.emit(kind, id)


## Redraws the coins, the cards, the preview and the popup.
func refresh() -> void:
	_wallet.show_balance(_profile)
	for c in _cards:
		c.refresh(_profile, c.item_id == _selected)
	_look.show_look(_profile, kind, _selected)
	_popup.show_item(_profile, kind, _selected, _backdrop())


## The line under the preview, for tests.
func caption_text() -> String:
	return _look.caption_text()


## What the preview shows, for tests: [flyer, world, trail] ids.
func preview_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in [ItemKind.FLYER, ItemKind.WORLD, ItemKind.TRAIL]:
		out.append(_look.shown_id(k))
	return out


## The portal the preview shows, for tests.
func preview_portal_id() -> String:
	return _look.portal_id()


## [button text, enabled] for the selected item.
func action_label() -> Array:
	return ItemOffer.label(_profile, kind, _selected)


## Gold missing for the selected item (0 when it isn't a gold item or is
## affordable).
func gold_short() -> int:
	return ItemOffer.gold_short(_profile, kind, _selected)


## The convert sheet, on the fewest diamonds that cover the selected item.
func open_convert() -> ConvertSheet:
	if _sheet != null:
		return _sheet
	var short := gold_short()
	var why := ""
	if short > 0:
		why = "You need %d more gold for %s." % [short, ItemChip.short_name(kind, _selected)]
	_sheet = ConvertSheet.new(_checkout, maxi(Economy.diamonds_to_cover(short), 1), why)
	_sheet.converted.connect(func(_diamonds: int) -> void: refresh())
	_sheet.closed.connect(_close_sheet)
	add_child(_sheet)
	return _sheet


func sheet() -> ConvertSheet:
	return _sheet


func _close_sheet() -> void:
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null


## The popup's action: Use, buy (then use), or open the convert sheet.
func _on_action() -> void:
	if _selected.is_empty() or _paying:
		return
	if _profile.equipped_id(kind) == _selected:
		close_popup()
		return
	if not _profile.owns(kind, _selected):
		if gold_short() > 0 and _profile.diamonds > 0:
			open_convert()
			return
		var wanted := _selected
		_paying = true
		var result: Checkout.Result = await _checkout.buy(kind, wanted)
		_paying = false
		if result != Checkout.Result.OK:
			AudioDirector.ui("locked")
			refresh()
			return
		# The player may have tapped something else while the server answered.
		if wanted != _selected:
			refresh()
			return
		AudioDirector.sound("purchase")
	else:
		AudioDirector.ui("confirm")
	_profile.equip(kind, _selected)
	# Main now plays the new pick: no going back to the old track.
	_music.hand_over()
	equipped.emit(kind, _selected)
	# A bought item moves up among yours.
	_show_kind(kind)
	_select(_profile.equipped_id(kind))


## Music: plays a track's preview, or stops it when it is already playing
## (Match my world previews the track for the world in use).
func toggle_preview(id: String) -> void:
	_music.toggle(id, _backdrop().id)
	_show_playing()


## The music card whose preview plays, or "".
func playing_id() -> String:
	return _music.playing if _music != null else ""


## Stops a preview and plays the track from before it again.
func stop_preview() -> void:
	if _music == null or _music.playing.is_empty():
		return
	_music.stop()
	_show_playing()


func _show_playing() -> void:
	for c in _cards:
		if c.layout == ItemCard.Layout.TRACK:
			c.set_playing(c.item_id == _music.playing)


## The track a music card previews: itself, or the world's for Match my world.
func preview_track(id: String) -> MusicTrack:
	return MusicPreview.track_for(id, _backdrop().id)


func _exit_tree() -> void:
	stop_preview()
