class_name RoomScores
extends RefCounted
## Each room's measured difficulty score, the mean over its variants (fastsim
## difficulty, docs/ROOM_DIFFICULTY.md: 20 a beginner, 40 a normal and 60 a
## good player clears it 9 times in 10). Made by tools/make_room_scores.gd;
## don't edit by hand, run the tool on a new difficulty report instead.
##
## Source: fastsim-rs difficulty, full run on next-features-3 at 860b5b4
## (2026-11-15, 24 entries per variant, every bot tier): SpikeCage-coord
## research/room-difficulty/ruleb-860b5b4/report.json

const SCORES := {
	"open": 23,
	"crowded": 16,
	"narrow": 42,
	"tide": 25,
	"isles": 32,
	"garden": 10,
	"bramble": 36,
	"squeeze": 35,
	"slowmo": 9,
	"blink": 32,
	"flip": 35,
	"midnight": 38,
	"cloud": 30,
	"gates": 39,
	"crawl": 36,
	"swing": 38,
	"stalker": 32,
	"pinwheel": 44,
	"sawring": 37,
	"piston": 29,
	"crates": 28,
	"beams": 42,
	"stalac": 24,
	"hunter": 34,
	"updraft": 32,
	"bubbles": 38,
	"rain": 37,
	"orchard": 12,
	"keepy": 17,
	"pumpkin": 37,
	"ghostdoors": 40,
	"bats": 37,
	"icicle": 36,
	"gifts": 35,
	"hearts": 35,
	"cupid": 36,
	"eggs": 32,
	"bees": 40,
	"beachball": 11,
	"crabs": 39,
	"fireworks": 57,
	"countdown": 5,
	"crosswind": 24,
	"belt": 21,
	"lockexit": 32,
	"lava": 24,
	"echo": 37,
	"boss_watcher": 25,
	"boss_crusher": 21,
	"boss_saw": 39,
	"cave": 32,
	"pegs": 33,
	"buttons": 45,
}

## Rooms no bot can measure (the page shows no number).
const UNMEASURED: Array[String] = []


## The room's score, or -1 when it has none (not measured, or an id
## that is no longer in the catalog).
static func of(id: String) -> int:
	return SCORES.get(id, -1)
