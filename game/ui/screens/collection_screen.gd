class_name CollectionScreen
extends Control
## Customize (Sticker Pop): the shop and the loadout in one screen, over the
## live room. A live preview of the flyer, world, trail and exit portal (the
## tapped item replaces the one in use), tabs for Flyers, Worlds, Trails,
## Portals, Music and Hats (coming), and the items: yours first, then the ones
## in the shop. Tapping an item opens a small popup with its one action: Use,
## Get for free, Unlock for N or Need N more coins.
## Music items are playlist rows whose play button previews the track; the
## track that was playing comes back when the preview stops or the screen
## closes (equipping hands over to main, which plays the new pick).

signal closed
## Something was bought or put to use in the shop.
signal equipped(kind: String, id: String)
## A world was tapped: the room behind the menu shows it until the screen closes.
signal previewed(kind: String, id: String)

## Only the shop is left (the first-start pickers were removed).
enum Mode { SHOP }

const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
## A tab with no items yet: hats come later and will share the hitbox too.
const HATS := "hats"
const TAB_NAMES := {
	Catalog.FLYER: "Flyers",
	Catalog.WORLD: "Worlds",
	Catalog.TRAIL: "Trails",
	Catalog.PORTAL: "Portals",
	Catalog.MUSIC: "Music",
	HATS: "Hats",
}
const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
const POPUP_PICTURE := Vector2(160, 120)
const PREVIEW_HEIGHT := 130.0
const SHOP_ACTION_HEIGHT := 56.0
const SHOP_COLUMNS := 3
const SELECTED_TILT := 2.0
## Wide music rows tilt less.
const SELECTED_ROW_TILT := 1.0
## Six tabs fit 360 px only with small type and tight padding.
const TAB_FONT := 13
const TAB_PAD := 3

var mode: Mode
var kind: String

var _profile: Profile
var _selected := ""
var _cards: Array[ItemCard] = []
var _coins := CoinPill.new()
var _detail_name := Label.new()
var _detail_text := Label.new()
var _badge_text := Label.new()
var _action := Button.new()
var _tabs := {}
## Customize: your items, then the shop's, each under its own label.
var _owned_grid := GridContainer.new()
var _shop_grid := GridContainer.new()
var _owned_label := Label.new()
var _shop_label := Label.new()
## The popup for a tapped item (Customize).
var _popup := Control.new()
var _popup_thumb := ItemThumb.new()
var _preview := ItemThumb.new()
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
	margin.add_theme_constant_override("margin_left", UiTokens.SPACE_4 + 4)
	margin.add_theme_constant_override("margin_right", UiTokens.SPACE_4 + 4)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	# Keeps the action button above the floor spikes.
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_6 + 8)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	margin.add_child(col)
	_build_shop(col)
	_action.theme_type_variation = &"ActionButton"
	_action.custom_minimum_size = Vector2(0, SHOP_ACTION_HEIGHT)
	_action.focus_mode = Control.FOCUS_NONE
	_action.pressed.connect(_on_action)
	add_child(_build_popup())
	_show_kind(kind)


## Free any widget made in the member list that never joined the screen, or
## it leaks.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for n: Node in [
		_coins,
		_detail_name,
		_detail_text,
		_badge_text,
		_preview,
		_empty,
		_popup,
		_popup_thumb,
		_owned_grid,
		_shop_grid,
		_owned_label,
		_shop_label
	]:
		if is_instance_valid(n) and n.get_parent() == null:
			n.free()


func _build_shop(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	var back := Button.new()
	back.theme_type_variation = &"RoundButton"
	back.icon = BACK_ICON
	back.tooltip_text = "Back"
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(closed.emit)
	row.add_child(back)
	var title := _title("Customize", -3.0)
	(title.content() as Label).add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(title.content() as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(title)
	_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_coins)
	col.add_child(row)

	# The live preview: what you'd look like with the tapped item.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(
		"panel", UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_SELECTED, 5)
	)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	frame.add_child(_preview)
	var tilted := Tilt.new(frame, -1.0)
	tilted.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(tilted)

	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TabStrip"
	var tabs := HBoxContainer.new()
	# No gaps: five tabs (Portals joined) only just fit the 360 px screen.
	tabs.add_theme_constant_override("separation", 0)
	bar.add_child(tabs)
	var group := ButtonGroup.new()
	for k: String in Catalog.KINDS + [HATS]:
		var tab := Button.new()
		tab.theme_type_variation = &"TabButton"
		tab.text = TAB_NAMES[k]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_show_kind.bind(k))
		_tight(tab)
		_tabs[k] = tab
		tabs.add_child(tab)
	col.add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Room inside the scroll area for the cards' drops and the tilted card.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_bottom", 10)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair: Array in [
		[_owned_label, _owned_grid, "Yours"], [_shop_label, _shop_grid, "In the shop"]
	]:
		var label: Label = pair[0]
		label.theme_type_variation = &"SkyLabel"
		label.add_theme_font_size_override("font_size", 20)
		label.text = pair[2]
		stack.add_child(label)
		var g: GridContainer = pair[1]
		g.columns = SHOP_COLUMNS
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(g)
	_empty.theme_type_variation = &"StickerPanel"
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_text.theme_type_variation = &"MutedLabel"
	_empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_text.custom_minimum_size = Vector2(240, 0)
	_empty.add_child(_empty_text)
	stack.add_child(_empty)
	pad.add_child(stack)
	scroll.add_child(pad)
	col.add_child(scroll)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap)


## Tabs keep only a little padding (copied from UiTheme: the tab isn't in the
## tree yet, so its own get_theme_stylebox() would be Godot's).
func _tight(tab: Button) -> void:
	tab.add_theme_font_size_override("font_size", TAB_FONT)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := UiTheme.get_theme().get_stylebox(state, &"TabButton").duplicate() as StyleBox
		box.content_margin_left = TAB_PAD
		box.content_margin_right = TAB_PAD
		tab.add_theme_stylebox_override(state, box)


## The item popup: dims the room, a sticker panel with the item's name,
## picture, blurb and its one action. Tapping outside or Close dismisses it.
func _build_popup() -> Control:
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiTokens.INK_900, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BigPanel"
	panel.custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var head := HBoxContainer.new()
	_detail_name.theme_type_variation = &"NameLabel"
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_detail_name)
	var close := Button.new()
	close.theme_type_variation = &"RoundButton"
	close.icon = CLOSE_ICON
	close.tooltip_text = "Close"
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_popup)
	head.add_child(close)
	box.add_child(head)
	_popup_thumb.custom_minimum_size = POPUP_PICTURE
	_popup_thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_popup_thumb)
	_detail_text.theme_type_variation = &"MutedLabel"
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(240, 0)
	box.add_child(_detail_text)
	_badge_text.theme_type_variation = &"StatusLabel"
	box.add_child(_badge_text)
	box.add_child(_action)
	panel.add_child(box)
	center.add_child(Tilt.new(panel, -1.0))
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


func _title(text: String, tilt: float) -> Tilt:
	var l := Label.new()
	l.theme_type_variation = &"TitleLabel"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := Tilt.new(l, tilt)
	return t


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
	var columns := 1 if k == Catalog.MUSIC else SHOP_COLUMNS
	_owned_grid.columns = columns
	_shop_grid.columns = columns
	if _tabs.has(k):
		(_tabs[k] as Button).button_pressed = true
	for c in _cards:
		c.get_parent().queue_free()
	_cards.clear()
	var backdrop := _backdrop()
	var ids := item_ids()
	for id in ids:
		var card := ItemCard.new(kind, id, backdrop)
		card.pressed.connect(_tap.bind(id))
		card.preview_pressed.connect(toggle_preview)
		var holder := Tilt.new(card, 0.0)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(_owned_grid if _profile.owns(kind, id) else _shop_grid).add_child(holder)
		_cards.append(card)
	close_popup()
	_empty.visible = ids.is_empty()
	_empty_text.text = _empty_message()
	_owned_label.visible = ids.any(func(i: String) -> bool: return _profile.owns(kind, i))
	_shop_label.visible = ids.any(func(i: String) -> bool: return not _profile.owns(kind, i))
	var current := _profile.equipped_id(kind)
	_select(current if current in ids else (ids[0] if not ids.is_empty() else ""))


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


## Redraws the cards, the detail sticker and the action button.
func refresh() -> void:
	_coins.set_amount(_profile.coins)
	for c in _cards:
		var on := c.item_id == _selected
		c.refresh(_profile, on)
		var tilt := SELECTED_ROW_TILT if kind == Catalog.MUSIC else SELECTED_TILT
		(c.get_parent() as Tilt).degrees = tilt if on else 0.0
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
	_action.icon = LOCK_ICON if not label[1] and label[0] != "In use" else null


## The id the preview shows for a kind: the tapped item, else the one in use.
func _preview_id(k: String) -> String:
	if k == kind and not _selected.is_empty():
		return _selected
	return _profile.equipped_id(k)


## The preview: the items in use, with the tapped one swapped in. The popup
## picture shows the tapped item on its own.
func _show_preview() -> void:
	_popup_thumb.world = _backdrop()
	_popup_thumb.flyer = null
	_popup_thumb.trail = null
	_popup_thumb.portal = null
	_popup_thumb.music = ""
	_popup_thumb.bare = kind == Catalog.FLYER
	match kind:
		Catalog.FLYER:
			var pf := Catalog.flyer(_selected)
			_popup_thumb.flyer = pf.flap if pf != null else null
		Catalog.WORLD:
			var pw := Catalog.world(_selected)
			if pw != null:
				_popup_thumb.world = pw
		Catalog.TRAIL:
			_popup_thumb.trail = Catalog.trail(_selected)
		Catalog.PORTAL:
			_popup_thumb.portal = Catalog.portal(_selected)
		Catalog.MUSIC:
			_popup_thumb.music = _selected
	var w := Catalog.world(_preview_id(Catalog.WORLD))
	_preview.world = w if w != null else ThemeCatalog.default_theme()
	var f := Catalog.flyer(_preview_id(Catalog.FLYER))
	_preview.flyer = f.flap if f != null else null
	var t := Catalog.trail(_preview_id(Catalog.TRAIL))
	_preview.trail = t if t != null else TrailStyle.world_ribbon()
	var p := Catalog.portal(_preview_id(Catalog.PORTAL))
	_preview.portal = p if p != null else Catalog.portal(PortalStyle.DEFAULT_ID)


## What the preview shows, for tests: [flyer, world, trail] ids.
func preview_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in [Catalog.FLYER, Catalog.WORLD, Catalog.TRAIL]:
		out.append(_preview_id(k))
	return out


## The portal the preview shows, for tests.
func preview_portal_id() -> String:
	return _preview.portal.id if _preview.portal != null else ""


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
	return _price_label(Shop.price(kind, _selected))


func _price_label(cost: int) -> Array:
	if cost == 0:
		return ["Get for free", true]
	if _profile.coins >= cost:
		return ["Unlock for %d" % cost, true]
	return ["Need %d more coins" % (cost - _profile.coins), false]


func _on_action() -> void:
	if _selected.is_empty():
		return
	if _profile.equipped_id(kind) == _selected:
		close_popup()
		return
	if not _profile.owns(kind, _selected):
		if Shop.buy(_profile, kind, _selected) != Shop.Result.OK:
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
	# A bought item moves to Yours.
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
	return ""
