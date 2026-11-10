class_name CrashStyle
extends Resource
## What the flyer bursts into when a run ends. Cosmetic only: it plays after
## the sim has ended the run and never reads or changes it, so every style
## plays the same game. Flat shapes, no flash (fine with Reduced flashing).
##
## Adding a style: one row in STYLES below plus a price in Shop.PRICES. A new
## `kind` also needs its draw function in CrashPainter.
##
## The room plays the equipped one through CrashView; the shop cards and popup
## draw one moment of it (thumb_time) with CrashPainter.

## The free default.
const DEFAULT_ID := "feather_puff"
## Kinds CrashPainter knows. A kind is a string so new ones need no enum change.
const BURST := "burst"
const SPLAT := "splat"
const RAYS := "rays"
const POW := "pow"
const ORBIT := "orbit"
const BUBBLE := "bubble"
const GHOST := "ghost"
## What a BURST throws.
const FEATHER := "feather"
const CONFETTI := "confetti"
const SHARD := "shard"
const PIXEL := "pixel"
## Seconds a style that ends takes; the rest stay until the next run.
const DURATIONS := {BURST: 1.4, RAYS: 1.3, POW: 1.3, GHOST: 1.8}
## The moment the shop pictures show.
const THUMB_TIMES := {BURST: 0.3, SPLAT: 1.0, RAYS: 0.38, POW: 0.4, GHOST: 0.9}

## id, name, kind, burst piece, colours, pieces, hides the flyer, drawn in front
## of the flyer, blurb.
const STYLES := [
	[
		DEFAULT_ID,
		"Feather Puff",
		BURST,
		FEATHER,
		["FFFFFF"],
		9,
		false,
		true,
		"A puff where it hit; feathers rock slowly down."
	],
	[
		"confetti_pop",
		"Confetti Pop",
		BURST,
		CONFETTI,
		["5CC8FF", "FFB020", "8A6AD0", "3FD9A3", "FF5E7A"],
		20,
		false,
		true,
		"Strips, dots and triangles shoot across the room."
	],
	[
		"bubble_trap",
		"Bubble Trap",
		BUBBLE,
		"",
		["FFFFFF"],
		4,
		false,
		true,
		"A bubble closes round the flyer; small ones rise."
	],
	[
		"dizzy_stars",
		"Dizzy Stars",
		ORBIT,
		"",
		["FFE45C", "FFFFFF"],
		3,
		false,
		true,
		"Stars circle the flyer's head."
	],
	[
		"shatter",
		"Shatter",
		BURST,
		SHARD,
		["2E64D9", "4C82F0", "F2F5FA", "FFB020"],
		12,
		true,
		true,
		"The flyer breaks into shards in its own colours."
	],
	[
		"pixel_dissolve",
		"Pixel Dissolve",
		BURST,
		PIXEL,
		["00E5FF", "7DF9FF", "FFC928"],
		18,
		true,
		true,
		"The flyer crumbles into blocks that shrink away."
	],
	[
		"paint_splat",
		"Paint Splat",
		SPLAT,
		"",
		["FF5FA2"],
		6,
		false,
		false,
		"A pink splat that drips; drops fly off."
	],
	[
		"comic_pow",
		"Comic Pow",
		POW,
		"",
		["FFE45C", "FFFFFF"],
		12,
		false,
		false,
		"A flat comic burst pops behind the flyer."
	],
	[
		"firework",
		"Firework",
		RAYS,
		"",
		["FF5E7A", "FFE45C", "5FD3A8", "5CC8FF", "B69CFF"],
		12,
		true,
		true,
		"The flyer goes up as a twelve-ray firework."
	],
	[
		"little_ghost",
		"Little Ghost",
		GHOST,
		"",
		["FFFFFF", "FFC93C"],
		1,
		false,
		true,
		"A ghost with a halo floats up out of the flyer."
	],
]

## Stable id, kept in saves: never rename a shipped one.
@export var id := DEFAULT_ID
@export var display_name := "Feather Puff"
## Which CrashPainter draw function draws it.
@export var kind := BURST
## What a BURST throws (FEATHER, CONFETTI, SHARD, PIXEL).
@export var piece := FEATHER
@export var colors := PackedColorArray()
## Pieces, rays, stars or small bubbles.
@export var count := 9
## The flyer fades out as the effect starts (it became the pieces).
@export var hides_flyer := false
## Drawn over the flyer; the others sit behind it.
@export var in_front := true
## One line for the shop popup.
@export var blurb := ""


## Every style, in display order (Catalog.crashes()).
static func all() -> Array[CrashStyle]:
	var out: Array[CrashStyle] = []
	for row: Array in STYLES:
		var c := CrashStyle.new()
		c.id = row[0]
		c.display_name = row[1]
		c.kind = row[2]
		c.piece = row[3]
		for hex: String in row[4]:
			c.colors.append(Color(hex))
		c.count = row[5]
		c.hides_flyer = row[6]
		c.in_front = row[7]
		c.blurb = row[8]
		out.append(c)
	return out


## The style a player has in use; the default when the save names none we know.
static func equipped(profile: Profile) -> CrashStyle:
	var c := Catalog.crash(profile.equipped_id(Catalog.CRASH)) if profile != null else null
	return c if c != null else Catalog.crash(DEFAULT_ID)


## True for styles that stay until the next run (a bubble, circling stars, a splat).
func loops() -> bool:
	return not DURATIONS.has(kind)


## Seconds until it is over; 0 for the ones that stay.
func duration() -> float:
	return float(DURATIONS.get(kind, 0.0))


## The moment the shop pictures show.
func thumb_time() -> float:
	return float(THUMB_TIMES.get(kind, 0.6))
