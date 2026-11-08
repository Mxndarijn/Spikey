class_name PortalStyle
extends Resource
## How exit portals look. Cosmetic only: the exit's size and position come from
## sim/ and never from here, so every style plays the same.
##
## Adding a style: one factory below plus its line in Catalog.portals() and a
## price in Shop.PRICES, and one draw function in PortalPainter for a new `kind`.
##
## The room draws the equipped portal with draw_portal(); the shop cards and
## popup draw it with draw_thumb().

const DEFAULT_ID := "cloud_hole"
## Kinds PortalPainter knows. A kind is a string so new ones need no enum change.
const CLOUD := "cloud"
const SPLAT := "splat"
const FEATHERS := "feathers"
const CRACK := "crack"
const RIPPLE := "ripple"

## Stable id, kept in saves: never rename a shipped one.
@export var id := DEFAULT_ID
@export var display_name := "Cloud Hole"
## Which PortalPainter draw function draws it.
@export var kind := CLOUD
## One line for the shop popup.
@export var blurb := ""
## Take the colour from the world's accent token (normal exits). Off: `color`.
@export var use_world_color := true
@export var color := Color.WHITE


static func _make(p_id: String, p_name: String, p_kind: String, p_blurb: String) -> PortalStyle:
	var p := PortalStyle.new()
	p.id = p_id
	p.display_name = p_name
	p.kind = p_kind
	p.blurb = p_blurb
	return p


## The free default.
static func cloud_hole() -> PortalStyle:
	return _make(
		DEFAULT_ID, "Cloud Hole", CLOUD, "Puffy clouds round a hole of deep sky with stars."
	)


static func ink_splat() -> PortalStyle:
	return _make("ink_splat", "Ink Splat", SPLAT, "A wobbly ink blot with a glowing middle.")


static func feather_ring() -> PortalStyle:
	return _make("feather_ring", "Feather Ring", FEATHERS, "A wreath of feathers turning round.")


static func breakout_crack() -> PortalStyle:
	return _make(
		"breakout_crack", "Breakout Crack", CRACK, "The wall cracks open and light blasts through."
	)


static func ripple_mirror() -> PortalStyle:
	return _make("ripple_mirror", "Ripple Mirror", RIPPLE, "A pool of light with rippling rings.")


## The style a player has in use; Classic when the save names none we know.
static func equipped(profile: Profile) -> PortalStyle:
	var p := Catalog.portal(profile.equipped_portal()) if profile != null else null
	return p if p != null else Catalog.portal(DEFAULT_ID)


## The colour of a normal exit in a world.
func tint(theme: ThemeDef) -> Color:
	if use_world_color and theme != null:
		return theme.world_accent
	return color


## Draws one exit portal; call from the canvas item's _draw().
## `center`: the portal's centre in the canvas's coordinates. `half_height`:
## half the exit's height in px (the sim's exit size). `side`: the wall it is
## on, 0 left or 1 right (like SimState.exit_side). `open_amount`: 0 closed to
## 1 open (may overshoot a little while opening). `time`: seconds, for spin
## and sparks. `color_override`: Calm and Wild exits pass their own colour;
## leave it clear for a normal exit in the world's colour.
func draw_portal(
	canvas: CanvasItem,
	center: Vector2,
	half_height: float,
	side: int,
	open_amount: float,
	time: float,
	theme: ThemeDef,
	color_override: Color = Color(0, 0, 0, 0)
) -> void:
	var c := color_override if color_override.a > 0.0 else tint(theme)
	PortalPainter.paint(canvas, self, center, half_height, side, open_amount, time, c)


## The shop picture: the portal open on the right wall of a mini room `rect`
## (the room itself is drawn by the caller). Returns the portal's centre.
func draw_thumb(canvas: CanvasItem, rect: Rect2, theme: ThemeDef, alpha: float = 1.0) -> Vector2:
	var half := rect.size.y * PortalPainter.THUMB_HEIGHT
	var center := Vector2(
		rect.end.x - PortalPainter.THUMB_INSET - half * PortalPainter.RX_RATIO * 0.5,
		rect.position.y + rect.size.y * 0.5
	)
	PortalPainter.paint(
		canvas, self, center, half, 1, 1.0, PortalPainter.THUMB_TIME, tint(theme), alpha
	)
	return center
