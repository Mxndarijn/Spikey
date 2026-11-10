class_name SampleLeaderboard
extends LeaderboardService
## Made-up boards until the leaderboard server exists (Phase 3). Other players
## are sample data; the player's own entries come from their profile (best
## score, leaderboard name, flyer) and from runs finished today.
## Nothing is verified here: the real client only shows runs the server replayed.

const DAILY_SCORES: Array[int] = [188, 176, 170, 160, 151, 144, 139, 131, 126, 118, 112, 104]
const ALL_TIME_SCORES: Array[int] = [412, 398, 377, 365, 351, 344, 338, 331, 322, 317, 309, 301]
## Tier board: other players sit this far above or below the player's best.
const TIER_OFFSETS: Array[int] = [24, 19, 15, 12, 9, 7, 5, 3, 1, -2, -4, -7, -10, -14]
const TIERS := [[0, "Bronze"], [40, "Silver"], [90, "Gold"], [160, "Diamond"]]
const FRIEND_LIST := [["Noor", "pip", 131], ["Ines", "puff", 66], ["Bram_77", "dash", 40]]
const NAMES: Array[String] = [
	"Noor",
	"Kofi",
	"mia.flaps",
	"Jun",
	"zuzu",
	"Raf",
	"Ines",
	"Oskar",
	"sol.r",
	"kiki",
	"pebble",
	"Bram_77",
	"dotty",
	"TapTapLeo",
]
const FLYERS: Array[String] = [
	"pip", "hoot", "ember", "lulu", "mochi", "fold", "puff", "nimbus", "bubbles", "tock", "dash"
]
## Name plates of the sample players: most keep the plain row ("").
const PLATES: Array[String] = [
	"", "", "sunset_glow", "", "", "deep_sea", "", "star_station", "", "", "sugar_rush", "", ""
]
const DAILY_PLAYERS := 8930
const ALL_TIME_PLAYERS := 52140
const TIER_PLAYERS := 50
## How many ranks each point below the last listed score costs.
const RANKS_PER_POINT := 37

## Tests turn these off to see the offline and signed-out boards.
var online := true
var signed_in := false
## Seconds since local midnight; -1 reads the clock. Tests set it.
var clock_s := -1

var _profile: Profile
## The best real run since the game started; the daily board's own score.
var _today_best := 0


func _init(profile: Profile) -> void:
	_profile = profile


func request_board(board_id: String) -> void:
	_deliver(build_board(board_id))


## Builds a board right away (the sample has no network to wait for).
func build_board(board_id: String) -> LeaderboardBoard:
	if not online:
		return LeaderboardBoard.make(board_id, LeaderboardBoard.Status.OFFLINE)
	if board_id == FRIENDS and not signed_in:
		return LeaderboardBoard.make(board_id, LeaderboardBoard.Status.SIGNED_OUT)
	var b := LeaderboardBoard.make(board_id)
	match board_id:
		DAILY:
			b.players = DAILY_PLAYERS
			b.resets_in_s = _seconds_to_midnight()
			_fill(b, DAILY_SCORES, _today_best)
		TIER:
			var best := _profile.best_score
			b.players = TIER_PLAYERS
			b.resets_in_s = _seconds_to_midnight() + _days_to_monday() * 86400
			b.tier_name = tier_for(best)
			var scores: Array[int] = []
			for off in TIER_OFFSETS:
				scores.append(maxi(maxi(best, 20) + off, 1))
			_fill(b, scores, best)
		ALL_TIME:
			b.players = ALL_TIME_PLAYERS
			_fill(b, ALL_TIME_SCORES, _profile.best_score)
		FRIENDS:
			_fill_friends(b)
	return b


func submit_run(score: int, _replay: Dictionary = {}) -> void:
	_today_best = maxi(_today_best, score)


func cached_rank(board_id: String) -> int:
	var b := build_board(board_id)
	return b.me.rank if b.me != null else 0


func is_signed_in() -> bool:
	return signed_in


func sign_in() -> void:
	signed_in = true


## The tier a best score falls in.
static func tier_for(best: int) -> String:
	var title := String(TIERS[0][1])
	for t: Array in TIERS:
		if best >= int(t[0]):
			title = String(t[1])
	return title


## Fills a board from other players' scores (best first) plus the player's.
func _fill(b: LeaderboardBoard, scores: Array[int], mine: int) -> void:
	var placed := false
	for i in scores.size():
		if mine > 0 and not placed and mine >= scores[i]:
			b.me = _me(b.entries.size() + 1, mine)
			b.entries.append(b.me)
			placed = true
		var n := b.entries.size()
		var other := LeaderboardBoard.Entry.new(
			n + 1, NAMES[i % NAMES.size()], FLYERS[i % FLYERS.size()], scores[i]
		)
		other.plate_id = PLATES[i % PLATES.size()]
		b.entries.append(other)
	if mine > 0 and not placed:
		var below := scores[scores.size() - 1] - mine
		var rank := b.entries.size() + 1 + below * RANKS_PER_POINT
		b.me = _me(rank, mine)
	if b.me != null:
		b.players = maxi(b.players, b.me.rank)


func _fill_friends(b: LeaderboardBoard) -> void:
	var all: Array[LeaderboardBoard.Entry] = []
	for f: Array in FRIEND_LIST:
		all.append(LeaderboardBoard.Entry.new(0, f[0], f[1], f[2]))
	if _profile.best_score > 0:
		b.me = _me(0, _profile.best_score)
		all.append(b.me)
	all.sort_custom(
		func(a: LeaderboardBoard.Entry, c: LeaderboardBoard.Entry) -> bool: return a.score > c.score
	)
	for i in all.size():
		all[i].rank = i + 1
	b.entries = all
	b.players = all.size()


func _me(rank: int, score: int) -> LeaderboardBoard.Entry:
	var e := LeaderboardBoard.Entry.new(
		rank, display_name(), _profile.equipped_id(ItemKind.FLYER), score
	)
	e.is_me = true
	e.plate_id = _profile.equipped_id(ItemKind.PLATE)
	return e


## The player's name on the boards ("You" until they pick one).
func display_name() -> String:
	return _profile.leaderboard_name if not _profile.leaderboard_name.is_empty() else "You"


func _seconds_to_midnight() -> int:
	var now := clock_s
	if now < 0:
		var t := Time.get_time_dict_from_system()
		now = int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second)
	return 86400 - clampi(now, 0, 86399)


## Whole days until the tier board moves players up (Monday 00:00).
func _days_to_monday() -> int:
	var weekday := int(Time.get_date_dict_from_system().weekday)
	return (7 - weekday) % 7
