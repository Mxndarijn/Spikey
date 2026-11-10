class_name PortalStyle
extends Resource
## How exit portals look. Cosmetic only: the exit's size and position come from
## sim/ and never from here, so every style plays the same. Every style is the
## same flat spinning vortex disc set against the wall; only the drawing inside
## it changes.
##
## Adding a style: one line in STYLES below plus a price in Shop.PRICES. A new
## `kind` also needs its draw function in PortalPainter.
##
## The room draws the equipped portal with draw_portal(); the shop cards and
## popup draw it with draw_thumb().

## "Match my world": the free default, the world's own vortex.
const DEFAULT_ID := ItemKind.DEFAULT_PORTAL
## Kinds PortalPainter knows. A kind is a string so new ones need no enum change.
const SPIRAL := "spiral"
const DOTS := "dots"
const RINGS := "rings"
const GALAXY := "galaxy"
const PIXEL := "pixel"

## One entry per style, in display order; the keys are the fields below
## ("name" is display_name, colours as hex strings).
## Match my world takes its colours from the world instead (follows_world).
const STYLES: Array[Dictionary] = [
	{
		"id": DEFAULT_ID,
		"name": "Match my world",
		"kind": SPIRAL,
		"base": "",
		"rim": "",
		"arms": [],
		"arm_count": 4,
		"arm_width": 9.0,
		"blurb": "The world's own vortex, with a touch of the world on its rim."
	},
	{
		"id": "classic_spiral",
		"name": "Classic Spiral",
		"kind": SPIRAL,
		"base": "3A2A6E",
		"rim": "6B5BC8",
		"arms": ["FFFFFF", "C9C2F2"],
		"arm_count": 4,
		"arm_width": 9.0,
		"blurb": "Four white arms round a deep purple eye."
	},
	{
		"id": "candy_swirl",
		"name": "Candy Swirl",
		"kind": SPIRAL,
		"base": "FF8FC0",
		"rim": "FFFFFF",
		"arms": ["FFFFFF", "FF5A9A"],
		"arm_count": 2,
		"arm_width": 18.0,
		"blurb": "A fat pink and white lollipop swirl."
	},
	{
		"id": "mint_breeze",
		"name": "Mint Breeze",
		"kind": SPIRAL,
		"base": "2E8F74",
		"rim": "B8F2DC",
		"arms": ["B8F2DC", "5FD3A8", "E6FBF2"],
		"arm_count": 3,
		"arm_width": 10.0,
		"blurb": "Cool mint arms on a deep green disc."
	},
	{
		"id": "dotted",
		"name": "Dotted",
		"kind": DOTS,
		"base": "2A1C66",
		"rim": "7A6BD6",
		"arms": ["FFD23F", "FFFFFF"],
		"arm_count": 4,
		"arm_width": 0.0,
		"blurb": "Spirals of gold and white dots."
	},
	{
		"id": "ripple",
		"name": "Ripple",
		"kind": RINGS,
		"base": "1A7FB0",
		"rim": "8EEDE4",
		"arms": ["E0FBFF", "6EE7E0"],
		"arm_count": 4,
		"arm_width": 5.0,
		"blurb": "Broken rings of water turning round."
	},
	{
		"id": "galaxy",
		"name": "Galaxy",
		"kind": GALAXY,
		"base": "120A33",
		"rim": "4B37A8",
		"arms": ["7A6BD6", "B69CFF"],
		"arm_count": 2,
		"arm_width": 14.0,
		"blurb": "A starry spiral galaxy."
	},
	{
		"id": "ink_swirl",
		"name": "Ink Swirl",
		"kind": SPIRAL,
		"base": "FFF5EC",
		"rim": "1E1B2E",
		"arms": ["1E1B2E"],
		"arm_count": 3,
		"arm_width": 10.0,
		"blurb": "Black ink swirling on paper."
	},
	{
		"id": "rainbow",
		"name": "Rainbow",
		"kind": SPIRAL,
		"base": "33204F",
		"rim": "FFFFFF",
		"arms": ["FF5A5A", "FFC93C", "5FD3A8", "5CB8FF", "B69CFF", "FF8FC0"],
		"arm_count": 6,
		"arm_width": 7.0,
		"blurb": "Six arms, every colour."
	},
	{
		"id": "flame",
		"name": "Flame",
		"kind": SPIRAL,
		"base": "5A2024",
		"rim": "FFA94D",
		"arms": ["FFD27A", "FF7A2F"],
		"arm_count": 3,
		"arm_width": 12.0,
		"blurb": "A swirl of fire with a smoky middle."
	},
	{
		"id": "pixel",
		"name": "Pixel",
		"kind": PIXEL,
		"base": "17123A",
		"rim": "7DE2FF",
		"arms": ["7DE2FF", "FF6BDD"],
		"arm_count": 2,
		"arm_width": 0.0,
		"blurb": "A blocky arcade swirl."
	},
	{
		"id": "golden",
		"name": "Golden",
		"kind": SPIRAL,
		"base": "13283A",
		"rim": "FFC93C",
		"arms": ["FFC93C", "FFE7A0"],
		"arm_count": 4,
		"arm_width": 9.0,
		"blurb": "Gold arms on a midnight disc."
	},
]

## Stable id, kept in saves: never rename a shipped one.
@export var id := DEFAULT_ID
@export var display_name := "Match my world"
## Which PortalPainter draw function draws the inside of the disc.
@export var kind := SPIRAL
## One line for the shop popup.
@export var blurb := ""
## Colours from the world (and its rim touch) instead of the ones below.
@export var follows_world := true
@export var base := Color.BLACK
@export var rim := Color.WHITE
@export var arms: Array[Color] = []
@export var arm_count := 4
## Arm stroke width in disc units (PortalPen.OUTER is the disc's radius).
@export var arm_width := 9.0


## Every style, in display order (Catalog.portals()).
static func all() -> Array[PortalStyle]:
	var out: Array[PortalStyle] = []
	for row: Dictionary in STYLES:
		var p := PortalStyle.new()
		p.id = row.id
		p.display_name = row.name
		p.kind = row.kind
		p.follows_world = p.id == DEFAULT_ID
		if not p.follows_world:
			p.base = Color(row.base)
			p.rim = Color(row.rim)
			for hex: String in row.arms:
				p.arms.append(Color(hex))
		p.arm_count = row.arm_count
		p.arm_width = row.arm_width
		p.blurb = row.blurb
		out.append(p)
	return out


## The free default (Match my world).
static func match_world() -> PortalStyle:
	return all()[0]


## The style a player has in use; Match my world when the save names none we know.
static func equipped(profile: Profile) -> PortalStyle:
	var p := Catalog.portal(profile.equipped_id(ItemKind.PORTAL)) if profile != null else null
	return p if p != null else Catalog.portal(DEFAULT_ID)


## The colours this style draws with in a world: "base" (the disc), "rim",
## "eye" (the dark middle), "arms" (Array[Color]) and "touch" (Array[Color],
## the world's rim touch; empty for fixed styles). `override` (Calm mint, Wild
## gold) recolours the arms; leave it clear for a normal exit.
func colors(theme: ThemeDef, override: Color = Color(0, 0, 0, 0)) -> Dictionary:
	var b := base
	var r := rim
	var a: Array[Color] = arms.duplicate()
	var touch: Array[Color] = []
	if follows_world and theme != null:
		# The far end of the sky stands in for the far hills; mixed toward the
		# spike colour for a dark disc, never the spike colour itself.
		var far := theme.sky_bottom
		b = far.lerp(theme.spike, 0.45)
		r = far.lerp(theme.sky_top, 0.3)
		a = [theme.sky_top, theme.sky_mid, theme.sky_top.lerp(Color.WHITE, 0.4), theme.world_accent]
		touch = PortalPainter.touch_colors(theme)
	if override.a > 0.0:
		var o := Color(override, 1.0)
		a = [
			o.lerp(Color.WHITE, 0.15),
			o.lerp(Color.WHITE, 0.6),
			o.darkened(0.12),
			o.lerp(Color.WHITE, 0.85)
		]
	if a.is_empty():
		a = [Color.WHITE]
	return {
		"base": b,
		"rim": r,
		"eye": b.lerp(Color.BLACK, 0.35 if follows_world else 0.4),
		"arms": a,
		"touch": touch,
	}


## Draws one exit portal; call from the canvas item's _draw().
## `center`: where RoomView puts the exit (PortalPainter.EXIT_CENTER_DEPTH px
## from the wall); the disc itself sits PortalPainter.DISC_DEPTH px from the
## wall. `half_height`: half the exit's height in px (the sim's exit size).
## `side`: the wall it is on, 0 left or 1 right (like SimState.exit_side).
## `open_amount`: 0 closed to 1 open (may overshoot a little while opening).
## `time`: seconds, for the spin. `color_override`: Calm and Wild exits pass
## their colour (it recolours the arms); clear for a normal exit. `alpha`
## fades the whole portal (the ghost of the next exit is drawn faint).
func draw_portal(
	canvas: CanvasItem,
	center: Vector2,
	half_height: float,
	side: int,
	open_amount: float,
	time: float,
	theme: ThemeDef,
	color_override: Color = Color(0, 0, 0, 0),
	alpha: float = 1.0
) -> void:
	var into := 1.0 if side == 0 else -1.0
	var k := half_height / PortalPainter.REF_HALF
	var shift := (PortalPainter.DISC_DEPTH - PortalPainter.EXIT_CENTER_DEPTH) * k
	var disc := center + Vector2(into * shift, 0.0)
	PortalPainter.paint(
		canvas,
		self,
		disc,
		half_height,
		side,
		open_amount,
		time,
		colors(theme, color_override),
		theme,
		alpha
	)


## The shop picture: the portal open on the right wall of a mini room `rect`
## (the room itself is drawn by the caller). Returns the portal's centre.
func draw_thumb(canvas: CanvasItem, rect: Rect2, theme: ThemeDef, alpha: float = 1.0) -> Vector2:
	var half := rect.size.y * PortalPainter.THUMB_HEIGHT
	var k := half / PortalPainter.REF_HALF
	var center := Vector2(
		rect.end.x - PortalPainter.DISC_DEPTH * k, rect.position.y + rect.size.y * 0.5
	)
	PortalPainter.paint(
		canvas, self, center, half, 1, 1.0, PortalPainter.THUMB_TIME, colors(theme), theme, alpha
	)
	return center
