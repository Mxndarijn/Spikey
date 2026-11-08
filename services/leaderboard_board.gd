class_name LeaderboardBoard
extends RefCounted
## One leaderboard as the screen shows it: who is on it, best first, and where
## the player stands. Comes from a LeaderboardService.

enum Status { OK, OFFLINE, SIGNED_OUT }

## LeaderboardService.DAILY, TIER, ALL_TIME or FRIENDS.
var id := ""
var status := Status.OK
## Best first; ranks start at 1. Can include the player (is_me).
var entries: Array[Entry] = []
## The player's own entry, or null when they have no run on this board yet.
var me: Entry = null
## Everyone on the board, also those not in `entries`.
var players := 0
## Seconds until the board starts over, or -1 when it never does.
var resets_in_s := -1
## The tier's name on the tier board ("Gold").
var tier_name := ""


class Entry:
	extends RefCounted
	var rank := 0
	var player_name := ""
	var flyer_id := ""
	var score := 0
	## The server replayed the run and got the same score.
	var verified := true
	var is_me := false

	func _init(p_rank: int, p_name: String, p_flyer: String, p_score: int) -> void:
		rank = p_rank
		player_name = p_name
		flyer_id = p_flyer
		score = p_score


static func make(board_id: String, board_status: Status = Status.OK) -> LeaderboardBoard:
	var b := LeaderboardBoard.new()
	b.id = board_id
	b.status = board_status
	return b


## Nobody has a score on it yet (a daily board right after midnight).
func is_empty() -> bool:
	return status == Status.OK and entries.is_empty()
