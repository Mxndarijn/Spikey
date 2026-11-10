class_name RoomInfo
extends RefCounted
## How each room kind is shown in the Rooms screen: its name, one-line pitch,
## difficulty (1 to 5), the world its preview is drawn in, and the picture
## (glyph) on its card. Cosmetic only: when a room can appear and how it plays
## live in sim/rooms/ (RoomDef). Text comes from the room ideas page.

## Card groups, in screen order. Seasonal rooms go under "seasonal" whatever
## their sim group, so the season is the first thing you see.
const GROUPS: Array[String] = ["starter", "mid", "late", "bonus", "seasonal"]
const GROUP_NAMES := {
	"starter": "Starter",
	"mid": "Mid-game",
	"late": "Late-game",
	"bonus": "Bonus",
	"seasonal": "Seasonal",
}
## When each season's rooms show up in runs (Seasons.* index).
const SEASON_NAMES := ["October", "December", "February", "Spring", "Summer", "New Year"]

## id -> [name, pitch, difficulty, preview world, glyph]
const ROOMS := {
	"open": ["Open Sky", "The cage at its simplest: two spike walls and you.", 1, "sunset", ""],
	"crowded": ["Crowded", "Open Sky with more spikes on every wall.", 2, "sunset", "extra"],
	"narrow": ["Narrow", "The walls slide in. Less room, quicker bounces.", 2, "ice", "extra"],
	"tide":
	[
		"Tide Spikes",
		"Wall spikes breathe in and out. Some tides are big, some small.",
		2,
		"deepsea",
		"extra"
	],
	"isles":
	[
		"Floating Isles",
		"Rounded rock islands hang in the air. Weave between them.",
		2,
		"jungle",
		"blocks"
	],
	"cloud":
	[
		"Bumper Cloud",
		"A fat friendly cloud, or two, drifts around and bumps you.",
		2,
		"sunset",
		"cloud"
	],
	"gates":
	[
		"Shutter Gates",
		"Two sliding columns with a window. Fly through the window.",
		2,
		"ice",
		"cols"
	],
	"crawl":
	["Caterpillar Crawl", "Spiky caterpillars walk the edges of the cage.", 3, "jungle", "crawl"],
	"garden":
	["Coin Garden", "Four coins and only a few spikes. Grab them all.", 1, "jungle", "coins"],
	"bramble": ["Bramble Ball", "A big thorny ball ricochets around the room.", 3, "ice", "ball"],
	"squeeze":
	["Squeeze Box", "The walls creep inward while you play this room.", 4, "desert", "extra"],
	"slowmo":
	["Slow-Mo Breather", "Time slows to half speed. Coins hang in an arc.", 1, "sunset", "cloud"],
	"blink": ["Blink Walls", "The walls swap between two spike patterns.", 4, "neon", "extra"],
	"flip":
	["Gravity Flip", "Up is down. Tapping pushes you toward the floor.", 4, "deepsea", "flip"],
	"midnight": ["Midnight Cage", "The lights go down and the cage speeds up.", 5, "star", "dark"],
	"piston":
	["Piston Press", "Spiked pistons punch out of the walls, then pull back.", 3, "lava", "blocks"],
	"court":
	[
		"Bumper Court",
		"Sliding pads on the ceiling and floor are the only safe spots.",
		3,
		"sugar",
		"cloud"
	],
	"crates":
	["Crate Drop", "Crates fall from the sky and pile up into towers.", 4, "autumn", "blocks"],
	"beams":
	["Beam Gates", "Light beams snap on and off across the cage to a beat.", 3, "neon", "beam"],
	"stalac":
	[
		"Stalactite Run",
		"Rounded rock fingers hang from the roof and rise from the floor.",
		3,
		"jungle",
		"cols"
	],
	"hunter":
	[
		"Hunter Spike",
		"One glowing spike tears off the wall and darts at your height.",
		4,
		"lava",
		"extra"
	],
	"swing":
	["Lantern Swing", "A spiked lantern swings on a chain from the ceiling.", 3, "autumn", "ball"],
	"stalker":
	["Stalker Rail", "A pair of spikes rides the wall rail to meet you.", 3, "star", "extra"],
	"pinwheel":
	["Pinwheel", "A four-blade star spins in the middle of the cage.", 3, "sunset", "ball"],
	"sawring": ["Saw Ring", "Three saws orbit the middle of the cage.", 4, "ice", "ball"],
	"updraft":
	["Updraft", "Columns of moving air: ride them, time them or fight them.", 3, "desert", "cloud"],
	"bubbles":
	[
		"Bubble Lift",
		"Bubbles rise from the floor. Hop in for a free ride up.",
		3,
		"deepsea",
		"bubbles"
	],
	"rain":
	["Spike Rain", "Sharp drops fall from the ceiling in marked columns.", 4, "desert", "rain"],
	"orchard":
	["Orchard Drop", "Coins tumble from the sky. You are the basket.", 2, "autumn", "rain"],
	"keepy": ["Keepy-Uppy", "Keep a bouncy ball in the air with your head.", 2, "sugar", "ball"],
	"double":
	["Double Trouble", "Two hazards you already know, sharing one room.", 5, "sunset", "ball"],
	"pumpkin":
	["Pumpkin Bounce", "A thorny jack-o'-lantern ricochets around the room.", 3, "haunted", "ball"],
	"ghostdoors":
	[
		"Ghost Doors",
		"Ghost blocks fade in and out. Only solid when you can see them.",
		3,
		"haunted",
		"cols"
	],
	"bats": ["Bat Loop", "Three bats chase each other in a figure eight.", 3, "haunted", "crawl"],
	"icicle": ["Icicle Drop", "Icicles shake on the ceiling, then fall.", 4, "winterfest", "rain"],
	"gifts": ["Gift Stack", "Presents pile up instead of crates.", 4, "winterfest", "blocks"],
	"hearts":
	["Heart Bumpers", "Two soft hearts drift around and bump you.", 2, "blossom", "cloud"],
	"cupid": ["Cupid Lanes", "Arrows fly across in marked lanes.", 3, "blossom", "beam"],
	"eggs":
	[
		"Egg Hunt",
		"Painted eggs hide behind floating isles. Each is worth gold.",
		1,
		"blossom",
		"coins"
	],
	"bees": ["Bee Line", "Bees zigzag across the room on wavy paths.", 3, "jungle", "crawl"],
	"beachball": ["Beach Ball", "Keepy-Uppy with a striped beach ball.", 2, "deepsea", "ball"],
	"crabs": ["Crab Walk", "Crabs scuttle along the walls and floor.", 3, "deepsea", "crawl"],
	"fireworks":
	["Firework Burst", "Rockets rise and burst into a ring of sparks.", 4, "neon", "rain"],
	"countdown": ["Countdown", "Ten coins, ten seconds, then confetti.", 1, "neon", "coins"],
}


static func name_of(id: String) -> String:
	return ROOMS[id][0] if ROOMS.has(id) else id.capitalize()


static func pitch(id: String) -> String:
	return ROOMS[id][1] if ROOMS.has(id) else ""


static func difficulty(id: String) -> int:
	return int(ROOMS[id][2]) if ROOMS.has(id) else 1


static func preview_world(id: String) -> ThemeDef:
	var w := Catalog.world(ROOMS[id][3]) if ROOMS.has(id) else null
	return w if w != null else ThemeCatalog.default_theme()


static func glyph(id: String) -> String:
	return ROOMS[id][4] if ROOMS.has(id) else ""


## Which card group the room sits in.
static func group(def: RoomDef) -> String:
	return "seasonal" if def.season != Seasons.NONE else def.group


static func season_name(def: RoomDef) -> String:
	if def.season < 0 or def.season >= SEASON_NAMES.size():
		return ""
	return SEASON_NAMES[def.season]


## Room kinds in a group, in catalog order.
static func rooms_in(group_id: String) -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for def in RoomCatalog.all():
		if group(def) == group_id:
			out.append(def)
	return out


## Open for practice: met in a real run, or any room in developer mode.
static func is_open(profile: Profile, def: RoomDef) -> bool:
	return DevMode.enabled() or profile.has_met_room(def.id)


## The line under a room card: how often it was cleared, or why it's locked.
static func status(profile: Profile, def: RoomDef) -> String:
	if is_open(profile, def):
		var n := profile.clears(def.id)
		return "Cleared %d×" % n if n > 0 else "Not cleared yet"
	if def.season != Seasons.NONE:
		return "%s only" % season_name(def)
	if profile.best_score < def.from_score:
		return "Reach %d points" % def.from_score
	return "Not met yet"


static func group_label(def: RoomDef) -> String:
	return GROUP_NAMES.get(group(def), "")
