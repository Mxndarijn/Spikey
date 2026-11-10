class_name Shop
extends RefCounted
## Prices. Cosmetic only: nothing here changes gameplay. Buying is Checkout.
## Free items (price 0) are starters: a first start gets the first free flyer.

## Coins are collected in runs (sim/: one coin spawns on a wall bounce when none
## is out) and checked with the same replay as the leaderboards.

## Diamond prices of the premium line (see diamond_price()).
const DIAMOND_WORLD := 30
const DIAMOND_SEASONAL := 25
const DIAMOND_FLYER := 20
const DIAMOND_PRICES := {"flyer": {"bolt": DIAMOND_FLYER, "nova": DIAMOND_FLYER}}

const PRICES := {
	ItemKind.FLYER:
	{
		"buzz": 0,
		"dash": 0,
		"nimbus": 0,
		"hoot": 250,
		"fold": 400,
		"ember": 500,
		"lulu": 300,
		"pip": 350,
		"puff": 350,
		"mochi": 400,
		"tock": 450,
		"bubbles": 500,
		"waddle": 300,
		"flutter": 300,
		"boo": 350,
		"hamlet": 400,
		"scoop": 400,
		"glim": 450,
		"lumi": 450,
		"bolt": 500,
		"nova": 550,
	},
	ItemKind.WORLD:
	{
		"sunset": 0,
		"jungle": 0,
		"ice": 0,
		"lava": 300,
		"deepsea": 300,
		"sugar": 450,
		"star": 600,
	},
	ItemKind.TRAIL:
	{
		"world_ribbon": 0,
		"spark_dots": 200,
		"bubble_stream": 250,
		"rainbow_ribbon": 300,
		"leaf_swirl": 300,
		"pixel_trail": 300,
		"confetti": 350,
		"comet_tail": 400,
		"star_dust": 400,
		"music_notes": 500,
		# Flap trails: one stamp per tap.
		"cloud_puff": 200,
		"ripple": 200,
		"hearts": 250,
		"feather_drop": 250,
		"splash": 300,
		"snowflake": 300,
		"blossom": 300,
		"paw_prints": 350,
		"flame": 350,
		"zap": 400,
	},
	ItemKind.CRASH:
	{
		CrashStyle.DEFAULT_ID: 0,
		"confetti_pop": 200,
		"bubble_trap": 300,
		"dizzy_stars": 300,
		"shatter": 350,
		"pixel_dissolve": 350,
		"paint_splat": 400,
		"comic_pow": 450,
		"firework": 500,
		"little_ghost": 600,
	},
	ItemKind.PLATE:
	{
		PlateStyle.DEFAULT_ID: 0,
		"sunset_glow": 300,
		"jungle_canopy": 300,
		"ice_cavern": 300,
		"finish_line": 350,
		"lava_forge": 400,
		"deep_sea": 400,
		"sugar_rush": 400,
		"star_station": 500,
		"royal": 800,
	},
	ItemKind.PORTAL:
	{
		PortalStyle.DEFAULT_ID: 0,
		"classic_spiral": 0,
		"candy_swirl": 200,
		"mint_breeze": 200,
		"dotted": 250,
		"ripple": 300,
		"galaxy": 300,
		"ink_swirl": 350,
		"rainbow": 400,
		"flame": 400,
		"pixel": 450,
		"golden": 600,
	},
	ItemKind.MUSIC:
	{
		MusicTrack.MATCH_WORLD: 0,
		MusicTrack.SHUFFLE: 0,
		"candy_hop": 0,
		"bubble_drift": 300,
		"jungle_bounce": 300,
		"lava_rush": 400,
		"star_arcade": 400,
	},
}


## Price in coins, or -1 for an item that isn't for sale.
static func price(kind: String, id: String) -> int:
	var table: Dictionary = PRICES.get(kind, {})
	if table.has(id):
		return table[id]
	# Worlds added later (data/design/extra_worlds.json) carry their own price.
	if kind == ItemKind.WORLD:
		var w := Catalog.world(id)
		if w != null:
			return w.price
	return -1


static func is_free(kind: String, id: String) -> bool:
	return price(kind, id) == 0


## Free items of a kind, in display order (the first one is the first-start gift).
static func starters(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id in Catalog.ids(kind):
		if is_free(kind, id):
			out.append(id)
	return out


## The premium line sells for diamonds (Economy), not gold. Every world marked
## `premium` is on it: DIAMOND_SEASONAL when it has a season, else
## DIAMOND_WORLD. Other premium items are listed by id in DIAMOND_PRICES; a new
## one is one line there. An item with a diamond price ignores its gold price.
## Returns 0 for everything sold for gold.
static func diamond_price(kind: String, id: String) -> int:
	var table: Dictionary = DIAMOND_PRICES.get(kind, {})
	if table.has(id):
		return table[id]
	if kind == ItemKind.WORLD:
		var w := Catalog.world(id)
		if w != null and w.premium:
			return DIAMOND_SEASONAL if not w.season.is_empty() else DIAMOND_WORLD
	return 0


## What the item costs in its own currency (-1: not for sale).
static func cost(kind: String, id: String) -> int:
	var gems := diamond_price(kind, id)
	return gems if gems > 0 else price(kind, id)


static func can_afford(profile: Profile, kind: String, id: String) -> bool:
	var gems := diamond_price(kind, id)
	if gems > 0:
		return profile.diamonds >= gems
	var gold := price(kind, id)
	return gold >= 0 and profile.coins >= gold
