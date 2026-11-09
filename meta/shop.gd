class_name Shop
extends RefCounted
## Prices and buying. Cosmetic only: nothing here changes gameplay.
## Free items (price 0) are starters: a first start gets the first free flyer.

enum Result { OK, ALREADY_OWNED, NOT_ENOUGH_COINS, UNKNOWN_ITEM, NOT_ENOUGH_DIAMONDS }

## Coins are collected in runs (sim/: one coin spawns on a wall bounce when none
## is out) and checked with the same replay as the leaderboards.

## Diamond prices of the premium line (see diamond_price()).
const DIAMOND_WORLD := 30
const DIAMOND_SEASONAL := 25
const DIAMOND_FLYER := 20
const DIAMOND_PRICES := {"flyer": {"bolt": DIAMOND_FLYER, "nova": DIAMOND_FLYER}}

const PRICES := {
	Catalog.FLYER:
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
	},
	Catalog.WORLD:
	{
		"sunset": 0,
		"jungle": 0,
		"ice": 0,
		"lava": 300,
		"deepsea": 300,
		"sugar": 450,
		"star": 600,
	},
	Catalog.TRAIL:
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
	},
	Catalog.PORTAL:
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
	Catalog.MUSIC:
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
	if kind == Catalog.WORLD:
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


static func buy(profile: Profile, kind: String, id: String) -> Result:
	var gems := diamond_price(kind, id)
	var gold := price(kind, id)
	if gold < 0 and gems == 0:
		return Result.UNKNOWN_ITEM
	if profile.owns(kind, id):
		return Result.ALREADY_OWNED
	if gems > 0:
		if profile.diamonds < gems:
			return Result.NOT_ENOUGH_DIAMONDS
		profile.diamonds -= gems
	else:
		if profile.coins < gold:
			return Result.NOT_ENOUGH_COINS
		profile.coins -= gold
	profile.grant(kind, id)
	return Result.OK


## The premium line sells for diamonds (Economy), not gold. Every world marked
## `premium` is on it: DIAMOND_SEASONAL when it has a season, else
## DIAMOND_WORLD. Other premium items are listed by id in DIAMOND_PRICES; a new
## one is one line there. An item with a diamond price ignores its gold price.
## Returns 0 for everything sold for gold.
static func diamond_price(kind: String, id: String) -> int:
	var table: Dictionary = DIAMOND_PRICES.get(kind, {})
	if table.has(id):
		return table[id]
	if kind == Catalog.WORLD:
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
