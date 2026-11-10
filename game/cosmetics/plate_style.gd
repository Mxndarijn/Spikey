class_name PlateStyle
extends Resource
## The plate behind a player's row on the leaderboards: a tiny flat landscape.
## Cosmetic only. Scenery stays in the bottom third of the row, so the name and
## score stay clear. The player's own row keeps its gold ring on top of any
## plate, so no plate is gold all over.
##
## Adding a plate: one row in STYLES below plus a price in Shop.PRICES. A new
## `scene` also needs its draw function in PlatePainter.

## The free default: the plain paper row.
const DEFAULT_ID := ItemKind.DEFAULT_PLATE
## Scenes PlatePainter knows; "" draws nothing (the plain row).
const SUNSET := "sunset"
const JUNGLE := "jungle"
const ICE := "ice"
const LAVA := "lava"
const DEEPSEA := "deepsea"
const SUGAR := "sugar"
const STAR := "star"
const FINISH := "finish"
const ROYAL := "royal"

## One entry per plate, in display order; the keys are the fields below
## ("name" is display_name, "base" a hex string).
const STYLES: Array[Dictionary] = [
	{
		"id": DEFAULT_ID,
		"name": "Paper",
		"scene": "",
		"base": "FFF4E2",
		"dark": false,
		"blurb": "The plain row everyone starts with."
	},
	{
		"id": "sunset_glow",
		"name": "Sunset Glow",
		"scene": SUNSET,
		"base": "FFC78E",
		"dark": false,
		"blurb": "A low sun behind two warm hills."
	},
	{
		"id": "jungle_canopy",
		"name": "Jungle Canopy",
		"scene": JUNGLE,
		"base": "D6F2A0",
		"dark": false,
		"blurb": "Pointed trees on green hills."
	},
	{
		"id": "ice_cavern",
		"name": "Ice Cavern",
		"scene": ICE,
		"base": "EAF7FF",
		"dark": false,
		"blurb": "Two-tone ice shards rising from the floor."
	},
	{
		"id": "lava_forge",
		"name": "Lava Forge",
		"scene": LAVA,
		"base": "FFC27A",
		"dark": false,
		"blurb": "A flat volcano with a yellow lava cap."
	},
	{
		"id": "deep_sea",
		"name": "Deep Sea",
		"scene": DEEPSEA,
		"base": "8EEDE4",
		"dark": false,
		"blurb": "Coral on the seabed and rising bubbles."
	},
	{
		"id": "sugar_rush",
		"name": "Sugar Rush",
		"scene": SUGAR,
		"base": "FFE9F3",
		"dark": false,
		"blurb": "Two lollipops on pink hills."
	},
	{
		"id": "star_station",
		"name": "Star Station",
		"scene": STAR,
		"base": "241A63",
		"dark": true,
		"blurb": "Night sky, a pale moon, a lit station."
	},
	{
		"id": "finish_line",
		"name": "Finish Line",
		"scene": FINISH,
		"base": "FFFFFF",
		"dark": false,
		"blurb": "A checkered flag on each end."
	},
	{
		"id": "royal",
		"name": "Royal",
		"scene": ROYAL,
		"base": "6447C2",
		"dark": true,
		"blurb": "Purple with a gold band and a crown."
	},
]

## Stable id, kept in saves and sent with runs: never rename a shipped one.
@export var id := DEFAULT_ID
@export var display_name := "Paper"
## Which PlatePainter draw function draws the scenery.
@export var scene := ""
@export var base := Color("FFF4E2")
## A dark plate: its row's text is white.
@export var dark := false
## One line for the shop popup.
@export var blurb := ""


## Every plate, in display order (Catalog.plates()).
static func all() -> Array[PlateStyle]:
	var out: Array[PlateStyle] = []
	for row: Dictionary in STYLES:
		var p := PlateStyle.new()
		p.id = row.id
		p.display_name = row.name
		p.scene = row.scene
		p.base = Color(str(row.base))
		p.dark = row.dark
		p.blurb = row.blurb
		out.append(p)
	return out


## The plate a player has in use; Paper when the save names none we know.
static func equipped(profile: Profile) -> PlateStyle:
	var p := Catalog.plate(profile.equipped_id(ItemKind.PLATE)) if profile != null else null
	return p if p != null else Catalog.plate(DEFAULT_ID)


## Paper: the row keeps its normal look and nothing is drawn.
func is_plain() -> bool:
	return scene.is_empty()


## The colour of text on this plate.
func text_color() -> Color:
	return UiTokens.ON_SCRIM if dark else UiTokens.ON_PANEL
