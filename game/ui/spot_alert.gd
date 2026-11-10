class_name SpotAlert
extends RefCounted
## The words for losing a prize spot on the daily board: someone's run pushed
## the player down past a line that pays fewer diamonds (Economy.daily_prize).
## Used for the line on Home now and for push notifications later, so both
## say the same. Moves that cross no line (inside 4th to 10th) say nothing.


## What to tell a player who was `old_rank` and is `new_rank` now, or "".
## `entries`: today's board, to name who passed them.
static func message(old_rank: int, new_rank: int, entries: Array[LeaderboardBoard.Entry]) -> String:
	if old_rank < 1 or new_rank <= old_rank:
		return ""
	var was := Economy.daily_prize(old_rank)
	var now := Economy.daily_prize(new_rank)
	if was == 0:
		return ""
	if now == 0:
		var tenth := _at(entries, Economy.DAILY_PRIZES.size())
		if tenth == null:
			return "You're out of the top 10."
		return "You're out of the top 10. Beat %d to win a diamond back." % tenth.score
	if old_rank <= 3 and new_rank > 3:
		return (
			"You're off the podium. %s now: %s instead of %d."
			% [ordinal(new_rank), diamonds(now), was]
		)
	if old_rank == 1:
		var first := _at(entries, 1)
		var lead := "You lost 1st place."
		if first != null:
			lead = "%s took 1st with %d." % [first.player_name, first.score]
		return "%s You're %s now: %s instead of %d." % [lead, ordinal(new_rank), diamonds(now), was]
	if old_rank == 2 and new_rank == 3:
		var second := _at(entries, 2)
		var lead := "You lost 2nd place."
		if second != null:
			lead = "%s passed you with %d." % [second.player_name, second.score]
		return "%s You're 3rd now, still %s." % [lead, diamonds(now)]
	return ""


## Someone else at this place, or null.
static func _at(entries: Array[LeaderboardBoard.Entry], rank: int) -> LeaderboardBoard.Entry:
	for e in entries:
		if e.rank == rank and not e.is_me:
			return e
	return null


static func diamonds(count: int) -> String:
	return "1 diamond" if count == 1 else "%d diamonds" % count


## 1 -> "1st", 2 -> "2nd", 11 -> "11th", 23 -> "23rd".
static func ordinal(n: int) -> String:
	var tens := n % 100
	if tens >= 11 and tens <= 13:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
	return "%dth" % n
