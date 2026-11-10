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
const DEFAULT_ID := "paper"
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

## id, name, scene, base colour, white text (a dark plate), blurb.
const STYLES := [
	[DEFAULT_ID, "Paper", "", "FFF4E2", false, "The plain row everyone starts with."],
	["sunset_glow", "Sunset Glow", SUNSET, "FFC78E", false, "A low sun behind two warm hills."],
	["jungle_canopy", "Jungle Canopy", JUNGLE, "D6F2A0", false, "Pointed trees on green hills."],
	[
		"ice_cavern",
		"Ice Cavern",
		ICE,
		"EAF7FF",
		false,
		"Two-tone ice shards rising from the floor."
	],
	["lava_forge", "Lava Forge", LAVA, "FFC27A", false, "A flat volcano with a yellow lava cap."],
	["deep_sea", "Deep Sea", DEEPSEA, "8EEDE4", false, "Coral on the seabed and rising bubbles."],
	["sugar_rush", "Sugar Rush", SUGAR, "FFE9F3", false, "Two lollipops on pink hills."],
	[
		"star_station",
		"Star Station",
		STAR,
		"241A63",
		true,
		"Night sky, a pale moon, a lit station."
	],
	["finish_line", "Finish Line", FINISH, "FFFFFF", false, "A checkered flag on each end."],
	["royal", "Royal", ROYAL, "6447C2", true, "Purple with a gold band and a crown."],
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
	for row: Array in STYLES:
		var p := PlateStyle.new()
		p.id = row[0]
		p.display_name = row[1]
		p.scene = row[2]
		p.base = Color(str(row[3]))
		p.dark = row[4]
		p.blurb = row[5]
		out.append(p)
	return out


## The plate a player has in use; Paper when the save names none we know.
static func equipped(profile: Profile) -> PlateStyle:
	var p := Catalog.plate(profile.equipped_id(Catalog.PLATE)) if profile != null else null
	return p if p != null else Catalog.plate(DEFAULT_ID)


## Paper: the row keeps its normal look and nothing is drawn.
func is_plain() -> bool:
	return scene.is_empty()


## The colour of text on this plate.
func text_color() -> Color:
	return UiTokens.ON_SCRIM if dark else UiTokens.ON_PANEL
