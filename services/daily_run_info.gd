class_name DailyRunInfo
extends RefCounted
## Today's Daily Run for this player, as get_daily_run answers it
## (supabase/migrations/20261113130000_daily_run.sql): the day's number, its
## season, the time to the reset, the tries used, the best try and its rank,
## and how yesterday's Daily Run ended. The seed is not here: it comes with a
## try (DailyTry), so the map can't be played before the try is counted.

enum Status { OK, OFFLINE }

var status := Status.OK
## "2026-11-14", the board's day.
var day := ""
## No. 1 is the first Daily Run.
var number := 0
var season := Seasons.NONE
## Seconds to the reset, when a new map starts.
var resets_in_s := -1
var tries_max := DailyRunRules.TRIES_PER_DAY
var tries_used := 0
## The best try today, -1 before the first one is sent.
var best := -1
## The best try's place today, 0 while unranked.
var rank := 0
var players := 0
## Yesterday's Daily Run, or null when there was none.
var yesterday: Yesterday = null


class Yesterday:
	extends RefCounted
	var day := ""
	var number := 0
	var players := 0
	## Its prizes were handed out.
	var settled := false
	## The player's place and score, 0 / -1 without a checked try.
	var rank := 0
	var score := -1
	## The first three, best first (their replays are open now).
	var top: Array[LeaderboardBoard.Entry] = []


static func offline() -> DailyRunInfo:
	var info := DailyRunInfo.new()
	info.status = Status.OFFLINE
	return info


func is_online() -> bool:
	return status == Status.OK


func tries_left() -> int:
	return DailyRunRules.tries_left(tries_used, tries_max)


## get_daily_run's answer; anything unexpected reads as offline.
static func parse(data: Variant) -> DailyRunInfo:
	if not data is Dictionary or not (data as Dictionary).has("number"):
		return offline()
	var d := data as Dictionary
	var info := DailyRunInfo.new()
	info.day = str(d.get("day", ""))
	info.number = int(d.get("number", 0))
	info.season = _int(d.get("season"), Seasons.NONE)
	info.resets_in_s = _int(d.get("resets_in_s"), -1)
	info.tries_max = maxi(_int(d.get("tries_max"), DailyRunRules.TRIES_PER_DAY), 1)
	info.tries_used = maxi(_int(d.get("tries_used"), 0), 0)
	info.best = _int(d.get("best"), -1)
	info.rank = maxi(_int(d.get("rank"), 0), 0)
	info.players = maxi(_int(d.get("players"), 0), 0)
	var y: Variant = d.get("yesterday")
	if y is Dictionary:
		var yd := y as Dictionary
		var past := Yesterday.new()
		past.day = str(yd.get("day", ""))
		past.number = _int(yd.get("number"), 0)
		past.players = _int(yd.get("players"), 0)
		past.settled = bool(yd.get("settled", false))
		var me: Variant = yd.get("me")
		if me is Dictionary:
			past.rank = _int((me as Dictionary).get("rank"), 0)
			past.score = _int((me as Dictionary).get("score"), -1)
		var top: Variant = yd.get("top", [])
		if top is Array:
			for row: Variant in top:
				if not row is Dictionary:
					continue
				var r := row as Dictionary
				var e := LeaderboardBoard.Entry.new(
					_int(r.get("rank"), 0),
					str(r.get("name", "")),
					str(r.get("flyer", "")),
					_int(r.get("score"), 0)
				)
				e.run_id = _int(r.get("run"), 0)
				past.top.append(e)
		info.yesterday = past
	return info


## A JSON number (or null) as an int.
static func _int(v: Variant, fallback: int) -> int:
	if v is int or v is float:
		return int(v)
	return fallback
