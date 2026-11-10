class_name LookCard
extends Button
## One kind on the "Your look" overview: a flat paper card with a picture of
## the item in use, the kind ("Trail"), the item's name and how many of that
## kind the player owns ("3 of 20"). Tapping it opens that kind's list.
## The name plate's card is `wide`: the words first, then the plate as a
## sample row across the rest.

const PICTURE := 56.0
const HEIGHT := 88.0
const WIDE_HEIGHT := 72.0
const PAD := 8
const RADIUS := 18
const NAME_MIN := 70.0
## What each kind is called on its card.
const LABELS := {
	Catalog.FLYER: "Flyer",
	Catalog.WORLD: "World",
	Catalog.TRAIL: "Trail",
	Catalog.PORTAL: "Portal",
	Catalog.MUSIC: "Music",
	Catalog.CRASH: "Crash",
	Catalog.PLATE: "Name plate",
}

var kind := ""
var wide := false

var _row := HBoxContainer.new()
var _thumb := ItemThumb.new()
var _name := Label.new()
var _count := Label.new()


func _init(p_kind: String, profile: Profile, world: ThemeDef, p_wide: bool = false) -> void:
	kind = p_kind
	wide = p_wide
	theme_type_variation = &"CardButton"
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = "Change %s" % label_for(kind).to_lower()
	for state in ["normal", "hover"]:
		add_theme_stylebox_override(state, UiTheme.flat(UiTokens.PANEL, RADIUS, 0))
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, UiTheme.flat(UiTheme.SELECTED_FILL, RADIUS, 0))
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = PAD + (4 if wide else 0)
	_row.offset_top = PAD
	_row.offset_right = -PAD
	_row.offset_bottom = -PAD
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", UiTokens.SPACE_3 if wide else UiTokens.SPACE_2)
	add_child(_row)
	var id := profile.equipped_id(kind)
	_thumb.world = world
	_thumb.outlined = false
	_thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_thumb.custom_minimum_size = Vector2(PICTURE, PICTURE)
	_fill_thumb(id, profile)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var what := Label.new()
	what.theme_type_variation = &"MutedLabel"
	what.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	what.text = label_for(kind)
	text.add_child(what)
	_name.theme_type_variation = &"SmallNameLabel"
	_name.add_theme_font_size_override("font_size", 15)
	_name.text = ItemChip.short_name(kind, id) if not id.is_empty() else "None"
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(NAME_MIN, 0)
	text.add_child(_name)
	_count.theme_type_variation = &"MutedLabel"
	_count.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	_count.text = count_text(kind, profile)
	text.add_child(_count)
	if wide:
		# Words first, then the plate across the rest of the card.
		text.custom_minimum_size = Vector2(96, 0)
		_thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row.add_child(text)
		_row.add_child(_thumb)
	else:
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row.add_child(_thumb)
		_row.add_child(text)
	custom_minimum_size = Vector2(0, WIDE_HEIGHT if wide else HEIGHT)


## The picture of the item in use, per kind (as ItemCard draws them).
func _fill_thumb(id: String, profile: Profile) -> void:
	match kind:
		Catalog.FLYER:
			var f := Catalog.flyer(id)
			_thumb.flyer = f.idle if f != null else null
			_thumb.bare = true
		Catalog.WORLD:
			var w := Catalog.world(id)
			if w != null:
				_thumb.world = w
		Catalog.TRAIL:
			_thumb.trail = Catalog.trail(id)
		Catalog.PORTAL:
			_thumb.portal = Catalog.portal(id)
		Catalog.MUSIC:
			_thumb.music = id
		Catalog.CRASH:
			_thumb.crash = Catalog.crash(id)
			_thumb.clip_contents = true
		Catalog.PLATE:
			_thumb.plate = Catalog.plate(id)
			var mine := Catalog.flyer(profile.equipped_id(Catalog.FLYER))
			_thumb.flyer = mine.idle if mine != null else null


func _ready() -> void:
	# A Button doesn't grow with its children, so size it to its content.
	_row.minimum_size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var content := _row.get_combined_minimum_size()
	custom_minimum_size = Vector2(
		content.x + PAD * 2, maxf(WIDE_HEIGHT if wide else HEIGHT, content.y + PAD * 2)
	)


static func label_for(p_kind: String) -> String:
	return str(LABELS.get(p_kind, p_kind.capitalize()))


## "3 of 20": how many items of a kind the player owns, out of all of them.
static func count_text(p_kind: String, profile: Profile) -> String:
	var ids := Catalog.ids(p_kind)
	var owned := 0
	for id in ids:
		if profile.owns(p_kind, id):
			owned += 1
	return "%d of %d" % [owned, ids.size()]


## The item's name on the card, for tests.
func name_text() -> String:
	return _name.text


## The "3 of 20" line, for tests.
func count_line() -> String:
	return _count.text
