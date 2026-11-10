class_name CollectionScreen
extends Control
## One kind's list in Customize (minimal kit): the shop and the player's own
## items of that kind in one screen, over the live room. It opens from a card on
## LookScreen ("Your look"), and Back returns there. A back arrow, the kind's
## name as the title and the coins; the flyer in use (or the
## tapped one) standing on the room with its puff trail and a line under it
## ("Buzz, in use"); the trail or exit portal of those kinds drawn with it (the
## room behind already shows a tapped world; Crashes show the effect round the
## flyer, Plates a sample leaderboard row); and the items as flat paper tiles,
## yours first, then the shop's. Tapping an item opens a small popup with its
## one action: Use, Get for free, Unlock for N or Need N more coins.
## Music items are playlist rows whose play button previews the track; the
## track that was playing comes back when the preview stops or the screen
## closes (equipping hands over to main, which plays the new pick).

signal closed
## Something was bought or put to use in the shop.
signal equipped(kind: String, id: String)
## A world was tapped: the room behind the menu shows it until the screen closes.
signal previewed(kind: String, id: String)
## The wallet in the header was tapped: main opens the Shop.
signal store_pressed
## Diamonds were turned into gold here (already in the profile): main saves.
signal wallet_changed

## Only the shop is left (the first-start pickers were removed).
enum Mode { SHOP }

const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
const COIN_ICON := preload("res://assets/ui/coin.svg")
const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
## The action when gold is short but diamonds can cover it: opens the sheet.
const CONVERT_LABEL := "Turn diamonds into gold"
const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
## No items yet: hats come later and will share the hitbox too.
const HATS := "hats"
## The screen's title per kind.
const TITLES := {
	Catalog.FLYER: "Flyers",
	Catalog.WORLD: "Worlds",
	Catalog.TRAIL: "Trails",
	Catalog.PORTAL: "Portals",
	Catalog.MUSIC: "Music",
	Catalog.CRASH: "Crashes",
	Catalog.PLATE: "Plates",
	HATS: "Hats",
}
## The popup's clean picture, as wide as its card's inside.
const POPUP_PICTURE := Vector2(264, 160)
## The popup card's side margins.
const POPUP_SIDE := 28
## The flyer standing on the room: its body, and the stage it stands on.
const PREVIEW_BODY := 52.0
const PREVIEW_HEIGHT := 84.0
const SHOP_ACTION_HEIGHT := float(UiTokens.SIZE_BUTTON_H)
const SHOP_COLUMNS := 3
const GRID_GAP := 10
const SIDE := 14

var mode: Mode
var kind: String
## Where diamonds are spent; main sets it before the screen is shown (the
## local wallet when left alone).
var wallet_service: WalletService

var _profile: Profile
var _selected := ""
var _cards: Array[ItemCard] = []
var _wallet := Wallet.new()
## The convert sheet, while it is open.
var _sheet: ConvertSheet
## A premium purchase is waiting for the wallet's answer.
var _paying := false
var _detail_name := Label.new()
var _detail_text := Label.new()
var _badge_text := Label.new()
var _action := Button.new()
## The header row; its "Title" label names the kind shown.
var _header: Control
## Every item of the tab, yours first.
var _owned_grid := GridContainer.new()
## The popup for a tapped item.
var _popup := Control.new()
var _popup_thumb := ItemThumb.new()
## The preview on the room: the flyer with its puffs, or (Trails, Portals) a
## picture with no room of its own, and the line under it.
var _stage := Control.new()
var _flyer_art := FlyerArt.new(null, PREVIEW_BODY)
var _preview := ItemThumb.new()
var _caption := Label.new()
var _preview_portal: PortalStyle
var _empty := PanelContainer.new()
var _empty_text := Label.new()
## Music preview: the card id playing ("" for none) and the track to go back to.
var _playing := ""
var _resting: MusicTrack


func _init(profile: Profile, p_mode: Mode, tab: String = Catalog.FLYER) -> void:
	_profile = profile
	mode = p_mode
	kind = tab


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	# Keeps the grid above the floor spikes.
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_7)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	margin.add_child(col)
	_build_shop(col)
	_action.theme_type_variation = &"ActionButton"
	_action.custom_minimum_size = Vector2(0, SHOP_ACTION_HEIGHT)
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_constant_override("icon_max_width", 22)
	_action.pressed.connect(_on_action)
	add_child(_build_popup())
	_show_kind(kind)


## Free any widget made in the member list that never joined the screen, or
## it leaks.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for n: Node in [
		_wallet,
		_detail_name,
		_detail_text,
		_badge_text,
		_action,
		_stage,
		_flyer_art,
		_preview,
		_caption,
		_empty,
		_popup,
		_popup_thumb,
		_owned_grid,
	]:
		if is_instance_valid(n) and n.get_parent() == null:
			n.free()


func _build_shop(col: VBoxContainer) -> void:
	_wallet.pressed.connect(store_pressed.emit)
	_header = UiKit.header(title_for(kind), closed.emit, _wallet)
	col.add_child(_header)

	# The preview: the flyer standing on the room, no card.
	_stage.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.open = true
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_preview)
	_stage.add_child(_flyer_art)
	_flyer_art.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_flyer_art.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flyer_art.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_child(_stage)
	_caption.theme_type_variation = &"SkyCaption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_caption)

	var scroll := SmoothScroll.new()
	scroll.blocked = is_popup_open
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", int(FadeMask.FADE))
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_grid.columns = SHOP_COLUMNS
	_owned_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_owned_grid.add_theme_constant_override("v_separation", GRID_GAP)
	stack.add_child(_owned_grid)
	_empty.theme_type_variation = &"Card"
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_text.theme_type_variation = &"MutedLabel"
	_empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_text.custom_minimum_size = Vector2(240, 0)
	_empty.add_child(_empty_text)
	stack.add_child(_empty)
	pad.add_child(stack)
	scroll.add_child(pad)
	col.add_child(FadeMask.new(scroll))


## The item popup: dims the room; a paper card with the item's name and a
## bare close X, a clean picture, the blurb and its one action. Tapping
## outside or the X dismisses it.
func _build_popup() -> Control:
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.visible = false
	var dim := ColorRect.new()
	dim.color = UiTokens.SCRIM
	ScrimBleed.attach(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_popup.add_child(dim)
	var side := MarginContainer.new()
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("margin_left", POPUP_SIDE)
	side.add_theme_constant_override("margin_right", POPUP_SIDE)
	_popup.add_child(side)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BigPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SPACE_3)
	var head := HBoxContainer.new()
	_detail_name.theme_type_variation = &"NameLabel"
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_detail_name)
	var close := UiKit.icon_button(CLOSE_ICON, "Close", &"InkButton", UiTokens.SIZE_TAP_MIN)
	# Ink on the paper card, also in night worlds.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		close.add_theme_color_override(state, UiTokens.INK_LINE)
	close.pressed.connect(close_popup)
	head.add_child(close)
	box.add_child(head)
	_popup_thumb.custom_minimum_size = Vector2(0, POPUP_PICTURE.y)
	_popup_thumb.outlined = false
	box.add_child(_popup_thumb)
	_detail_text.theme_type_variation = &"InkLabel"
	_detail_text.add_theme_font_size_override("font_size", 15)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(200, 0)
	box.add_child(_detail_text)
	_badge_text.theme_type_variation = &"MutedLabel"
	box.add_child(_badge_text)
	box.add_child(_action)
	panel.add_child(box)
	center.add_child(panel)
	return _popup


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_popup()


## Customize: tapping an item previews it and opens its popup.
func open_popup() -> void:
	if not _selected.is_empty():
		_popup.visible = true


func close_popup() -> void:
	_popup.visible = false


func is_popup_open() -> bool:
	return _popup.visible


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
	_owned_grid.columns = 1 if k == Catalog.MUSIC else SHOP_COLUMNS
	if _header != null:
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
	_empty_text.text = _empty_message()
	# Music rows need the room: no flyer preview there.
	_stage.visible = k != Catalog.MUSIC
	_caption.visible = k != Catalog.MUSIC
	var current := _profile.equipped_id(kind)
	_select(current if current in ids else (ids[0] if not ids.is_empty() else ""))


## "Crashes" for Catalog.CRASH: the title of a kind's list.
static func title_for(k: String) -> String:
	return str(TITLES.get(k, "Customize"))


## The title in the header, for tests.
func title_text() -> String:
	return (_header.get_node("Title") as Label).text if _header != null else ""


func _empty_message() -> String:
	return "Hats are coming. Every flyer will wear them on the same hitbox."


## Flyers and trails are shown on the player's world.
func _backdrop() -> ThemeDef:
	var w := Catalog.world(_profile.equipped_id(Catalog.WORLD))
	return w if w != null else ThemeCatalog.default_theme()


func _select(id: String) -> void:
	_selected = id
	refresh()
	if not id.is_empty():
		previewed.emit(kind, id)


## Redraws the cards, the preview, the popup and its action button.
func refresh() -> void:
	_wallet.show_balance(_profile)
	for c in _cards:
		c.refresh(_profile, c.item_id == _selected)
	_detail_name.text = Catalog.display_name(kind, _selected)
	_detail_text.text = _detail(kind, _selected)
	_badge_text.text = badge_text(kind, _selected)
	_badge_text.visible = not _badge_text.text.is_empty()
	_show_preview()
	var label := action_label()
	_action.text = label[0]
	_action.disabled = not label[1]
	# In the popup, "In use" stays tappable: it just closes the popup.
	if label[0] == "In use":
		_action.disabled = false
	var buy: bool = label[1] and str(label[0]).begins_with("Unlock")
	var short: bool = not label[1] and label[0] != "In use"
	var pay_icon := DIAMOND_ICON if Shop.diamond_price(kind, _selected) > 0 else COIN_ICON
	if label[0] == CONVERT_LABEL:
		pay_icon = DIAMOND_ICON
		buy = true
	_action.icon = pay_icon if buy else (LOCK_ICON if short else null)
	# The coin keeps its own colours on the ink button (white tints nothing).
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		_action.add_theme_color_override(state, Color.WHITE)
	_caption.text = _caption_text()


## "Buzz, in use" for the item in use, else the tapped item's name.
func _caption_text() -> String:
	if _selected.is_empty():
		return ""
	var item := ItemChip.short_name(kind, _selected)
	return item + ", in use" if _profile.equipped_id(kind) == _selected else item


## The line under the preview, for tests.
func caption_text() -> String:
	return _caption.text


## The id the preview shows for a kind: the tapped item, else the one in use.
func _preview_id(k: String) -> String:
	if k == kind and not _selected.is_empty():
		return _selected
	return _profile.equipped_id(k)


## The preview: the items in use, with the tapped one swapped in, on the
## room (a tapped world is shown by the room itself). The popup picture shows
## the tapped item on its own.
func _show_preview() -> void:
	_show_popup_picture()
	var w := Catalog.world(_preview_id(Catalog.WORLD))
	var f := Catalog.flyer(_preview_id(Catalog.FLYER))
	var t := Catalog.trail(_preview_id(Catalog.TRAIL))
	var p := Catalog.portal(_preview_id(Catalog.PORTAL))
	_preview_portal = p if p != null else Catalog.portal(PortalStyle.DEFAULT_ID)
	_flyer_art.texture = f.idle if f != null else null
	# Trails: the flyer leads its trail; Portals: the exit on the right wall.
	_preview.world = w if w != null else ThemeCatalog.default_theme()
	_preview.flyer = f.idle if f != null and kind == Catalog.TRAIL else null
	_preview.trail = null
	_preview.portal = null
	_preview.crash = null
	_preview.plate = null
	match kind:
		Catalog.TRAIL:
			_preview.trail = t if t != null else TrailStyle.world_ribbon()
		Catalog.PORTAL:
			_preview.portal = _preview_portal
		Catalog.CRASH:
			# The picture draws the flyer itself, under or over the effect.
			_preview.crash = Catalog.crash(_preview_id(Catalog.CRASH))
			_preview.flyer = f.idle if f != null else null
		Catalog.PLATE:
			_preview.plate = Catalog.plate(_preview_id(Catalog.PLATE))
			_preview.flyer = f.idle if f != null else null
	_flyer_art.visible = kind not in [Catalog.TRAIL, Catalog.CRASH, Catalog.PLATE]


## The popup picture: flyers and worlds on a clean sky with a far hill (the
## tapped world, or the player's), the other kinds as their small picture.
func _show_popup_picture() -> void:
	_popup_thumb.world = _backdrop()
	_popup_thumb.flyer = null
	_popup_thumb.trail = null
	_popup_thumb.portal = null
	_popup_thumb.crash = null
	_popup_thumb.plate = null
	_popup_thumb.music = ""
	_popup_thumb.scenic = kind == Catalog.FLYER or kind == Catalog.WORLD
	match kind:
		Catalog.FLYER:
			var pf := Catalog.flyer(_selected)
			_popup_thumb.flyer = pf.idle if pf != null else null
		Catalog.WORLD:
			var pw := Catalog.world(_selected)
			if pw != null:
				_popup_thumb.world = pw
			var mine := Catalog.flyer(_profile.equipped_id(Catalog.FLYER))
			_popup_thumb.flyer = mine.idle if mine != null else null
		Catalog.TRAIL:
			_popup_thumb.trail = Catalog.trail(_selected)
		Catalog.PORTAL:
			_popup_thumb.portal = Catalog.portal(_selected)
		Catalog.MUSIC:
			_popup_thumb.music = _selected
		Catalog.CRASH, Catalog.PLATE:
			var own := Catalog.flyer(_profile.equipped_id(Catalog.FLYER))
			_popup_thumb.flyer = own.idle if own != null else null
			_popup_thumb.crash = Catalog.crash(_selected) if kind == Catalog.CRASH else null
			_popup_thumb.plate = Catalog.plate(_selected) if kind == Catalog.PLATE else null


## What the preview shows, for tests: [flyer, world, trail] ids.
func preview_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in [Catalog.FLYER, Catalog.WORLD, Catalog.TRAIL]:
		out.append(_preview_id(k))
	return out


## The portal the preview shows, for tests.
func preview_portal_id() -> String:
	return _preview_portal.id if _preview_portal != null else ""


## [button text, enabled] for the selected item.
func action_label() -> Array:
	if kind == HATS:
		return ["Hats are coming", false]
	if _selected.is_empty():
		return ["Pick one", false]
	if _profile.equipped_id(kind) == _selected:
		return ["In use", false]
	if _profile.owns(kind, _selected):
		return ["Use %s" % ItemChip.short_name(kind, _selected), true]
	var gems := Shop.diamond_price(kind, _selected)
	if gems > 0:
		return _diamond_label(gems)
	return _price_label(Shop.price(kind, _selected))


func _price_label(cost: int) -> Array:
	if cost == 0:
		return ["Get for free", true]
	if _profile.coins >= cost:
		return ["Unlock for %d" % cost, true]
	# Short on gold, but diamonds can make up for it.
	if _profile.diamonds > 0:
		return [CONVERT_LABEL, true]
	return ["Need %d more gold" % (cost - _profile.coins), false]


## A premium item: paid with diamonds (the wallet opens the Shop for more).
func _diamond_label(gems: int) -> Array:
	if _profile.diamonds >= gems:
		return ["Unlock for %d" % gems, true]
	return ["Need %d more diamonds" % (gems - _profile.diamonds), false]


## Gold missing for the selected item (0 when it isn't a gold item or is
## affordable).
func gold_short() -> int:
	if _selected.is_empty() or _profile.owns(kind, _selected):
		return 0
	if Shop.diamond_price(kind, _selected) > 0:
		return 0
	return maxi(Shop.price(kind, _selected) - _profile.coins, 0)


## The convert sheet, on the fewest diamonds that cover the selected item.
func open_convert() -> ConvertSheet:
	if _sheet != null:
		return _sheet
	var short := gold_short()
	var why := ""
	if short > 0:
		why = "You need %d more gold for %s." % [short, ItemChip.short_name(kind, _selected)]
	_sheet = ConvertSheet.new(
		_profile, maxi(Economy.diamonds_to_cover(short), 1), why, _wallet_service()
	)
	_sheet.converted.connect(_on_converted)
	_sheet.closed.connect(_close_sheet)
	add_child(_sheet)
	return _sheet


func sheet() -> ConvertSheet:
	return _sheet


func _wallet_service() -> WalletService:
	if wallet_service == null:
		wallet_service = WalletService.new(_profile)
	return wallet_service


## Pays for the selected premium item through the wallet (which may ask the
## server) and hands it over. False when the diamonds could not be spent.
func _buy_with_diamonds(gems: int) -> bool:
	var item_kind := kind
	var item_id := _selected
	if _profile.diamonds < gems:
		return false
	_paying = true
	@warning_ignore("redundant_await")
	var ok: bool = await _wallet_service().spend(
		gems, WalletService.ITEM, "%s:%s" % [item_kind, item_id]
	)
	_paying = false
	if ok:
		_profile.grant(item_kind, item_id)
	return ok


func _on_converted(_diamonds: int) -> void:
	wallet_changed.emit()
	refresh()


func _close_sheet() -> void:
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null


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
		var gems := Shop.diamond_price(kind, _selected)
		var bought := false
		if gems > 0:
			var wanted := _selected
			bought = await _buy_with_diamonds(gems)
			# The player may have tapped something else while the server answered.
			if bought and wanted != _selected:
				wallet_changed.emit()
				refresh()
				return
		else:
			bought = Shop.buy(_profile, kind, _selected) == Shop.Result.OK
		if not bought:
			AudioDirector.ui("locked")
			refresh()
			return
		AudioDirector.sound("purchase")
	else:
		AudioDirector.ui("confirm")
	_profile.equip(kind, _selected)
	# Main now plays the new pick: no going back to the old track.
	_playing = ""
	_resting = null
	equipped.emit(kind, _selected)
	# A bought item moves up among yours.
	_show_kind(kind)
	_select(_profile.equipped_id(kind))


## Music: plays a track's preview, or stops it when it is already playing
## (Match my world previews the track for the world in use). Tests run
## without an AudioDirector, so only the state changes then.
func toggle_preview(id: String) -> void:
	if _playing == id:
		stop_preview()
		return
	var t := preview_track(id)
	if t == null:
		return
	var director := _director()
	if _playing.is_empty():
		_resting = director.track if director != null else null
	_playing = id
	if director != null:
		director.play_track(t)
	_show_playing()


## The music card whose preview plays, or "".
func playing_id() -> String:
	return _playing


## Stops a preview and plays the track from before it again.
func stop_preview() -> void:
	if _playing.is_empty():
		return
	_playing = ""
	var director := _director()
	if director != null and _resting != null:
		director.play_track(_resting)
	_resting = null
	_show_playing()


## The live AudioDirector, or null (tests, or one already freed).
static func _director() -> AudioDirector:
	var d: Variant = AudioDirector.current
	if not is_instance_valid(d) or not (d as AudioDirector).is_inside_tree():
		return null
	return d as AudioDirector


func _show_playing() -> void:
	for c in _cards:
		if c.layout == ItemCard.Layout.TRACK:
			c.set_playing(c.item_id == _playing)


## The track a music card previews: itself, or the world's for Match my world.
func preview_track(id: String) -> MusicTrack:
	if id == MusicTrack.MATCH_WORLD:
		return MusicTrack.for_world(_backdrop().id)
	return Catalog.track(id)


func _exit_tree() -> void:
	stop_preview()


## A short extra line in the shop: "Premium" or "Seasonal: October" for
## worlds, the worlds a flyer fits for flyers, the worlds a track matches for
## music. Empty when there is nothing.
static func badge_text(k: String, id: String) -> String:
	match k:
		Catalog.WORLD:
			var w := Catalog.world(id)
			if w == null:
				return ""
			if not w.season.is_empty():
				return "Seasonal: %s" % w.season
			return "Premium" if w.premium else ""
		Catalog.FLYER:
			var f := Catalog.flyer(id)
			if f == null or f.fits_worlds.is_empty():
				return ""
			var names: Array[String] = []
			for wid in f.fits_worlds:
				names.append(Catalog.display_name(Catalog.WORLD, wid))
			return "Fits " + " and ".join(names)
		Catalog.MUSIC:
			var t := Catalog.track(id)
			if t == null or t.worlds.is_empty():
				return ""
			var names: Array[String] = []
			for wid in t.worlds:
				names.append(Catalog.display_name(Catalog.WORLD, wid))
			var last: String = names.pop_back()
			if names.is_empty():
				return "Matches " + last
			return "Matches %s and %s" % [", ".join(names), last]
	return ""


static func _detail(k: String, id: String) -> String:
	match k:
		Catalog.FLYER:
			var f := Catalog.flyer(id)
			if f == null:
				return ""
			return f.blurb + " Looks only, same hitbox."
		Catalog.WORLD:
			return "A world to play in. Looks only: every world plays the same."
		Catalog.TRAIL:
			var t := Catalog.trail(id)
			if t != null and t.use_world_color:
				return "Takes the color of the world you play in."
			return "A trail behind your flyer."
		Catalog.PORTAL:
			var p := Catalog.portal(id)
			var blurb := p.blurb + " " if p != null and not p.blurb.is_empty() else ""
			return blurb + "Looks only: every exit is the same size."
		Catalog.MUSIC:
			match id:
				MusicTrack.MATCH_WORLD:
					return "Plays the track that fits the world you pick."
				MusicTrack.SHUFFLE:
					return "Plays a random track you own, a new one each run."
			var t := Catalog.track(id)
			if t == null:
				return ""
			return "%s. Music only: every run plays the same." % ItemCard.track_line(id, null)
		Catalog.CRASH:
			var c := Catalog.crash(id)
			var line := c.blurb + " " if c != null and not c.blurb.is_empty() else ""
			return line + "Looks only: it plays after the run has ended."
		Catalog.PLATE:
			var plate := Catalog.plate(id)
			var line := plate.blurb + " " if plate != null and not plate.blurb.is_empty() else ""
			return line + "Shows behind your row on the leaderboards."
	return ""
