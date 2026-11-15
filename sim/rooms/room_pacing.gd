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

## Tiers, easiest first: a room's tier comes from its rank by measured
## difficulty (TIERS); scores at 860b5b4.
## Easy: 7 rooms (16-28).
const EASY := [10, 10, 60, 10, 150, 1]
## Steady: 5 rooms (29-33).
const STEADY := [20, 6, 40, 10, 100, 10, 250, 2]
## Middle: 11 rooms (32-36).
const MIDDLE := [30, 5, 60, 10, 160, 10, 400, 4]
## Hard: 7 rooms (35-38).
const HARD := [50, 4, 100, 12, 200, 14]
## Harder: 8 rooms (37-40).
const HARDER := [70, 4, 130, 14, 250, 18]
## Hardest: 5 rooms (42-57).
const HARDEST := [90, 4, 160, 16, 300, 20]
## Bonus rooms (coins, no real threat): occasional at any score.
const BONUS := [20, 3]
## The weights of every other tier are times this when a room gets its curve,
## so bonus rooms come up a quarter as often as with the curves alone (the
## user, 2026-11-13: tools/room_odds.gd, 1000 runs to 990, 6.6 -> 1.75 per 100
## rooms) and the other tiers keep their shares. 5, not 4: the shuffle bag
## gives light rooms a little more than their weight.
const OTHERS_SCALE := 5
## Seasonal rooms (not bonus) come up more often while their season is on:
## their tier's weights times this over 2.
const SEASON_BOOST := 3
## Rooms that change the controls (gravity flips, a shadow of the bird, walls
## that swap) unlock no earlier than this, however easy bots find them: a new
## player needs a few rooms first. Their curve starts here, at its weight here.
const CONTROL_FLOOR := 40
const CONTROL_ROOMS := ["flip", "echo", "blink"]

## The tier of every room the picker can pick (not the open first room or
## the bosses), by rank (the user's rule B, 2026-11-15): every room ranked by
## its measured mean score (seasonal rooms with the rest; bonus rooms keep
## BONUS) and split into the tiers in order, Easy 7, Steady 6, Middle 12,
## Hard 7, Harder 7, Hardest 4. Only clear moves were taken: a room whose
## score is within 2 points of its old tier's range stays in its old tier
## (the user, 2026-11-15), so the tiers hold 7, 5, 11, 7, 8, 5 rooms.
## Measured on next-features-3 at 860b5b4 (2026-11-15, Rust difficulty tool,
## 24 entries per variant, every bot tier: SpikeCage-coord
## research/room-difficulty/ruleb-860b5b4); the mean score is in the comment,
## with the hardest and easiest variant.
const TIERS := {
	"crowded": EASY,  # 16 (storm 23 .. lopsided 7)
	"belt": EASY,  # 21 (switchback 24 .. counter 16)
	"crosswind": EASY,  # 24 (gusty 27 .. split 22)
	"lava": EASY,  # 24 (rafts 32 .. lava 20)
	"stalac": EASY,  # 24 (alternating 33 .. floor 16)
	"tide": EASY,  # 25 (small 33 .. big 15)
	"crates": EASY,  # 28 (pairs 29 .. wide 26)
	"piston": STEADY,  # 29, was Middle
	"cloud": STEADY,  # 30 (one 31 .. two 28)
	"cave": STEADY,  # 32 (drips 36 .. fork 29)
	"stalker": STEADY,  # 32, ranks Middle: kept, within the noise
	"pegs": STEADY,  # 33 (drift 34 .. classic 32), ranks Middle: kept, within the noise
	"isles": MIDDLE,  # 32 (classic 32 .. drifting 31), ranks Steady: kept, within the noise
	"lockexit": MIDDLE,  # 32 (chain 33 .. quad 29), ranks Steady: kept, within the noise
	"eggs": MIDDLE,  # 32 (classic 32 .. drifting 31), ranks Steady: kept, within the noise
	"blink": MIDDLE,  # 32 (classic 34 .. fast 30)
	"updraft": MIDDLE,  # 32 (gust 49 .. drift 22), was Harder
	"hunter": MIDDLE,  # 34 (twin 37 .. classic 31)
	"hearts": MIDDLE,  # 35 (orbit 36 .. classic 34)
	"gifts": MIDDLE,  # 35 (pairs 40 .. classic 33)
	"flip": MIDDLE,  # 35 (flip-flop 38 .. classic 33)
	"crawl": MIDDLE,  # 36 (swarm 37 .. sprinters 36)
	"icicle": MIDDLE,  # 36, was Hardest
	"squeeze": HARD,  # 35 (breathing 36 .. left-only 33), ranks Middle: kept, within the noise
	"bramble": HARD,  # 36 (curious 41 .. heavy 27), ranks Middle: kept, within the noise
	"cupid": HARD,  # 36 (slow-volley 38 .. classic 34)
	"pumpkin": HARD,  # 37 (splitting 39 .. classic 36)
	"echo": HARD,  # 37 (echo 40 .. mirror 34), was Steady
	"midnight": HARD,  # 38 (classic 38 .. classic 38)
	"bubbles": HARD,  # 38 (spiky 44 .. classic 34), ranks Harder: kept, within the noise
	"rain": HARDER,  # 37 (classic 41 .. stake 32), ranks Hard: kept, within the noise
	"sawring": HARDER,  # 37 (two-rings 43 .. pair 31), ranks Hard: kept, within the noise
	"bats": HARDER,  # 37 (classic 39 .. wide 36), ranks Hard: kept, within the noise
	"swing": HARDER,  # 38 (big 41 .. winch 35)
	"gates": HARDER,  # 39 (single 43 .. classic 35), was Steady
	"crabs": HARDER,  # 39 (swarm 44 .. classic 35), was Middle
	"bees": HARDER,  # 40
	"ghostdoors": HARDER,  # 40 (classic 46 .. row 36)
	"narrow": HARDEST,  # 42, ranks Harder: kept, within the noise
	"beams": HARDEST,  # 42, was Hard
	"pinwheel": HARDEST,  # 44 (rock 47 .. twin 42)
	"buttons": HARDEST,  # 45 (classic 46 .. apart 44), was Middle
	"fireworks": HARDEST,  # 57 (classic 59 .. double 53)
	# Bonus rooms (not ranked)
	"slowmo": BONUS,
	"keepy": BONUS,
	"orchard": BONUS,
	"garden": BONUS,
	"countdown": BONUS,
	"beachball": BONUS,
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
		var scale := 1 if tier == BONUS else OTHERS_SCALE
		for i in tier.size():
			var v: int = tier[i]
			if i % 2 == 1:
				v *= scale
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
