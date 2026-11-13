class_name RoomScores
extends RefCounted
## Each room's measured difficulty score, the mean over its variants (fastsim
## difficulty, docs/ROOM_DIFFICULTY.md: 20 a beginner, 40 a normal and 60 a
## good player clears it 9 times in 10). Made by tools/make_room_scores.gd;
## don't edit by hand, run the tool on a new difficulty report instead.
##
## Source: fastsim difficulty, SpikeCage-coord research/room-difficulty: the
## full run on next-features-2 at 5354aac (2026-11-12), then the rerun-pacing
## and crowded-buttons reruns (v22, cef1c9b). Cave, pegs and bees from the
## room_pacing.gd tier comments (5cae103, no variant rows on disk); buttons 44
## is a placeholder (its Middle tier), as the bots can't finish it yet
## (measured 127 = bots running to the cap). Baked on next-features-2 at
## 1de6ae6: replace with the room-regroup run.

const SCORES := {
	"open": 28,
	"crowded": 18,
	"narrow": 39,
	"tide": 26,
	"isles": 40,
	"garden": 20,
	"bramble": 55,
	"squeeze": 50,
	"slowmo": 10,
	"blink": 43,
	"flip": 48,
	"midnight": 50,
	"cloud": 38,
	"gates": 46,
	"crawl": 35,
	"swing": 55,
	"stalker": 43,
	"pinwheel": 65,
	"sawring": 54,
	"piston": 29,
	"crates": 28,
	"beams": 56,
	"stalac": 63,
	"hunter": 39,
	"updraft": 68,
	"bubbles": 47,
	"rain": 50,
	"orchard": 12,
	"keepy": 11,
	"pumpkin": 54,
	"ghostdoors": 60,
	"bats": 61,
	"icicle": 53,
	"gifts": 48,
	"hearts": 35,
	"cupid": 47,
	"eggs": 42,
	"bees": 72,
	"beachball": 15,
	"crabs": 34,
	"fireworks": 69,
	"countdown": 10,
	"crosswind": 31,
	"belt": 36,
	"lockexit": 48,
	"lava": 19,
	"echo": 41,
	"boss_watcher": 25,
	"boss_crusher": 28,
	"boss_saw": 29,
	"cave": 54,
	"pegs": 50,
	"buttons": 44,
}


## The room's score, or -1 when it has none (not measured yet, or an id
## that is no longer in the catalog).
static func of(id: String) -> int:
	return SCORES.get(id, -1)
