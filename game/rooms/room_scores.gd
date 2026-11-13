class_name RoomScores
extends RefCounted
## Each room's measured difficulty score, the mean over its variants (fastsim
## difficulty, docs/ROOM_DIFFICULTY.md: 20 a beginner, 40 a normal and 60 a
## good player clears it 9 times in 10). Made by tools/make_room_scores.gd;
## don't edit by hand, run the tool on a new difficulty report instead.
##
## Source: fastsim-rs difficulty, room-regroup run on next-features-2 at
## 62aca6f (2026-11-13, 24 entries per variant): SpikeCage-coord
## research/room-difficulty/v23-regroup/report.json. Lava Rise and Locked Out
## changed after 62aca6f: their numbers are from 62aca6f until a new run.
## Piston Press (generated) measured on its own on next-features-2 at deca255
## with the new human bots (72 entries): 41. Buttons measured on its own on
## next-features-2 at 162437a once the bots press buttons (72 entries per
## variant, every bot tier; scored with the room-regroup rows): 50,
## research/room-difficulty/buttons-press. Stalker Rail with its slide at half
## speed measured on its own on next-features-2 at 98c19b5 (24 entries, scored
## with the room-regroup rows): 34 (was 42 on the same build). Cave Tunnel
## measured on its own on next-features-2 at 1fbddb6 with one slow bat (72
## entries per variant, every bot tier; scored with the room-regroup rows): 32
## (fork 24, drips 40, bats 32).
## Beam Gates (generated, each wall's free run reachable from the last one's through the
## beams, rows a hop from the ceiling and floor) measured on its own on next-features-2 at
## e66fc5b (72 entries, every bot tier; scored with the room-regroup rows without Beam
## Gates'): 48.

const SCORES := {
	"open": 24,
	"crowded": 15,
	"narrow": 70,
	"tide": 23,
	"isles": 45,
	"garden": 14,
	"bramble": 54,
	"squeeze": 52,
	"slowmo": 0,
	"blink": 43,
	"flip": 47,
	"midnight": 51,
	"cloud": 44,
	"gates": 46,
	"crawl": 44,
	"swing": 58,
	"stalker": 34,
	"pinwheel": 70,
	"sawring": 59,
	"piston": 41,
	"crates": 30,
	"beams": 48,
	"stalac": 25,
	"hunter": 60,
	"updraft": 55,
	"bubbles": 50,
	"rain": 57,
	"orchard": 6,
	"keepy": 4,
	"pumpkin": 55,
	"ghostdoors": 59,
	"bats": 58,
	"icicle": 65,
	"gifts": 48,
	"hearts": 44,
	"cupid": 63,
	"eggs": 42,
	"bees": 62,
	"beachball": 1,
	"crabs": 41,
	"fireworks": 86,
	"countdown": 4,
	"crosswind": 14,
	"belt": 25,
	"lockexit": 37,  # changed since the run: measure again
	"lava": 19,  # changed since the run: measure again
	"echo": 39,
	"boss_watcher": 34,
	"boss_crusher": 30,
	"boss_saw": 46,
	"cave": 32,
	"pegs": 44,
	"buttons": 50,
}

## Rooms no bot can measure (the page shows no number).
const UNMEASURED: Array[String] = []


## The room's score, or -1 when it has none (not measured, or an id
## that is no longer in the catalog).
static func of(id: String) -> int:
	return SCORES.get(id, -1)
