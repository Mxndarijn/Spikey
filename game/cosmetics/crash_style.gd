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
const DEFAULT_ID := ItemKind.DEFAULT_CRASH
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

## One entry per style, in display order; the keys are the fields below
## ("name" is display_name, "colors" hex strings).
const STYLES: Array[Dictionary] = [
	{
		"id": DEFAULT_ID,
		"name": "Feather Puff",
		"kind": BURST,
		"piece": FEATHER,
		"colors": ["FFFFFF"],
		"count": 9,
		"hides_flyer": false,
		"in_front": true,
		"blurb": "A puff where it hit; feathers rock slowly down."
	},
	{
		"id": "confetti_pop",
		"name": "Confetti Pop",
		"kind": BURST,
		"piece": CONFETTI,
		"colors": ["5CC8FF", "FFB020", "8A6AD0", "3FD9A3", "FF5E7A"],
		"count": 20,
		"hides_flyer": false,
		"in_front": true,
		"blurb": "Strips, dots and triangles shoot across the room."
	},
	{
		"id": "bubble_trap",
		"name": "Bubble Trap",
		"kind": BUBBLE,
		"piece": "",
		"colors": ["FFFFFF"],
		"count": 4,
		"hides_flyer": false,
		"in_front": true,
		"blurb": "A bubble closes round the flyer; small ones rise."
	},
	{
		"id": "dizzy_stars",
		"name": "Dizzy Stars",
		"kind": ORBIT,
		"piece": "",
		"colors": ["FFE45C", "FFFFFF"],
		"count": 3,
		"hides_flyer": false,
		"in_front": true,
		"blurb": "Stars circle the flyer's head."
	},
	{
		"id": "shatter",
		"name": "Shatter",
		"kind": BURST,
		"piece": SHARD,
		"colors": ["2E64D9", "4C82F0", "F2F5FA", "FFB020"],
		"count": 12,
		"hides_flyer": true,
		"in_front": true,
		"blurb": "The flyer breaks into shards in its own colours."
	},
	{
		"id": "pixel_dissolve",
		"name": "Pixel Dissolve",
		"kind": BURST,
		"piece": PIXEL,
		"colors": ["00E5FF", "7DF9FF", "FFC928"],
		"count": 18,
		"hides_flyer": true,
		"in_front": true,
		"blurb": "The flyer crumbles into blocks that shrink away."
	},
	{
		"id": "paint_splat",
		"name": "Paint Splat",
		"kind": SPLAT,
		"piece": "",
		"colors": ["FF5FA2"],
		"count": 6,
		"hides_flyer": false,
		"in_front": false,
		"blurb": "A pink splat that drips; drops fly off."
	},
	{
		"id": "comic_pow",
		"name": "Comic Pow",
		"kind": POW,
		"piece": "",
		"colors": ["FFE45C", "FFFFFF"],
		"count": 12,
		"hides_flyer": false,
		"in_front": false,
		"blurb": "A flat comic burst pops behind the flyer."
	},
	{
		"id": "firework",
		"name": "Firework",
		"kind": RAYS,
		"piece": "",
		"colors": ["FF5E7A", "FFE45C", "5FD3A8", "5CC8FF", "B69CFF"],
		"count": 12,
		"hides_flyer": true,
		"in_front": true,
		"blurb": "The flyer goes up as a twelve-ray firework."
	},
	{
		"id": "little_ghost",
		"name": "Little Ghost",
		"kind": GHOST,
		"piece": "",
		"colors": ["FFFFFF", "FFC93C"],
		"count": 1,
		"hides_flyer": false,
		"in_front": true,
		"blurb": "A ghost with a halo floats up out of the flyer."
	},
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
	for row: Dictionary in STYLES:
		var c := CrashStyle.new()
		c.id = row.id
		c.display_name = row.name
		c.kind = row.kind
		c.piece = row.piece
		for hex: String in row.colors:
			c.colors.append(Color(hex))
		c.count = row.count
		c.hides_flyer = row.hides_flyer
		c.in_front = row.in_front
		c.blurb = row.blurb
		out.append(c)
	return out


## The style a player has in use; the default when the save names none we know.
static func equipped(profile: Profile) -> CrashStyle:
	var c := Catalog.crash(profile.equipped_id(ItemKind.CRASH)) if profile != null else null
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
