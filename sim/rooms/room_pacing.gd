class_name RoomPacing
extends RefCounted
## When each room can show up and how often, as the score climbs: the pick
## weight of a room is a curve over the score (RoomDef.pace). The curve of a
## room comes from its tier, and its tier from its measured difficulty
## (`fastsim difficulty`, docs/ROOM_DIFFICULTY.md: the mean score over its
## variants), not from its group label. Easy rooms fade as the run goes on
## and hard ones grow, so the run gets harder in a controlled way.
##
## A curve is score, weight pairs: weight 0 below the first score, a straight
## line (integer) between two points, the last weight after the last point.
## The first score is the room's unlock (RoomDef.from_score).

## Tiers by measured difficulty score (20 beginner, 40 normal, 60 good).
## Up to 32: a beginner clears it nearly always.
const EASY := [10, 10, 60, 10, 150, 1]
## 32 to 40.
const STEADY := [20, 6, 40, 10, 100, 10, 250, 2]
## 40 to 48: a normal player clears it 9 times in 10.
const MIDDLE := [30, 5, 60, 10, 160, 10, 400, 4]
## 48 to 56.
const HARD := [50, 4, 100, 12, 200, 14]
## 56 to 63.
const HARDER := [70, 4, 130, 14, 250, 18]
## Over 63: needs more than a good player.
const HARDEST := [90, 4, 160, 16, 300, 20]
## Bonus rooms (coins, no real threat): occasional at any score.
const BONUS := [20, 3]
## Seasonal rooms (not bonus) come up more often while their season is on:
## their tier's weights times this over 2.
const SEASON_BOOST := 3
## Rooms that change the controls (gravity flips, a shadow of the bird, walls
## that swap) unlock no earlier than this, however easy bots find them: a new
## player needs a few rooms first. Their curve starts here, at its weight here.
const CONTROL_FLOOR := 40
const CONTROL_ROOMS := ["flip", "echo", "blink"]

## The tier of every room the picker can pick (not the open first room or
## the bosses). Measured on next-features-2 at 62aca6f (2026-11-13, Rust
## difficulty tool, 24 entries per variant, every bot tier); the mean score
## is in the comment.
const TIERS := {
	"crosswind": EASY,  # 14
	"crowded": EASY,  # 15
	"lava": EASY,  # 19
	"tide": EASY,  # 23
	"belt": EASY,  # 25
	"stalac": EASY,  # 25 (alternating 40)
	"crates": EASY,  # 30
	"piston": STEADY,  # 36
	"echo": STEADY,  # 39
	"cloud": STEADY,  # 44 (bots clear it like Steady: skill 26 / 35; analytic 54 / 59)
	"stalker": MIDDLE,  # 41
	"lockexit": MIDDLE,  # 42 (trio 38, quad 43, chain 45, since classic and orbit went)
	"blink": MIDDLE,  # 43
	"crawl": MIDDLE,  # 44
	"pegs": MIDDLE,  # 44
	"isles": MIDDLE,  # 45
	"gates": MIDDLE,  # 46 (single 53, classic 39)
	"flip": MIDDLE,  # 47
	"hunter": MIDDLE,  # 60 (human bots 78-90, analytic 33-37: one step until a playtest)
	"buttons": MIDDLE,  # not measurable yet (bots never press the buttons): design guess
	"bubbles": HARD,  # 50
	"midnight": HARD,  # 51
	"squeeze": HARD,  # 52
	"beams": HARD,  # 53
	"bramble": HARD,  # 54 (heavy 34 .. curious 77, still being fixed)
	"cave": HARD,  # 44 (fork 29, bats 58; fork still being reworked)
	"rain": HARDER,  # 57
	"swing": HARDER,  # 58
	"sawring": HARDER,  # 59
	"updraft": HARDER,  # 55 (gust 90, chimney 69; gust still being fixed)
	"narrow": HARDEST,  # 70
	"pinwheel": HARDEST,  # 70
	"slowmo": BONUS,  # 0
	"keepy": BONUS,  # 4
	"orchard": BONUS,  # 6
	"garden": BONUS,  # 14
	# Seasonal
	"eggs": MIDDLE,  # 42
	"crabs": MIDDLE,  # 41
	"hearts": MIDDLE,  # 44
	"gifts": MIDDLE,  # 48
	"pumpkin": HARD,  # 56
	"cupid": HARD,  # 63 (human bots 54-97, analytic 43-51: one step until a playtest)
	"bats": HARDER,  # 58
	"ghostdoors": HARDER,  # 59
	"bees": HARDER,  # 62
	"icicle": HARDEST,  # 65
	"fireworks": HARDEST,  # 86
	"countdown": BONUS,  # 4
	"beachball": BONUS,  # 1
}


## Gives every room in `defs` its curve and unlock score (RoomCatalog.all).
## A room without a tier keeps an empty curve: never picked.
static func apply(defs: Array[RoomDef]) -> void:
	for def in defs:
		if not TIERS.has(def.id):
			continue
		var tier: Array = TIERS[def.id]
		var pace := PackedInt32Array()
		var boost := def.season != Seasons.NONE and def.group != "bonus"
		for i in tier.size():
			var v: int = tier[i]
			if boost and i % 2 == 1:
				v = v * SEASON_BOOST / 2
			pace.append(v)
		if def.id in CONTROL_ROOMS and pace[0] < CONTROL_FLOOR:
			pace = floored(pace, CONTROL_FLOOR)
		def.pace = pace
		def.from_score = pace[0]


## Curve `pace` starting at `at` instead (0 before it): its weight at
## `at`, then its points after `at`.
static func floored(pace: PackedInt32Array, at: int) -> PackedInt32Array:
	var out := PackedInt32Array([at, weight(pace, at)])
	for i in range(0, pace.size(), 2):
		if pace[i] > at:
			out.append(pace[i])
			out.append(pace[i + 1])
	return out


## The weight of curve `pace` at `score` (0 before it starts or if empty).
static func weight(pace: PackedInt32Array, score: int) -> int:
	if pace.is_empty() or score < pace[0]:
		return 0
	for i in range(0, pace.size() - 2, 2):
		var a := pace[i]
		var b := pace[i + 2]
		if score < b:
			var wa := pace[i + 1]
			return wa + (pace[i + 3] - wa) * (score - a) / (b - a)
	return pace[pace.size() - 1]
