class_name LookPreview
extends VBoxContainer
## The preview at the top of a Customize list, on the room: the items in use
## with the tapped one swapped in. The flyer stands on the room with its puffs;
## Trails show the flyer leading its trail, Portals the exit on the right wall,
## Crashes the effect round the flyer, Plates a sample leaderboard row (a
## tapped world is shown by the room itself). A line under it names the item
## ("Buzz, in use").

## The flyer standing on the room: its body, and the stage it stands on.
const BODY := 52.0
const HEIGHT := 84.0

var _stage := Control.new()
var _flyer := FlyerArt.new(null, BODY)
var _picture := ItemThumb.new()
var _caption := Label.new()
var _portal: PortalStyle
## The id shown per kind (the tapped one for the list's kind), for tests.
var _shown: Dictionary[String, String] = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	_stage.custom_minimum_size = Vector2(0, HEIGHT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.open = true
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_picture)
	_stage.add_child(_flyer)
	_flyer.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_flyer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flyer.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_stage)
	_caption.theme_type_variation = &"SkyCaption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)


## Shows the player's look with `selected` (of the list's `kind`) swapped in;
## "" shows just what is in use.
func show_look(profile: Profile, kind: String, selected: String) -> void:
	for k in ItemKind.ALL:
		_shown[k] = selected if k == kind and not selected.is_empty() else profile.equipped_id(k)
	var w := Catalog.world(_shown[ItemKind.WORLD])
	var f := Catalog.flyer_art(_shown[ItemKind.FLYER])
	var p := Catalog.portal(_shown[ItemKind.PORTAL])
	_portal = p if p != null else Catalog.portal(PortalStyle.DEFAULT_ID)
	_flyer.texture = f
	_picture.world = w if w != null else ThemeCatalog.default_theme()
	_picture.flyer = null
	_picture.trail = null
	_picture.portal = null
	_picture.crash = null
	_picture.plate = null
	match kind:
		ItemKind.TRAIL:
			var t := Catalog.trail(_shown[ItemKind.TRAIL])
			_picture.trail = t if t != null else TrailStyle.world_ribbon()
			_picture.flyer = f
		ItemKind.PORTAL:
			_picture.portal = _portal
		ItemKind.CRASH:
			# The picture draws the flyer itself, under or over the effect.
			_picture.crash = Catalog.crash(_shown[ItemKind.CRASH])
			_picture.flyer = f
		ItemKind.PLATE:
			_picture.plate = Catalog.plate(_shown[ItemKind.PLATE])
			_picture.flyer = f
	_flyer.visible = kind not in [ItemKind.TRAIL, ItemKind.CRASH, ItemKind.PLATE]
	# Music rows need the room: no preview there.
	visible = kind != ItemKind.MUSIC
	_caption.text = caption(profile, kind, selected)


## "Buzz, in use" for the item in use, else the tapped item's short name.
static func caption(profile: Profile, kind: String, selected: String) -> String:
	if selected.is_empty():
		return ""
	var item := ItemChip.short_name(kind, selected)
	return item + ", in use" if profile.equipped_id(kind) == selected else item


func caption_text() -> String:
	return _caption.text


## The id shown for `kind`, for tests.
func shown_id(kind: String) -> String:
	return _shown.get(kind, "")


func portal_id() -> String:
	return _portal.id if _portal != null else ""
