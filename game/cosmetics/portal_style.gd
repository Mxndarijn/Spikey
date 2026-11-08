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
const DEFAULT_ID := "match_world"
## Kinds PortalPainter knows. A kind is a string so new ones need no enum change.
const SPIRAL := "spiral"
const DOTS := "dots"
const RINGS := "rings"
const GALAXY := "galaxy"
const PIXEL := "pixel"

## id, name, kind, base (disc), rim, arm colours, arm count, arm width, blurb.
## Match my world takes its colours from the world instead (follows_world).
const STYLES := [
	[
		DEFAULT_ID,
		"Match my world",
		SPIRAL,
		"",
		"",
		[],
		4,
		9.0,
		"The world's own vortex, with a touch of the world on its rim."
	],
	[
		"classic_spiral",
		"Classic Spiral",
		SPIRAL,
		"3A2A6E",
		"6B5BC8",
		["FFFFFF", "C9C2F2"],
		4,
		9.0,
		"Four white arms round a deep purple eye."
	],
	[
		"candy_swirl",
		"Candy Swirl",
		SPIRAL,
		"FF8FC0",
		"FFFFFF",
		["FFFFFF", "FF5A9A"],
		2,
		18.0,
		"A fat pink and white lollipop swirl."
	],
	[
		"mint_breeze",
		"Mint Breeze",
		SPIRAL,
		"2E8F74",
		"B8F2DC",
		["B8F2DC", "5FD3A8", "E6FBF2"],
		3,
		10.0,
		"Cool mint arms on a deep green disc."
	],
	[
		"dotted",
		"Dotted",
		DOTS,
		"2A1C66",
		"7A6BD6",
		["FFD23F", "FFFFFF"],
		4,
		0.0,
		"Spirals of gold and white dots."
	],
	[
		"ripple",
		"Ripple",
		RINGS,
		"1A7FB0",
		"8EEDE4",
		["E0FBFF", "6EE7E0"],
		4,
		5.0,
		"Broken rings of water turning round."
	],
	[
		"galaxy",
		"Galaxy",
		GALAXY,
		"120A33",
		"4B37A8",
		["7A6BD6", "B69CFF"],
		2,
		14.0,
		"A starry spiral galaxy."
	],
	[
		"ink_swirl",
		"Ink Swirl",
		SPIRAL,
		"FFF5EC",
		"1E1B2E",
		["1E1B2E"],
		3,
		10.0,
		"Black ink swirling on paper."
	],
	[
		"rainbow",
		"Rainbow",
		SPIRAL,
		"33204F",
		"FFFFFF",
		["FF5A5A", "FFC93C", "5FD3A8", "5CB8FF", "B69CFF", "FF8FC0"],
		6,
		7.0,
		"Six arms, every colour."
	],
	[
		"flame",
		"Flame",
		SPIRAL,
		"5A2024",
		"FFA94D",
		["FFD27A", "FF7A2F"],
		3,
		12.0,
		"A swirl of fire with a smoky middle."
	],
	[
		"pixel",
		"Pixel",
		PIXEL,
		"17123A",
		"7DE2FF",
		["7DE2FF", "FF6BDD"],
		2,
		0.0,
		"A blocky arcade swirl."
	],
	[
		"golden",
		"Golden",
		SPIRAL,
		"13283A",
		"FFC93C",
		["FFC93C", "FFE7A0"],
		4,
		9.0,
		"Gold arms on a midnight disc."
	],
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
	for row: Array in STYLES:
		var p := PortalStyle.new()
		p.id = row[0]
		p.display_name = row[1]
		p.kind = row[2]
		p.follows_world = row[0] == DEFAULT_ID
		if not p.follows_world:
			p.base = Color(row[3])
			p.rim = Color(row[4])
			for hex: String in row[5]:
				p.arms.append(Color(hex))
		p.arm_count = row[6]
		p.arm_width = row[7]
		p.blurb = row[8]
		out.append(p)
	return out


## The free default (Match my world).
static func match_world() -> PortalStyle:
	return all()[0]


## The style a player has in use; Match my world when the save names none we know.
static func equipped(profile: Profile) -> PortalStyle:
	var p := Catalog.portal(profile.equipped_portal()) if profile != null else null
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
## their colour (it recolours the arms); clear for a normal exit.
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
		theme
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
