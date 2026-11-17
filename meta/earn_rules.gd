class_name EarnRules
extends RefCounted
## The ways to earn diamonds besides the daily board (Economy.DAILY_PRIZES):
## best-score milestones (the first four, then the ladder to 1000), once each,
## and a streak of days with a checked run.
## The server pays them (backend/migrations/20261110100000_diamonds.sql);
## this holds the same table for the game's own screens.

## [score, diamonds]: a best score of 25 for the first time wins 1, and so on.
const MILESTONES: Array[Array] = [[25, 1], [50, 1], [75, 2], [100, 3]]
## The ladder after them: every LADDER_STEP from LADDER_FROM to LADDER_TOP
## (150, 200, ..., 1000) wins LADDER_PRIZE once. Steps at or below the
## player's ladder mark (their best when the ladder came, from the server)
## never pay (backend/migrations/20261114120000_score_ladder.sql).
const LADDER_FROM := 150
const LADDER_STEP := 50
const LADDER_TOP := 1000
const LADDER_PRIZE := 3
## The most ladder chips Earn free shows at once (ladder_window).
const WINDOW := 4
## Every STREAK_DAYS days in a row (7, 14, 21...) win STREAK_PRIZE.
const STREAK_DAYS := 7
const STREAK_PRIZE := 1


## The first four milestones: 25, 50, 75, 100.
static func first_scores() -> Array[int]:
	var out: Array[int] = []
	for m: Array in MILESTONES:
		out.append(int(m[0]))
	return out


## The ladder's steps: 150, 200, ..., 1000.
static func ladder_scores() -> Array[int]:
	var out: Array[int] = []
	for score in range(LADDER_FROM, LADDER_TOP + 1, LADDER_STEP):
		out.append(score)
	return out


## Every milestone, lowest first: the first four, then the ladder.
static func milestone_scores() -> Array[int]:
	var out := first_scores()
	out.append_array(ladder_scores())
	return out


static func is_ladder(score: int) -> bool:
	return score >= LADDER_FROM and score <= LADDER_TOP and (score - LADDER_FROM) % LADDER_STEP == 0


## Diamonds for reaching `score` (0 when it is not a milestone).
static func milestone_prize(score: int) -> int:
	for m: Array in MILESTONES:
		if int(m[0]) == score:
			return int(m[1])
	return LADDER_PRIZE if is_ladder(score) else 0


## Whether `score` still pays for a player whose ladder mark is `mark`: the
## first four always do, a ladder step only above the mark.
static func payable(score: int, mark: int = 0) -> bool:
	if milestone_prize(score) <= 0:
		return false
	return not is_ladder(score) or score > mark


## The lowest milestone not won yet that still pays, or 0 when none is left.
static func next_milestone(won: Array[int], mark: int = 0) -> int:
	for score in milestone_scores():
		if payable(score, mark) and not won.has(score):
			return score
	return 0


## The milestones a best score has reached that pay (above the mark).
static func reached(best: int, mark: int = 0) -> Array[int]:
	var out: Array[int] = []
	for score in milestone_scores():
		if best >= score and payable(score, mark):
			out.append(score)
	return out


## How far `best` is from the milestone below the next one to win to that
## next one, 0.0 to 1.0 (1.0 when nothing is left).
static func progress(best: int, won: Array[int], mark: int = 0) -> float:
	var next := next_milestone(won, mark)
	if next == 0:
		return 1.0
	var below := 0
	for score in milestone_scores():
		if score < next:
			below = score
	return clampf(float(best - below) / float(next - below), 0.0, 1.0)


## The milestones a run of `score` wins that a best of `previous_best` had not
## reached: lowest first, without those already `won` or at or below `mark`.
## What Game over shows; the server pays them once it has checked the run.
static func new_prizes(
	previous_best: int, score: int, won: Array[int] = [], mark: int = 0
) -> Array[int]:
	var out: Array[int] = []
	for m in milestone_scores():
		if m > previous_best and m <= score and payable(m, mark) and not won.has(m):
			out.append(m)
	return out


## Diamonds the milestones `scores` pay together.
static func prizes_total(scores: Array[int]) -> int:
	var sum := 0
	for score in scores:
		sum += milestone_prize(score)
	return sum


## The ladder chips Earn free shows: the last step won, the next one and the
## ones after it, at most WINDOW chips. "more" is the step where "and every 50
## after" starts (0: the chips reach the top). All won: the last steps.
## Steps at or below the mark never show: they don't pay.
static func ladder_window(won: Array[int], mark: int = 0) -> Dictionary:
	var steps: Array[int] = []
	for score in ladder_scores():
		if score > mark:
			steps.append(score)
	var first := -1
	for i in steps.size():
		if not won.has(steps[i]):
			first = i
			break
	if first < 0:
		return {"steps": steps.slice(maxi(steps.size() - WINDOW, 0)), "more": 0}
	var rest := steps.slice(maxi(first - 1, 0))
	if rest.size() > WINDOW:
		return {"steps": rest.slice(0, WINDOW - 1), "more": rest[WINDOW - 1]}
	return {"steps": rest, "more": 0}


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
