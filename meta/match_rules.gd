class_name MatchRules
extends RefCounted
## Battle's rules (docs/DUEL_MODE.md): first to 6 round wins, the starter opens
## round 1 and the opener alternates, a round played at 5-5 is blind, a round
## goes to the higher score and then the coins. The server decides every round
## (backend/migrations/0110_battles.sql, spikey_battle_limits); these are the
## same numbers, for what the screens say before an answer arrives.

enum Outcome { WIN, LOSS, DRAW }

const FIRST_TO := 6
const MAX_ROUNDS := 13
const MAX_OPEN := 20
## A battle can be closed with no result after this long waiting on the other.
const CLOSE_AFTER_DAYS := 7


## Who wins a round: the higher score, then more coins.
static func round_outcome(
	my_score: int, my_coins: int, their_score: int, their_coins: int
) -> Outcome:
	if my_score != their_score:
		return Outcome.WIN if my_score > their_score else Outcome.LOSS
	if my_coins != their_coins:
		return Outcome.WIN if my_coins > their_coins else Outcome.LOSS
	return Outcome.DRAW


## True when the starter (player A) opens round `number`.
static func starter_opens(number: int) -> bool:
	return number % 2 == 1


## A round played at first_to - 1 each: neither sees the other's run first.
static func is_blind(wins_a: int, wins_b: int, first_to: int = FIRST_TO) -> bool:
	return wins_a == first_to - 1 and wins_b == first_to - 1


## The battle is decided: someone reached first_to wins.
static func is_decided(wins_me: int, wins_them: int, first_to: int = FIRST_TO) -> bool:
	return wins_me >= first_to or wins_them >= first_to


## "You 3 – 2 Mira".
static func score_line(wins_me: int, wins_them: int, rival: String) -> String:
	return "You %d – %d %s" % [wins_me, wins_them, rival]


## "2 h ago", "3 days ago", "just now", from seconds since the last move.
static func since_text(seconds: int) -> String:
	if seconds < 60:
		return "just now"
	if seconds < 3600:
		@warning_ignore("integer_division")
		return "%d min ago" % (seconds / 60)
	if seconds < 86400:
		@warning_ignore("integer_division")
		return "%d h ago" % (seconds / 3600)
	@warning_ignore("integer_division")
	var days := seconds / 86400
	return "1 day ago" if days == 1 else "%d days ago" % days
