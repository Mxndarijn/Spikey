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

## The tier of every room the picker can pick (not the open first room or
## the bosses). Measured on next-features-2 at 5354aac (2026-11-12); the
## mean score is in the comment.
const TIERS := {
	"lava": EASY,  # 16
	"cloud": EASY,  # 25
	"tide": EASY,  # 25
	"crosswind": EASY,  # 29
	"court": EASY,  # 31
	"belt": STEADY,  # 33
	"piston": STEADY,  # 33
	"crawl": STEADY,  # 33
	"hunter": STEADY,  # 36
	"crowded": STEADY,  # 37
	"echo": STEADY,  # 38
	"blink": STEADY,  # 39
	"flip": STEADY,  # 40
	"lockexit": STEADY,  # 40
	"isles": MIDDLE,  # 42
	"stalker": MIDDLE,  # 42
	"narrow": MIDDLE,  # 43
	"midnight": MIDDLE,  # 43
	"bubbles": MIDDLE,  # 45
	"beams": MIDDLE,  # 46
	"rain": HARD,  # 49
	"stalac": HARD,  # 51
	"gates": HARD,  # 52
	"swing": HARD,  # 52
	"double": HARD,  # 51
	"bramble": HARD,  # 54
	"crates": HARD,  # 54
	"sawring": HARD,  # 55
	"updraft": HARDER,  # 57
	"squeeze": HARDER,  # 60
	"pinwheel": HARDEST,  # 66
	"garden": BONUS,  # 19
	"orchard": BONUS,  # 11
	"keepy": BONUS,  # 9
	"slowmo": BONUS,  # 7
	# Seasonal
	"hearts": EASY,  # 21
	"crabs": STEADY,  # 32
	"eggs": MIDDLE,  # 43
	"cupid": MIDDLE,  # 45
	"icicle": HARD,  # 51
	"pumpkin": HARD,  # 56
	"bats": HARDER,  # 60
	"ghostdoors": HARDER,  # 61
	"gifts": HARDEST,  # 67
	"fireworks": HARDEST,  # 70
	"bees": HARDEST,  # 72
	"beachball": BONUS,  # 14
	"countdown": BONUS,  # 9
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
		def.pace = pace
		def.from_score = pace[0]


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
