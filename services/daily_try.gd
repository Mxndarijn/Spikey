class_name DailyTry
extends RefCounted
## One started try on today's Daily Run (start_daily_try): the server's id for
## it, which try of the day it is, and the day's seed and season. The run is
## played on exactly this seed and season and sent back with the id.

## Why a try could not start.
enum Problem { NONE, OFFLINE, NO_TRIES }

var problem := Problem.NONE
## The server's id of this try (a UUID); sent back with the run.
var id := ""
## 1 for the day's first try.
var n := 0
var tries_max := DailyRunRules.TRIES_PER_DAY
var seed_value := 0
var season := Seasons.NONE
var day := ""
var number := 0


static func failed(why: Problem) -> DailyTry:
	var t := DailyTry.new()
	t.problem = why
	return t


func ok() -> bool:
	return problem == Problem.NONE


## start_daily_try's answer, or a failed try (OFFLINE) when it isn't one.
static func parse(data: Variant) -> DailyTry:
	if not data is Dictionary:
		return failed(Problem.OFFLINE)
	var d := data as Dictionary
	var raw_seed: Variant = d.get("seed")
	if not (raw_seed is int or raw_seed is float) or str(d.get("try", "")).is_empty():
		return failed(Problem.OFFLINE)
	var t := DailyTry.new()
	t.id = str(d.get("try", ""))
	t.n = int(d.get("n", 1))
	t.tries_max = maxi(int(d.get("tries_max", DailyRunRules.TRIES_PER_DAY)), 1)
	t.seed_value = int(raw_seed)
	var s: Variant = d.get("season")
	t.season = int(s) if s is int or s is float else Seasons.NONE
	t.day = str(d.get("day", ""))
	t.number = int(d.get("number", 0))
	return t
