class_name ItemCard
extends Button
## One item as a Sticker Pop card, in one of two layouts:
## - TILE (shop grid): picture, short name, and a status line: an "In use" pill,
##   Owned, Free, or the price. Selected: cream fill, thicker outline, bigger drop.
## - TRACK (music, a playlist row): a round play/stop preview button, the name
##   and a "tempo · mood" line, then the same status as a tile. Music cards
##   always use it.

signal preview_pressed(id: String)

enum Layout { TILE, TRACK }

const COIN_ICON := preload("res://assets/ui/coin.svg")
const CHECK_ICON := preload("res://assets/ui/icons/check.svg")
const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const STOP_ICON := preload("res://assets/ui/icons/stop.svg")
const SHUFFLE_ICON := preload("res://assets/ui/icons/shuffle.svg")
## Inner padding between the card edge and its content.
const PAD := UiTokens.SPACE_2
const THUMB_HEIGHT := 70.0
const TILE_HEIGHT := 124.0
const TRACK_HEIGHT := 62.0

var kind := ""
var item_id := ""
var layout := Layout.TILE

var _thumb := ItemThumb.new()
var _name := Label.new()
var _blurb := Label.new()
var _status := HBoxContainer.new()
var _use := PanelContainer.new()
var _icon: TextureRect
var _meta := Label.new()
var _box: BoxContainer
var _preview := Button.new()
var _backdrop: ThemeDef


func _init(
	p_kind: String,
	p_id: String,
	backdrop: ThemeDef,
	thumb_height: float = THUMB_HEIGHT,
	p_layout: Layout = Layout.TILE
) -> void:
	kind = p_kind
	item_id = p_id
	layout = Layout.TRACK if p_kind == Catalog.MUSIC else p_layout
	_backdrop = backdrop
	theme_type_variation = &"CardButton"
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	tooltip_text = Catalog.display_name(kind, p_id)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var across := layout == Layout.TRACK
	_box = HBoxContainer.new() if across else VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, PAD)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 10 if across else UiTokens.SPACE_1)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_box)
	_icon = _small_icon(COIN_ICON, 15, Color.WHITE)
	_thumb.world = backdrop
	match kind:
		Catalog.WORLD:
			var w := Catalog.world(p_id)
			if w != null:
				_thumb.world = w
		Catalog.FLYER:
			var f := Catalog.flyer(p_id)
			if f != null:
				_thumb.flyer = f.idle
			_thumb.bare = true
		Catalog.TRAIL:
			_thumb.trail = Catalog.trail(p_id)
		Catalog.PORTAL:
			_thumb.portal = Catalog.portal(p_id)
	match layout:
		Layout.TRACK:
			_build_track()
		_:
			_build_tile(thumb_height)


func _build_tile(thumb_height: float) -> void:
	var side := thumb_height if kind == Catalog.FLYER else thumb_height * 0.86
	_thumb.custom_minimum_size = Vector2(side if kind == Catalog.FLYER else 84, side)
	_thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_thumb)
	_name.theme_type_variation = &"SmallNameLabel"
	_name.text = ItemChip.short_name(kind, item_id)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_box.add_child(_name)
	_status.alignment = BoxContainer.ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_constant_override("separation", 3)
	_status.custom_minimum_size = Vector2(0, 22)
	_box.add_child(_status)
	_build_status()
	custom_minimum_size = Vector2(0, TILE_HEIGHT)


## The "In use" pill, the coin and the Owned / Free / price text.
func _build_status() -> void:
	_use.theme_type_variation = &"UsePill"
	_use.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var use_row := HBoxContainer.new()
	use_row.add_theme_constant_override("separation", 3)
	use_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	use_row.add_child(_small_icon(CHECK_ICON, 12, UiTokens.INK_LINE))
	var use_text := Label.new()
	use_text.theme_type_variation = &"StatusLabel"
	use_text.text = "In use"
	use_row.add_child(use_text)
	_use.add_child(use_row)
	_status.add_child(_use)
	_status.add_child(_icon)
	_meta.theme_type_variation = &"StatusLabel"
	_status.add_child(_meta)


func _build_track() -> void:
	if item_id == MusicTrack.SHUFFLE:
		# No preview: it's a different track every run.
		var disc := PanelContainer.new()
		disc.add_theme_stylebox_override(
			"panel", UiTheme.sticker(UiTokens.PANEL_RAISED, UiTokens.RADIUS_PILL, Vector2.ZERO, 0)
		)
		disc.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(_small_icon(SHUFFLE_ICON, 20, UiTokens.INK_LINE))
		_box.add_child(disc)
	else:
		_preview.theme_type_variation = &"RoundButton"
		_preview.icon = PLAY_ICON
		_preview.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
		_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_preview.focus_mode = Control.FOCUS_NONE
		_preview.tooltip_text = "Play a preview"
		_preview.pressed.connect(func() -> void: preview_pressed.emit(item_id))
		_box.add_child(_preview)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.theme_type_variation = &"SmallNameLabel"
	_name.add_theme_font_size_override("font_size", 16)
	_name.text = Catalog.display_name(kind, item_id)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_name)
	_blurb.theme_type_variation = &"MutedLabel"
	_blurb.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	_blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_blurb.text = track_line(item_id, _backdrop)
	text.add_child(_blurb)
	_box.add_child(text)
	_status.alignment = BoxContainer.ALIGNMENT_END
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_constant_override("separation", 3)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_build_status()
	_box.add_child(_status)
	custom_minimum_size = Vector2(0, TRACK_HEIGHT)


## The line under a music card's name: "120 BPM · Bright and bouncy", which
## track Match my world plays in `world`, or what Shuffle does.
static func track_line(id: String, world: ThemeDef) -> String:
	match id:
		MusicTrack.MATCH_WORLD:
			if world == null:
				return "The track that fits your world"
			return "%s plays %s" % [world.display_name, MusicTrack.for_world(world.id).display_name]
		MusicTrack.SHUFFLE:
			return "A random track of yours each run"
	var t := Catalog.track(id)
	if t == null:
		return ""
	return "%d BPM · %s" % [t.bpm, t.blurb.trim_suffix(".")]


## Music cards: shows the stop icon while this card's preview plays.
func set_playing(on: bool) -> void:
	_preview.icon = STOP_ICON if on else PLAY_ICON
	_preview.tooltip_text = "Stop the preview" if on else "Play a preview"


func is_playing() -> bool:
	return _preview.icon == STOP_ICON


func _small_icon(tex: Texture2D, side: float, tint: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Each layout uses only some of the widgets made above; free the rest, or they leak.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for n: Node in [_thumb, _name, _blurb, _status, _use, _icon, _meta, _preview]:
		if is_instance_valid(n) and n.get_parent() == null:
			n.free()


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_box.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var content := _box.get_combined_minimum_size()
	var floor_h := 0.0
	match layout:
		Layout.TILE:
			floor_h = TILE_HEIGHT
		Layout.TRACK:
			floor_h = TRACK_HEIGHT
	custom_minimum_size = Vector2(
		maxf(content.x, UiTokens.SIZE_TAP_MIN) + PAD * 2, maxf(content.y + PAD * 2, floor_h)
	)


## Updates the picture, the status line and the sticker from the profile.
func refresh(profile: Profile, selected: bool) -> void:
	button_pressed = selected
	var owned := profile.owns(kind, item_id)
	var in_use := profile.equipped_id(kind) == item_id
	var cost := Shop.price(kind, item_id)
	# Faded only while the player can't afford it; the price still shows.
	_thumb.dimmed = layout == Layout.TILE and not owned and cost > profile.coins
	_use.visible = false
	_icon.visible = false
	_meta.visible = true
	_meta.remove_theme_color_override("font_color")
	if in_use:
		_meta.text = "In use"
		_use.visible = true
		_meta.visible = false
	elif owned:
		_meta.text = "Owned"
		_meta.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	elif cost == 0:
		_meta.text = "Free"
		_meta.add_theme_color_override("font_color", UiTokens.ON_PANEL_MUTED)
	else:
		_meta.text = str(cost)
		_icon.visible = true
	_blurb.add_theme_color_override(
		"font_color", UiTokens.ON_PANEL if selected else UiTokens.ON_PANEL_MUTED
	)
	_set_sticker(selected)


func _set_sticker(selected: bool) -> void:
	var box: StickerBox
	if not selected:
		box = UiTheme.sticker(UiTokens.PANEL, UiTokens.RADIUS_M, UiTheme.DROP_CARD, PAD)
	else:
		box = UiTheme.sticker(
			UiTheme.SELECTED_FILL,
			UiTokens.RADIUS_M,
			UiTheme.DROP_SELECTED,
			PAD,
			UiTheme.BORDER_BOLD
		)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, box)


## The text of the status line, for tests.
func status_text() -> String:
	return _meta.text


func is_selected_look() -> bool:
	var box := get_theme_stylebox("normal") as StickerBox
	return box != null and box.face.bg_color != UiTokens.PANEL
