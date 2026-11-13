class_name Economy
extends RefCounted
## The two currencies and the rules between them. Cosmetic only.
## - Gold is `Profile.coins`: collected in runs, plentiful.
## - Diamonds are `Profile.diamonds`: rare, won on the Today board or the Daily Run, or bought in
##   a pack (DiamondPacks). They turn into gold, never the other way: gold can
##   be farmed, so a way back would drain what a top-10 finish is worth.

const GOLD := "gold"
const DIAMOND := "diamond"
## The one anchor every price follows from: 1 diamond = 100 gold.
const GOLD_PER_DIAMOND := 100
## Diamonds for places 1 to 10 on the Today board (14 a day).
const DAILY_PRIZES: Array[int] = [3, 2, 2, 1, 1, 1, 1, 1, 1, 1]
## Diamonds for places 1 to 10 on a finished Daily Run: the same tiers, so the
## game pays 28 a day in all. The server's spikey_daily_run_prize holds the same
## table (supabase/migrations/20261113130000_daily_run.sql); change both.
const DAILY_RUN_PRIZES: Array[int] = DAILY_PRIZES


## Diamonds for a place on the daily board; 0 outside the top 10.
static func daily_prize(rank: int) -> int:
	if rank < 1 or rank > DAILY_PRIZES.size():
		return 0
	return DAILY_PRIZES[rank - 1]


## Diamonds for a place on a finished Daily Run; 0 outside the top 10.
static func daily_run_prize(rank: int) -> int:
	if rank < 1 or rank > DAILY_RUN_PRIZES.size():
		return 0
	return DAILY_RUN_PRIZES[rank - 1]


static func gold_for(diamonds: int) -> int:
	return maxi(diamonds, 0) * GOLD_PER_DIAMOND


## The fewest diamonds that cover a gold shortfall (160 short -> 2).
static func diamonds_to_cover(gold_short: int) -> int:
	if gold_short <= 0:
		return 0
	@warning_ignore("integer_division")
	return (gold_short + GOLD_PER_DIAMOND - 1) / GOLD_PER_DIAMOND
