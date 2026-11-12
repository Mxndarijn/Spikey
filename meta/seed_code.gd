class_name SeedCode
extends RefCounted
## A seed as players see and type it: one code that holds everything that
## decides a run's map, so one code always plays the same.
##
##   K7Q2M-9XH4D   10 characters, Crockford base 32, two groups of five.
##
## The first character is a check letter (22 letters: never a digit, so a code
## is never mistaken for an old plain seed number). The other nine hold 45
## bits, high to low: the random part (32 bits, the GameSim seed), the season
## (3 bits: 0 none, 1-6 = Seasons.* + 1) and the gameplay version (10 bits).
## The sim never sees the code: it gets the random part and the season, and
## runs keep storing seed, season and version apart (run files, Supabase).
##
## Typing is forgiving: any case, dashes and spaces skipped, O reads as 0 and
## I or L as 1. Old seeds (a plain number up to MAX_RANDOM, maybe with a
## "v11" tag after it, from the old game over line) still parse, as legacy.

const DIGITS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CHECKS := "ABCDEFGHJKMNPQRSTVWXYZ"
const LENGTH := 10
## Seeds of real runs are randi(): 0 up to this.
const MAX_RANDOM := 4294967295
const MAX_VERSION := 1023
const SEASON_BITS := 3
const VERSION_BITS := 10
const _MASK32 := 0xFFFFFFFF


## What a code (or an old seed number) holds.
class Parts:
	extends RefCounted
	## The GameSim seed.
	var random := 0
	## Seasons.*.
	var season := Seasons.NONE
	## The gameplay version it was made on; -1 when an old seed doesn't say.
	var version := -1
	## An old plain seed number, not a code: it holds no season.
	var legacy := false

	func _init(p_random: int = 0, p_season: int = Seasons.NONE, p_version: int = -1) -> void:
		random = p_random
		season = p_season
		version = p_version


## The code for a seed, e.g. "K7Q2M-9XH4D". `random` 0..MAX_RANDOM, `season`
## Seasons.NONE or 0..COUNT-1, `version` 0..MAX_VERSION; "" when one is out of range.
static func encode(random: int, season: int, version: int) -> String:
	if random < 0 or random > MAX_RANDOM or version < 0 or version > MAX_VERSION:
		return ""
	if season < Seasons.NONE or season >= Seasons.COUNT:
		return ""
	var payload := (random << (SEASON_BITS + VERSION_BITS)) | ((season + 1) << VERSION_BITS)
	payload |= version
	var chars := CHECKS[_check(payload)]
	for i in range(LENGTH - 2, -1, -1):
		chars += DIGITS[(payload >> (5 * i)) & 31]
	return chars.substr(0, 5) + "-" + chars.substr(5)


## The code of the current build for a seed and season.
static func current(random: int, season: int) -> String:
	return encode(random, season, SimConfig.GAMEPLAY_VERSION)


## The seed in `text`: a code anywhere in it (the whole game over line works),
## else an old seed number; null when there is neither, or a code's check
## letter doesn't match.
static func decode(text: String) -> Parts:
	var words := _words(text)
	for i in words.size():
		var parts := _code(words[i])
		if parts == null and i + 1 < words.size():
			parts = _code(words[i] + words[i + 1])
		if parts != null:
			return parts
	return _legacy(words)


## Why `text` is not a seed, for the picker's note ("" when it is one).
static func problem(text: String) -> String:
	if decode(text) != null:
		return ""
	for w in _words(text):
		if w.length() == LENGTH and _valid(w) and CHECKS.find(w[0]) >= 0:
			return "Not a seed: check the letters"
	return "Not a seed: a code like K7Q2M-9XH4D"


## "Halloween · v21", "No season · v21", or for an old seed "Old seed · v11".
static func describe(parts: Parts) -> String:
	var season_name := SeasonCalendar.display_name(parts.season)
	if season_name.is_empty():
		season_name = "Old seed" if parts.legacy else "No season"
	if parts.version < 0:
		return season_name
	return "%s · v%d" % [season_name, parts.version]


static func _code(word: String) -> Parts:
	if word.length() != LENGTH or not _valid(word):
		return null
	var check := CHECKS.find(word[0])
	if check < 0:
		return null
	var payload := 0
	for i in range(1, LENGTH):
		payload = (payload << 5) | DIGITS.find(word[i])
	if _check(payload) != check:
		return null
	var version := payload & ((1 << VERSION_BITS) - 1)
	var season := ((payload >> VERSION_BITS) & ((1 << SEASON_BITS) - 1)) - 1
	if season >= Seasons.COUNT:
		return null
	return Parts.new(payload >> (SEASON_BITS + VERSION_BITS), season, version)


## An old seed: the first all-digit word, with the version from a "v11" word.
static func _legacy(words: PackedStringArray) -> Parts:
	var found: Parts = null
	for w in words:
		if found == null and _all_digits(w):
			# More than 10 digits never fits; checked first so the int can't overflow.
			if w.length() > 10 or w.to_int() > MAX_RANDOM:
				return null
			found = Parts.new(w.to_int(), Seasons.NONE, -1)
			found.legacy = true
		elif found != null and w.length() > 1 and w[0] == "V" and _all_digits(w.substr(1)):
			if w.length() <= 5:
				found.version = w.substr(1).to_int()
			break
	return found


## Words of `text`, upper case, dashes dropped, O -> 0 and I/L -> 1 (check
## letters never use O, I or L).
static func _words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var word := ""
	for c in text.to_upper() + " ":
		if c == "-":
			continue
		if c == "O":
			c = "0"
		elif c == "I" or c == "L":
			c = "1"
		if (c >= "0" and c <= "9") or (c >= "A" and c <= "Z"):
			word += c
		elif not word.is_empty():
			out.append(word)
			word = ""
	return out


static func _valid(word: String) -> bool:
	for c in word:
		if DIGITS.find(c) < 0:
			return false
	return true


static func _all_digits(word: String) -> bool:
	if word.is_empty():
		return false
	for c in word:
		if c < "0" or c > "9":
			return false
	return true


## 0..CHECKS.length()-1 from the 45-bit payload.
static func _check(payload: int) -> int:
	var x := (payload & _MASK32) ^ (((payload >> 32) * 0x85EBCA6B) & _MASK32)
	x = ((x ^ (x >> 16)) * 0x7FEB352D) & _MASK32
	x = ((x ^ (x >> 15)) * 0x2C1B3C6D) & _MASK32
	x ^= x >> 16
	return x % CHECKS.length()
