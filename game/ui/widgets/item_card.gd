class_name ItemCard
extends Button
## One item as a flat paper card (minimal kit), in one of two layouts:
## - TILE (Customize grid): a small picture, the short name and a status line:
##   an ink "In use" pill with a check, a muted Owned or Free, the price with a
##   coin, or a lock and the price (and a faded picture) while the player can't
##   afford it. In use: a 3px ink ring inside the card. Tapped: a raised fill.
## - TRACK (music, a playlist row): a paper pill with a 44px round preview
##   button (soft edge with an ink play icon; ink with a white stop while it
##   plays), the name over a muted "tempo · mood" line, and the same status at
##   the right. Music cards always use it.

signal preview_pressed(id: String)

enum Layout { TILE, TRACK }

const COIN_ICON := preload("res://assets/ui/coin.svg")
const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")
const CHECK_ICON := preload("res://assets/ui/icons/check.svg")
const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const STOP_ICON := preload("res://assets/ui/icons/stop.svg")
const SHUFFLE_ICON := preload("res://assets/ui/icons/shuffle.svg")
## Inner padding between the card edge and its content (a tile's bottom gets
## TILE_PAD_BOTTOM; a music row has its own TRACK_PAD).
const PAD := 6
const TILE_PAD_BOTTOM := 8
## left, top, right, bottom of a music row.
const TRACK_PAD: Array[int] = [8, 8, 14, 8]
## The picture's height; flyers are THUMB_WIDTH wide, other pictures wider.
const THUMB_HEIGHT := 44.0
const THUMB_WIDTH := 56.0
const ROOM_THUMB_WIDTH := 72.0
## Long names ("Jungle Canopy") narrow and shrink a step instead of being cut:
## [font size, Archivo width] from widest to narrowest; the ellipsis is last.
const NAME_STEPS: Array[Vector2i] = [Vector2i(14, 100), Vector2i(13, 88), Vector2i(12, 76)]
## Text room on a tile in a 3-column grid at 360 px.
const NAME_ROOM := 88.0
const TILE_RADIUS := 18
const TILE_HEIGHT := 100.0
const TRACK_HEIGHT := 60.0
const PREVIEW_ICON := 18
const RING := 3

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
var _playing := false
## [left, top, right, bottom] padding of this card.
var _pad: Array[int] = []


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
	_pad.assign(TRACK_PAD if across else [PAD, PAD, PAD, TILE_PAD_BOTTOM])
	_box = HBoxContainer.new() if across else VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.offset_left = _pad[0]
	_box.offset_top = _pad[1]
	_box.offset_right = -_pad[2]
	_box.offset_bottom = -_pad[3]
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", UiTokens.SPACE_3 if across else 3)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_box)
	_icon = _small_icon(COIN_ICON, 14, Color.WHITE)
	_thumb.world = backdrop
	_thumb.outlined = false
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
		Catalog.CRASH:
			_thumb.crash = Catalog.crash(p_id)
			# Pieces fly wide: keep them inside the picture.
			_thumb.clip_contents = true
		Catalog.PLATE:
			_thumb.plate = Catalog.plate(p_id)
	match layout:
		Layout.TRACK:
			_build_track()
		_:
			_build_tile(thumb_height)


static func _fit_name(label: Label, room: float) -> void:
	for step in NAME_STEPS:
		var font := GameFonts.wide(800, step.y)
		if font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, step.x).x <= room:
			if step != NAME_STEPS[0]:
				label.add_theme_font_override("font", font)
				label.add_theme_font_size_override("font_size", step.x)
			return
	var last := NAME_STEPS[NAME_STEPS.size() - 1]
	label.add_theme_font_override("font", GameFonts.wide(800, last.y))
	label.add_theme_font_size_override("font_size", last.x)


func _build_tile(thumb_height: float) -> void:
	var wide := THUMB_WIDTH if kind == Catalog.FLYER else ROOM_THUMB_WIDTH
	var high := thumb_height if kind == Catalog.FLYER else thumb_height + 18.0
	_thumb.custom_minimum_size = Vector2(wide, high)
	_thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_thumb)
	_name.theme_type_variation = &"SmallNameLabel"
	_name.text = ItemChip.short_name(kind, item_id)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_fit_name(_name, NAME_ROOM)
	_box.add_child(_name)
	_status.alignment = BoxContainer.ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_constant_override("separation", 4)
	_status.custom_minimum_size = Vector2(0, 22)
	_box.add_child(_status)
	_build_status()
	custom_minimum_size = Vector2(0, TILE_HEIGHT)


## The "In use" pill, the coin (or lock) and the Owned / Free / price text.
func _build_status() -> void:
	_use.theme_type_variation = &"UsePill"
	_use.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var use_row := HBoxContainer.new()
	use_row.add_theme_constant_override("separation", 3)
	use_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	use_row.add_child(_small_icon(CHECK_ICON, 11, UiTokens.ON_PRIMARY))
	var use_text := Label.new()
	use_text.theme_type_variation = &"OnInkLabel"
	use_text.text = "In use"
	use_row.add_child(use_text)
	_use.add_child(use_row)
	_status.add_child(_use)
	_status.add_child(_icon)
	_meta.theme_type_variation = &"StatusLabel"
	_meta.add_theme_font_size_override("font_size", 13)
	_status.add_child(_meta)


func _build_track() -> void:
	if item_id == MusicTrack.SHUFFLE:
		# No preview: it's a different track every run.
		var disc := PanelContainer.new()
		disc.add_theme_stylebox_override(
			"panel", UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
		)
		disc.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(_small_icon(SHUFFLE_ICON, 20, UiTokens.INK_LINE))
		_box.add_child(disc)
	else:
		_preview.icon = PLAY_ICON
		_preview.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
		_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_preview.focus_mode = Control.FOCUS_NONE
		_preview.tooltip_text = "Play a preview"
		_preview.add_theme_constant_override("icon_max_width", PREVIEW_ICON)
		_preview.pressed.connect(func() -> void: preview_pressed.emit(item_id))
		_style_preview()
		_box.add_child(_preview)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.theme_type_variation = &"SmallNameLabel"
	_name.add_theme_font_size_override("font_size", 15)
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
	_status.add_theme_constant_override("separation", 4)
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


## Music cards: shows the stop icon (white on ink) while this card's preview plays.
func set_playing(on: bool) -> void:
	_playing = on
	_preview.icon = STOP_ICON if on else PLAY_ICON
	_preview.tooltip_text = "Stop the preview" if on else "Play a preview"
	_style_preview()


func is_playing() -> bool:
	return _playing


## The round preview button: soft edge and ink icon, or ink and white icon.
func _style_preview() -> void:
	var fill := UiTokens.INK_LINE if _playing else UiTokens.EDGE
	var tint := UiTokens.ON_PRIMARY if _playing else UiTokens.INK_LINE
	var disc := UiTheme.flat(fill, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		_preview.add_theme_stylebox_override(state, disc)
	_preview.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in [
		"icon_normal_color",
		"icon_hover_color",
		"icon_pressed_color",
		"icon_hover_pressed_color",
		"icon_focus_color"
	]:
		_preview.add_theme_color_override(state, tint)


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
	var floor_h := TRACK_HEIGHT if layout == Layout.TRACK else TILE_HEIGHT
	custom_minimum_size = Vector2(
		maxf(content.x + _pad[0] + _pad[2], UiTokens.SIZE_TAP_MIN),
		maxf(content.y + _pad[1] + _pad[3], floor_h)
	)


## Updates the picture, the status line and the card from the profile.
func refresh(profile: Profile, selected: bool) -> void:
	button_pressed = selected
	var owned := profile.owns(kind, item_id)
	var in_use := profile.equipped_id(kind) == item_id
	# Premium items show their diamond price, the rest their gold price.
	var gems := Shop.diamond_price(kind, item_id)
	var cost := Shop.cost(kind, item_id)
	var short := not owned and not Shop.can_afford(profile, kind, item_id)
	# Faded only while the player can't afford it; the price still shows.
	_thumb.dimmed = layout == Layout.TILE and short
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
		_icon.texture = LOCK_ICON if short else (DIAMOND_ICON if gems > 0 else COIN_ICON)
		_icon.modulate = UiTokens.INK_LINE if short else Color.WHITE
	_set_look(selected, in_use)


## Flat paper; raised while tapped; an ink ring inside while in use.
func _set_look(selected: bool, in_use: bool) -> void:
	var fill := UiTheme.SELECTED_FILL if selected else UiTokens.PANEL
	var radius := UiTokens.RADIUS_PILL if layout == Layout.TRACK else TILE_RADIUS
	var box: StyleBoxFlat
	if in_use:
		box = UiTheme.ringed(fill, radius, 0, UiTokens.INK_LINE, RING)
	else:
		box = UiTheme.flat(fill, radius, 0)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, box)


## The text of the status line, for tests.
func status_text() -> String:
	return _meta.text


## True while the card has the tapped (raised) fill, for tests.
func is_selected_look() -> bool:
	var box := get_theme_stylebox("normal") as StyleBoxFlat
	return box != null and box.bg_color != UiTokens.PANEL


## True while the card shows the "In use" ring, for tests.
func is_in_use_look() -> bool:
	var box := get_theme_stylebox("normal") as StyleBoxFlat
	return box != null and box.border_width_top > 0
