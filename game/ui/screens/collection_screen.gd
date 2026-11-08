class_name CollectionScreen
extends Control
## Customize (minimal kit): the shop and the loadout in one screen, over the
## live room. A back arrow, the title and the coins; the flyer in use (or the
## tapped one) standing on the room with its puff trail and a line under it
## ("Buzz, in use"); the trail or exit portal of those tabs drawn with it (the
## room behind already shows a tapped world); five tabs in a paper pill bar
## (Flyers, Worlds, Trails, Portals, Music); and the items as flat paper tiles,
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

## Only the shop is left (the first-start pickers were removed).
enum Mode { SHOP }

const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
const COIN_ICON := preload("res://assets/ui/coin.svg")
const CLOSE_ICON := preload("res://assets/ui/icons/close.svg")
## No tab and no items yet: hats come later and will share the hitbox too.
const HATS := "hats"
const TAB_NAMES := {
	Catalog.FLYER: "Flyers",
	Catalog.WORLD: "Worlds",
	Catalog.TRAIL: "Trails",
	Catalog.PORTAL: "Portals",
	Catalog.MUSIC: "Music",
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
const TAB_FONT := 13
const TAB_PAD := 2

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
		_coins,
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
	col.add_child(UiKit.header("Customize", closed.emit, _coins))

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

	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TabStrip"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	bar.add_child(tabs)
	var group := ButtonGroup.new()
	for k: String in Catalog.KINDS:
		var tab := Button.new()
		tab.theme_type_variation = &"TabButton"
		tab.text = TAB_NAMES[k]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Inside the bar's 3 px padding the strip is the 44 px tap height.
		tab.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_show_kind.bind(k))
		_tight(tab)
		_tabs[k] = tab
		tabs.add_child(tab)
	col.add_child(bar)

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


## Five tabs share 332 px equally (clip_text drops the text's own minimum
## width, so a long name can't push the last tab into the bar's edge), with a
## little less padding than the theme's (copied from
## UiTheme: the tab isn't in the tree yet, so its own get_theme_stylebox()
## would be Godot's).
func _tight(tab: Button) -> void:
	tab.add_theme_font_size_override("font_size", TAB_FONT)
	tab.clip_text = true
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := UiTheme.get_theme().get_stylebox(state, &"TabButton").duplicate() as StyleBox
		box.content_margin_left = TAB_PAD
		box.content_margin_right = TAB_PAD
		tab.add_theme_stylebox_override(state, box)


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
	if _tabs.has(k):
		(_tabs[k] as Button).button_pressed = true
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
	_coins.set_amount(_profile.coins)
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
	_action.icon = COIN_ICON if buy else (LOCK_ICON if short else null)
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
	match kind:
		Catalog.TRAIL:
			_preview.trail = t if t != null else TrailStyle.world_ribbon()
		Catalog.PORTAL:
			_preview.portal = _preview_portal
	_flyer_art.visible = kind != Catalog.TRAIL


## The popup picture: flyers and worlds on a clean sky with a far hill (the
## tapped world, or the player's), the other kinds as their small picture.
func _show_popup_picture() -> void:
	_popup_thumb.world = _backdrop()
	_popup_thumb.flyer = null
	_popup_thumb.trail = null
	_popup_thumb.portal = null
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
	return ""
