class_name EarnRules
extends RefCounted
## The ways to earn diamonds besides the daily board (Economy.DAILY_PRIZES):
## best-score milestones, once each, and a streak of days with a checked run.
## The server pays them (supabase/migrations/20261110100000_diamonds.sql);
## this holds the same table for the game's own screens.

## [score, diamonds]: a best score of 25 for the first time wins 1, and so on.
const MILESTONES: Array[Array] = [[25, 1], [50, 1], [75, 2], [100, 3]]
## Every STREAK_DAYS days in a row (7, 14, 21...) win STREAK_PRIZE.
const STREAK_DAYS := 7
const STREAK_PRIZE := 1


static func milestone_scores() -> Array[int]:
	var out: Array[int] = []
	for m: Array in MILESTONES:
		out.append(int(m[0]))
	return out


## Diamonds for reaching `score` (0 when it is not a milestone).
static func milestone_prize(score: int) -> int:
	for m: Array in MILESTONES:
		if int(m[0]) == score:
			return int(m[1])
	return 0


## The lowest milestone not won yet, or 0 when all are won.
static func next_milestone(won: Array[int]) -> int:
	for score in milestone_scores():
		if not won.has(score):
			return score
	return 0


## The milestones a best score has reached.
static func reached(best: int) -> Array[int]:
	var out: Array[int] = []
	for score in milestone_scores():
		if best >= score:
			out.append(score)
	return out


## How far `best` is along the milestones, 0.0 to 1.0 (the last one is 1.0).
static func progress(best: int) -> float:
	var top: int = milestone_scores()[-1]
	return clampf(float(best) / float(top), 0.0, 1.0)


## Days of the current week of a streak that are done: 0 to 7, where 7 is a
## week just finished (day 7, 14...) and day 8 starts the next week at 1.
static func week_days(streak: int) -> int:
	if streak <= 0:
		return 0
	var d := streak % STREAK_DAYS
	return STREAK_DAYS if d == 0 else d


## Days still to play for the next streak diamond (1 to 7).
static func days_to_prize(streak: int) -> int:
	return STREAK_DAYS - maxi(streak, 0) % STREAK_DAYS


## Streak diamonds a row of `streak` days has won.
static func streak_prizes(streak: int) -> int:
	@warning_ignore("integer_division")
	return maxi(streak, 0) / STREAK_DAYS * STREAK_PRIZE
