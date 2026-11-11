class_name EarnStatus
extends RefCounted
## What the Earn diamonds screen shows about the player's own progress: their
## best checked score, the milestones won and the current streak (EarnRules).
## Comes from the server (get_earn_status in supabase/migrations/); `known`
## is false when it was guessed on the phone (offline, or no server at all).

## From the server just now. False: a guess from the save (see from_profile).
var known := false
var best := 0
## Milestone scores won (claimed or not), lowest first.
var milestones: Array[int] = []
## Days in a row with a checked run, ending today or yesterday (0: none).
## -1: not known (offline before the server ever answered).
var streak := 0
var played_today := false
## Streak diamonds won in the current row.
var streak_won := 0


## A guess from the save while the server can't be asked: the best score on
## this phone, the milestones it reaches, and no streak (-1: unknown).
static func from_profile(profile: Profile) -> EarnStatus:
	var s := EarnStatus.new()
	s.best = profile.best_score
	s.milestones = EarnRules.reached(profile.best_score)
	s.streak = -1
	return s


## get_earn_status's answer, or null when it is not one.
static func parse(data: Variant) -> EarnStatus:
	if not data is Dictionary or not (data as Dictionary).has("best"):
		return null
	var d := data as Dictionary
	var s := EarnStatus.new()
	s.known = true
	s.best = maxi(int(d.get("best", 0)), 0)
	var raw: Variant = d.get("milestones", [])
	if raw is Array:
		for item: Variant in raw:
			var score := int(item)
			if EarnRules.milestone_prize(score) > 0 and not s.milestones.has(score):
				s.milestones.append(score)
	s.milestones.sort()
	s.streak = maxi(int(d.get("streak", 0)), 0)
	s.played_today = bool(d.get("played_today", false)) and s.streak > 0
	s.streak_won = maxi(int(d.get("streak_won", 0)), 0)
	return s


## The same numbers, marked as not fresh (shown again while offline).
func stale() -> EarnStatus:
	var s := EarnStatus.new()
	s.best = best
	s.milestones = milestones.duplicate()
	s.streak = streak
	s.played_today = played_today
	s.streak_won = streak_won
	return s
