class_name ItemKind
extends RefCounted
## The kinds of things a player can own and use, and the free ones every
## player starts with. Ids only: what each id looks like is in game/cosmetics
## (Catalog), its price in Shop.

const FLYER := "flyer"
const WORLD := "world"
const TRAIL := "trail"
const PORTAL := "portal"
const MUSIC := "music"
## What the flyer bursts into on a crash (CrashStyle).
const CRASH := "crash"
## The plate behind the player's leaderboard row (PlateStyle).
const PLATE := "plate"
const ALL: Array[String] = [FLYER, WORLD, TRAIL, PORTAL, MUSIC, CRASH, PLATE]

## Defaults, used from the start and whenever an equipped id is gone.
const DEFAULT_TRAIL := "world_ribbon"
const DEFAULT_PORTAL := "match_world"
const DEFAULT_CRASH := "feather_puff"
const DEFAULT_PLATE := "paper"
## Music picks that are not tracks: play the world's own track, or shuffle.
const MUSIC_MATCH_WORLD := "match_world"
const MUSIC_SHUFFLE := "shuffle"
## The free starter track.
const DEFAULT_TRACK := "candy_hop"

## kind -> ids every new profile owns (all free: tests/unit/test_economy.gd
## checks they match Shop's price-0 items). Flyers and worlds come with the
## first start instead (main._first_start).
const STARTERS: Dictionary[String, Array] = {
	TRAIL: [DEFAULT_TRAIL],
	PORTAL: [DEFAULT_PORTAL, "classic_spiral"],
	MUSIC: [MUSIC_MATCH_WORLD, MUSIC_SHUFFLE, DEFAULT_TRACK],
	CRASH: [DEFAULT_CRASH],
	PLATE: [DEFAULT_PLATE],
}
## kind -> id a new profile uses.
const DEFAULTS: Dictionary[String, String] = {
	TRAIL: DEFAULT_TRAIL,
	PORTAL: DEFAULT_PORTAL,
	MUSIC: MUSIC_MATCH_WORLD,
	CRASH: DEFAULT_CRASH,
	PLATE: DEFAULT_PLATE,
}
