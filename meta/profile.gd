class_name Profile
extends RefCounted
## The player's save: gold and diamonds, best score, what they own and use,
## rooms met and cleared, the leaderboard name, and whether the first start
## (free flyer and world handed out) is done. Settings and free revives are
## parts of it (PlayerSettings, DailyRevives) saved in the same file. Stored as
## JSON in user:// through SafeFile, so a crash mid-save never loses it.

const PATH := "user://profile.json"
## Save format. Each version only added keys (older saves load with the new
## ones at their defaults); _migrate() is where a change to an existing key
## would go.
## 2: met rooms and per-room clear counts.
## 3: diamonds and bought packs.
const VERSION := 3

## Gold: collected in runs (Economy).
var coins := 0
## Diamonds: rare, won on the daily board or bought (Economy, DiamondPacks).
var diamonds := 0
## Ids of the diamond packs bought (a once-only pack can't be bought again).
var packs_bought: Array[String] = []
## The player's place on today's board when it was last loaded (0: none) and
## the time (unix seconds) that board ends, to notice a lost prize spot.
var daily_spot_rank := 0
var daily_spot_until := 0
var best_score := 0
var runs := 0
var onboarded := false
## kind (ItemKind) -> owned ids
var owned := {}
## kind -> equipped id
var equipped := {}
## Room ids (RoomCatalog) met in real runs: these are open for practice.
var met_rooms: Array[String] = []
## Room id -> times cleared in real runs (all of its points survived).
var room_clears := {}
## The name other players see on the leaderboards; "" until the player picks one.
var leaderboard_name := ""
## The Settings sheet.
var settings := PlayerSettings.new()
## Revives without an ad, per day.
var revives := DailyRevives.new()
## The OS permission prompt for notifications was shown (it is shown once,
## after the first top-10 finish).
var push_asked := false
## Keys a newer version of the game saved that this one doesn't know: written
## back as they were, so opening an older build never deletes them.
var _unknown := {}
## The version of the build that wrote the save, when newer than this one: kept,
## so the newer build doesn't take its own save for an old one.
var _newer_version := 0


func _init() -> void:
	for kind in ItemKind.ALL:
		owned[kind] = []
		equipped[kind] = ""
	# The free defaults are everyone's from the start, and in use.
	for kind: String in ItemKind.STARTERS:
		for id: String in ItemKind.STARTERS[kind]:
			grant(kind, id)
	for kind: String in ItemKind.DEFAULTS:
		equipped[kind] = ItemKind.DEFAULTS[kind]


func owns(kind: String, id: String) -> bool:
	return id in owned.get(kind, [])


func grant(kind: String, id: String) -> void:
	if not owns(kind, id):
		owned[kind].append(id)


## Uses an owned item. Returns false if the player doesn't own it.
func equip(kind: String, id: String) -> bool:
	if not owns(kind, id):
		return false
	equipped[kind] = id
	return true


func equipped_id(kind: String) -> String:
	return equipped.get(kind, "")


## Records a finished run and adds the coins collected in it.
## Both numbers come from the replay, so a server can verify them.
func record_run(score: int, coins_collected: int) -> int:
	runs += 1
	best_score = maxi(best_score, score)
	var earned := maxi(coins_collected, 0)
	coins += earned
	return earned


## A real run entered this room; practice runs never call this.
func record_room_met(id: String) -> void:
	if not id.is_empty() and id not in met_rooms:
		met_rooms.append(id)


## A real run survived all of this room's points.
func record_room_cleared(id: String) -> void:
	if id.is_empty():
		return
	record_room_met(id)
	room_clears[id] = clears(id) + 1


func has_met_room(id: String) -> bool:
	return id in met_rooms


func clears(id: String) -> int:
	return int(room_clears.get(id, 0))


func total_clears() -> int:
	var n := 0
	for id: String in room_clears:
		n += clears(id)
	return n


func to_dict() -> Dictionary:
	var d := _unknown.duplicate()
	(
		d
		. merge(
			{
				"version": maxi(VERSION, _newer_version),
				"coins": coins,
				"diamonds": diamonds,
				"packs_bought": packs_bought,
				"daily_spot_rank": daily_spot_rank,
				"daily_spot_until": daily_spot_until,
				"best_score": best_score,
				"runs": runs,
				"onboarded": onboarded,
				"owned": owned,
				"equipped": equipped,
				"met_rooms": met_rooms,
				"room_clears": room_clears,
				"leaderboard_name": leaderboard_name,
				"push_asked": push_asked,
			},
			true
		)
	)
	settings.write_to(d)
	revives.write_to(d)
	return d


## Builds a profile from saved data, ignoring anything missing or malformed.
## Equipped ids are kept as saved; Catalog.repair() swaps any that are gone.
static func from_dict(saved: Dictionary) -> Profile:
	var d := _migrate(saved)
	var p := Profile.new()
	var version := int(d.get("version", VERSION))
	if version > VERSION:
		p._newer_version = version
	p.coins = maxi(int(d.get("coins", 0)), 0)
	p.diamonds = maxi(int(d.get("diamonds", 0)), 0)
	p.daily_spot_rank = maxi(int(d.get("daily_spot_rank", 0)), 0)
	p.daily_spot_until = maxi(int(d.get("daily_spot_until", 0)), 0)
	var packs: Variant = d.get("packs_bought", [])
	if packs is Array:
		for pack_id: Variant in packs:
			if pack_id is String and pack_id not in p.packs_bought:
				p.packs_bought.append(pack_id)
	p.best_score = maxi(int(d.get("best_score", 0)), 0)
	p.runs = maxi(int(d.get("runs", 0)), 0)
	p.onboarded = bool(d.get("onboarded", false))
	var saved_name: Variant = d.get("leaderboard_name", "")
	if saved_name is String and PlayerName.is_valid(saved_name):
		p.leaderboard_name = saved_name
	p.settings.read_from(d)
	p.revives.read_from(d)
	p.push_asked = bool(d.get("push_asked", false))
	var saved_owned: Variant = d.get("owned", {})
	if saved_owned is Dictionary:
		for kind in ItemKind.ALL:
			var list: Variant = saved_owned.get(kind, [])
			if list is Array:
				for id: Variant in list:
					if id is String:
						p.grant(kind, id)
	var saved_equipped: Variant = d.get("equipped", {})
	if saved_equipped is Dictionary:
		for kind in ItemKind.ALL:
			var id: Variant = saved_equipped.get(kind, "")
			if id is String:
				p.equip(kind, id)
	var met: Variant = d.get("met_rooms", [])
	if met is Array:
		for id: Variant in met:
			if id is String:
				p.record_room_met(id)
	var saved_clears: Variant = d.get("room_clears", {})
	if saved_clears is Dictionary:
		for id: Variant in saved_clears:
			var n := (
				int(saved_clears[id]) if saved_clears[id] is float or saved_clears[id] is int else 0
			)
			if id is String and n > 0:
				p.room_clears[id] = n
				p.record_room_met(id)
	var known := p.to_dict()
	for key: Variant in d:
		if not known.has(key):
			p._unknown[key] = d[key]
	return p


## Brings an older save up to VERSION. Every step so far only added keys, which
## load at their defaults, so there is nothing to change yet.
static func _migrate(saved: Dictionary) -> Dictionary:
	var d := saved.duplicate()
	var from := int(d.get("version", 1))
	if from < VERSION:
		d["version"] = VERSION
	return d


## Writes the save. Returns false when it could not be written; the last good
## save is then still there.
func save(path: String = PATH) -> bool:
	return SafeFile.write_json(path, to_dict())


## Loads the save (or its backup when the save is broken), or a fresh profile
## when there is none (first start).
static func load_or_new(path: String = PATH) -> Profile:
	var data: Variant = SafeFile.read_json(path)
	return from_dict(data) if data is Dictionary else Profile.new()
