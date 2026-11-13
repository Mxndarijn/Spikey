class_name DailyRunRules
extends RefCounted
## Daily Run: one map a day, the same for every player. The server hands out
## the day's seed and season with each try (start_daily_try,
## supabase/migrations/20261113130000_daily_run.sql), so the phone's clock and
## date never pick the map. TRIES_PER_DAY tries a day, the best one counts on
## the Daily Run board, a crash ends the try (no revive), and the board's top 10
## win Economy.DAILY_RUN_PRIZES when the day is over. Replays of today's map
## stay locked until then.

## The server's spikey_daily_run_tries holds the same number.
const TRIES_PER_DAY := 3
## Most squares in the share text; longer runs end with "+N".
const SHARE_SQUARES := 12
const ROOM_DONE := "🟩"
const ROOM_CRASH := "🟥"


static func tries_left(used: int, tries_max: int = TRIES_PER_DAY) -> int:
	return maxi(tries_max - maxi(used, 0), 0)


## The main action's label for the next try: "Try 2", or "" with none left.
static func next_try_label(used: int, tries_max: int = TRIES_PER_DAY) -> String:
	if tries_left(used, tries_max) <= 0:
		return ""
	return "Try %d" % (used + 1)


## "2 tries left", "1 try left", "No tries left".
static func tries_text(used: int, tries_max: int = TRIES_PER_DAY) -> String:
	var left := tries_left(used, tries_max)
	if left == 0:
		return "No tries left"
	return "%d %s left" % [left, "try" if left == 1 else "tries"]


## The short text a player shares after a try, with no spoilers about the map:
## "Flapjaw Daily Run No. 47 · 31 points · #12 of 2,140 · try 2 of 3" and a
## square per room reached (green cleared, red the room of the crash).
static func share_text(
	number: int, score: int, rank: int, players: int, try_n: int, tries_max: int, cleared: int
) -> String:
	var parts: Array[String] = ["Flapjaw Daily Run No. %d" % number, "%d points" % score]
	if rank > 0:
		parts.append("#%d of %s" % [rank, thousands(maxi(players, rank))])
	if try_n > 0:
		parts.append("try %d of %d" % [try_n, tries_max])
	return " · ".join(parts) + "\n" + squares(cleared)


static func squares(cleared: int) -> String:
	var shown := mini(maxi(cleared, 0), SHARE_SQUARES - 1)
	var out := ROOM_DONE.repeat(shown) + ROOM_CRASH
	if cleared > shown:
		out += " +%d" % (cleared - shown)
	return out


## 2140 -> "2,140".
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
