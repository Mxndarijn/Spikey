class_name LookScreen
extends Control
## "Your look": where Customize starts (minimal kit), over the live room. A
## back arrow, the title and the coins; the flyer in use leading its trail;
## then one paper card per cosmetic kind showing what is in use: Flyer, World,
## Trail, Portal, Music and Crash in two columns, and the name plate as a wide
## card under them. Tapping a card opens that kind's list (CollectionScreen);
## its Back comes back here. A new kind is one more entry in GRID_KINDS.

signal closed
## A card was tapped: open that kind's list.
signal kind_pressed(kind: String)

## The cards in the two-column grid, in order; the name plate is the wide card.
const GRID_KINDS: Array[String] = [
	Catalog.FLYER, Catalog.WORLD, Catalog.TRAIL, Catalog.PORTAL, Catalog.MUSIC, Catalog.CRASH
]
const WIDE_KIND := Catalog.PLATE
const TITLE := "Your look"
const SIDE := 14
const GRID_GAP := 10
const STAGE_HEIGHT := 84.0

var _profile: Profile
var _coins := CoinPill.new()
## kind -> LookCard
var _cards := {}


func _init(profile: Profile) -> void:
	_profile = profile


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6 + 4)
	# Keeps the cards above the floor spikes.
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_7)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_2)
	margin.add_child(col)
	_coins.set_amount(_profile.coins)
	col.add_child(UiKit.header(TITLE, closed.emit, _coins))

	var world := Catalog.world(_profile.equipped_id(Catalog.WORLD))
	if world == null:
		world = ThemeCatalog.default_theme()
	# The flyer leading its trail, straight on the room.
	var stage := ItemThumb.new()
	stage.open = true
	stage.world = world
	var flyer := Catalog.flyer(_profile.equipped_id(Catalog.FLYER))
	stage.flyer = flyer.idle if flyer != null else null
	var trail := Catalog.trail(_profile.equipped_id(Catalog.TRAIL))
	stage.trail = trail if trail != null else TrailStyle.world_ribbon()
	stage.custom_minimum_size = Vector2(0, STAGE_HEIGHT)
	col.add_child(stage)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	for k in GRID_KINDS:
		grid.add_child(_card(k, world, false))
	col.add_child(grid)
	col.add_child(_card(WIDE_KIND, world, true))


## Free the coin pill if the screen never joined the tree, or it leaks.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_coins) and _coins.get_parent() == null:
		_coins.free()


func _card(k: String, world: ThemeDef, wide: bool) -> LookCard:
	var c := LookCard.new(k, _profile, world, wide)
	c.pressed.connect(func() -> void: kind_pressed.emit(k))
	_cards[k] = c
	return c


## Every kind that has a card, in the order shown.
func kinds() -> Array[String]:
	var out: Array[String] = []
	out.append_array(GRID_KINDS)
	out.append(WIDE_KIND)
	return out


## A kind's card, or null (for tests).
func card(k: String) -> LookCard:
	return _cards.get(k) as LookCard
