class_name PlayerName
extends RefCounted
## The rules for the name other players see on the leaderboards.

const MIN := 3
const MAX := 14
const FIRST: Array[String] = ["Swift", "Zippy", "Lucky", "Brave", "Bouncy", "Sunny"]
const LAST: Array[String] = ["Buzz", "Flap", "Wing", "Hop", "Dash"]


## What is wrong with a leaderboard name, or "" when it is fine.
static func problem(text: String) -> String:
	if text.length() < MIN:
		return "Use at least %d characters." % MIN
	if text.length() > MAX:
		return "Use at most %d characters." % MAX
	for c in text:
		var ok := (
			(c >= "a" and c <= "z")
			or (c >= "A" and c <= "Z")
			or (c >= "0" and c <= "9")
			or c == "."
			or c == "_"
		)
		if not ok:
			return "Only letters, numbers, dots and underscores."
	if not NameFilter.is_allowed(text):
		return "That name isn't allowed. Pick another one."
	return ""


static func is_valid(text: String) -> bool:
	return problem(text).is_empty()


## A random friendly name ("ZippyFlap42"), always valid.
static func suggest(rng: RandomNumberGenerator) -> String:
	return (
		"%s%s%d"
		% [
			FIRST[rng.randi_range(0, FIRST.size() - 1)],
			LAST[rng.randi_range(0, LAST.size() - 1)],
			rng.randi_range(10, 99),
		]
	)
