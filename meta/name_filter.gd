class_name NameFilter
extends RefCounted
## The bad-word check for leaderboard names, so the name dialog can say "pick
## another" while the player types. The database has the final say
## (supabase/migrations/20261108210000_name_filter.sql, table banned_words, which
## can grow in the dashboard); this starter list must match that file's
## (tests/unit/test_name_filter.gd checks it).
## A look-alike digit standing alone counts as a letter (0 o, 1 i, 3 e, 4 a, 5 s,
## 7 t; "17" stays a number), and the name
## is also checked with repeated letters squashed ("fuuuck"). ANYWHERE words are
## found inside the name; WHOLE words (short ones hiding in normal words: "ass" in
## "classic") only when a part of the
## name between dots, underscores or digits, or the whole name, is that word.

const ANYWHERE: Array[String] = [
	"fuck",
	"shit",
	"cunt",
	"bitch",
	"whore",
	"slut",
	"wank",
	"pussy",
	"penis",
	"vagina",
	"porn",
	"rapist",
	"nigger",
	"nigga",
	"faggot",
	"retard",
	"tranny",
	"nazi",
	"hitler",
	"kkk",
	"kanker",
	"tering",
	"tyfus",
	"hoer",
	"klootzak",
	"flikker",
	"neuk",
	"mongool",
	"godver",
]
const WHOLE: Array[String] = [
	"ass",
	"arse",
	"dick",
	"cock",
	"twat",
	"prick",
	"cum",
	"rape",
	"fag",
	"anal",
	"kike",
	"spic",
	"chink",
	"kut",
	"lul",
	"pik",
	"sex",
	"tit",
	"tits",
]
const LOOK_ALIKES := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"}


static func is_allowed(player_name: String) -> bool:
	# A digit standing alone reads as a letter ("sh1t", "4ss"); a number ("17") stays one.
	var lower := player_name.to_lower()
	var text := ""
	for i in lower.length():
		var c := lower[i]
		var alone := (
			(i == 0 or not lower[i - 1].is_valid_int())
			and (i == lower.length() - 1 or not lower[i + 1].is_valid_int())
		)
		text += LOOK_ALIKES.get(c, c) if alone else c
	# The name's letters and its parts, each as typed and with repeats squashed;
	# the banned words stay as written ("kkk" must not become "k").
	var flat := ""
	var parts: Array[String] = []
	var part := ""
	for c in text:
		if c >= "a" and c <= "z":
			flat += c
			part += c
		elif not part.is_empty():
			parts.append(part)
			part = ""
	if not part.is_empty():
		parts.append(part)
	var flats := [flat, collapse(flat)]
	var all_parts := parts.duplicate()
	for p in parts:
		all_parts.append(collapse(p))
	for w in ANYWHERE:
		for f: String in flats:
			if w in f:
				return false
	for w in WHOLE:
		if w in flats or w in all_parts:
			return false
	return true


## "fuuuck" -> "fuck": each run of the same letter counts once.
static func collapse(text: String) -> String:
	var out := ""
	for c in text:
		if out.is_empty() or out[out.length() - 1] != c:
			out += c
	return out
