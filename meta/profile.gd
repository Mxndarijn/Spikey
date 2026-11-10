class_name Profile
extends RefCounted
## The player's save: gold and diamonds, best score, what they own and use,
## rooms met, reached, cleared and died in, the leaderboard name, and whether the first start
## (free flyer and world handed out) is done. Settings and free revives are
## parts of it (PlayerSettings, DailyRevives) saved in the same file. Stored as
## JSON in user:// through SafeFile, so a crash mid-save never loses it.

const PATH := "user://profile.json"
## Save format. Each version only added keys (older saves load with the new
## ones at their defaults); _migrate() is where a change to an existing key
## would go.
## 2: met rooms and per-room clear counts.
## 3: diamonds and bought packs.
## 4: the copy on the server (cloud_revision, cloud_coins).
## 5: per-room reached and death counts (room_reached, room_deaths).
const VERSION := 5
## Keys that belong to this phone, not to the player: never sent to the server
## and never taken from it (cloud_dict, merge_cloud). Diamonds live in the
## server's wallet; the prize spot and the free revives are checked against the
## server on their own; the alert and test-ad switches go with this phone's
## notification permission and build.
const LOCAL_KEYS: Array[String] = [
	"diamonds",
	"daily_spot_rank",
	"daily_spot_until",
	"push_asked",
	"free_revives_used",
	"free_revives_day",
	"board_alerts",
	"test_ads",
	"cloud_revision",
	"cloud_coins",
]

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
## Room id -> times a real run reached it (started in it or moved into it).
## Saves from before version 5 start at the clears, or 1 for a met room.
var room_reached := {}
## Room id -> crashes in it in real runs. A crash that is then revived still
## counts, so a room can have more deaths than reaches.
var room_deaths := {}
## The name other players see on the leaderboards; "" until the player picks one.
var leaderboard_name := ""
## The Settings sheet.
var settings := PlayerSettings.new()
## Revives without an ad, per day.
var revives := DailyRevives.new()
## The OS permission prompt for notifications was shown (it is shown once,
## after the first top-10 finish).
var push_asked := false
## The revision of the server's copy this save last matched (0: never synced,
## for example a fresh install), and the gold it held then. Gold earned or
## spent since is `coins - cloud_coins`, which a merge adds to the server's gold.
var cloud_revision := 0
var cloud_coins := 0
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


## A real run started in this room or moved into it.
func record_room_reached(id: String) -> void:
	if id.is_empty():
		return
	record_room_met(id)
	room_reached[id] = reached(id) + 1


## A real run survived all of this room's points.
func record_room_cleared(id: String) -> void:
	if id.is_empty():
		return
	record_room_met(id)
	room_clears[id] = clears(id) + 1


## A real run crashed in this room (revived or not).
func record_room_death(id: String) -> void:
	if id.is_empty():
		return
	record_room_met(id)
	room_deaths[id] = deaths(id) + 1


func has_met_room(id: String) -> bool:
	return id in met_rooms


func clears(id: String) -> int:
	return int(room_clears.get(id, 0))


func reached(id: String) -> int:
	return int(room_reached.get(id, 0))


func deaths(id: String) -> int:
	return int(room_deaths.get(id, 0))


## Clears per reach as a whole percent (0 when never reached). Each clear was
## reached, so the reaches count as at least the clears.
func clear_rate(id: String) -> int:
	var n := maxi(reached(id), clears(id))
	if n <= 0:
		return 0
	return roundi(100.0 * clears(id) / n)


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
				"room_reached": room_reached,
				"room_deaths": room_deaths,
				"leaderboard_name": leaderboard_name,
				"push_asked": push_asked,
				"cloud_revision": cloud_revision,
				"cloud_coins": cloud_coins,
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
	p.cloud_revision = maxi(int(d.get("cloud_revision", 0)), 0)
	p.cloud_coins = maxi(int(d.get("cloud_coins", 0)), 0)
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
	p.room_clears = _read_counts(d.get("room_clears", {}))
	p.room_reached = _read_counts(d.get("room_reached", {}))
	p.room_deaths = _read_counts(d.get("room_deaths", {}))
	for counts: Dictionary in [p.room_clears, p.room_reached, p.room_deaths]:
		for id: String in counts:
			p.record_room_met(id)
	var known := p.to_dict()
	for key: Variant in d:
		if not known.has(key):
			p._unknown[key] = d[key]
	return p


## Room id -> count from saved data: only string ids with a count above 0.
static func _read_counts(saved: Variant) -> Dictionary:
	var out := {}
	if not saved is Dictionary:
		return out
	for id: Variant in saved:
		var v: Variant = saved[id]
		var n := int(v) if v is float or v is int else 0
		if id is String and n > 0:
			out[id] = n
	return out


## The part of the save the server keeps (everything but LOCAL_KEYS).
func cloud_dict() -> Dictionary:
	var d := to_dict()
	for key in LOCAL_KEYS:
		d.erase(key)
	return d


## The server kept this save as `revision`; `coins_sent` is the gold it held.
func mark_cloud_saved(revision: int, coins_sent: int) -> void:
	cloud_revision = maxi(revision, 0)
	cloud_coins = maxi(coins_sent, 0)


## Takes in the server's copy (`cloud`, at `revision`) when this save was not
## based on it: on a fresh install, or after another save reached the server
## first. Changes this profile in place (screens hold on to it).
## - Collections join: owned items, bought packs, met rooms; per-room clears,
##   reaches and deaths, best score and run count take the higher (so a merge
##   never counts a run twice; runs played on two phones between syncs keep
##   the larger side); onboarded stays once done.
## - Gold: the server's, plus what this phone earned or spent since its last
##   sync.
## - Choices (what is worn, settings, the board name): the server's when this
##   phone never synced (a reinstall keeps the old look), else this phone's,
##   the newest edit.
## Keys only a newer build knows are taken from the server when missing here.
func merge_cloud(cloud: Profile, revision: int) -> void:
	var never_synced := cloud_revision == 0
	coins = maxi(cloud.coins + coins - cloud_coins, 0)
	best_score = maxi(best_score, cloud.best_score)
	runs = maxi(runs, cloud.runs)
	onboarded = onboarded or cloud.onboarded
	for kind: String in cloud.owned:
		for id: String in cloud.owned[kind]:
			if owned.has(kind):
				grant(kind, id)
	for pack_id in cloud.packs_bought:
		if pack_id not in packs_bought:
			packs_bought.append(pack_id)
	for id in cloud.met_rooms:
		record_room_met(id)
	for id: String in cloud.room_clears:
		room_clears[id] = maxi(clears(id), cloud.clears(id))
	for id: String in cloud.room_reached:
		room_reached[id] = maxi(reached(id), cloud.reached(id))
	for id: String in cloud.room_deaths:
		room_deaths[id] = maxi(deaths(id), cloud.deaths(id))
	if never_synced:
		for kind: String in cloud.equipped:
			equip(kind, cloud.equipped_id(kind))
		var choices := {}
		cloud.settings.write_to(choices)
		for key in LOCAL_KEYS:
			choices.erase(key)
		settings.read_from(choices)
		if not cloud.leaderboard_name.is_empty():
			leaderboard_name = cloud.leaderboard_name
	for key: Variant in cloud._unknown:
		if not _unknown.has(key):
			_unknown[key] = cloud._unknown[key]
	_newer_version = maxi(_newer_version, cloud._newer_version)
	cloud_revision = maxi(revision, 0)
	cloud_coins = cloud.coins


## Brings an older save up to VERSION. Most steps only added keys, which load
## at their defaults.
## 4 -> 5: reaches were not counted before, so each room starts at its clears
## (every clear was reached), or 1 for a room met but never cleared. Deaths
## start at 0.
static func _migrate(saved: Dictionary) -> Dictionary:
	var d := saved.duplicate()
	var from := int(d.get("version", 1))
	if from < 5 and not d.has("room_reached"):
		var reached_from := _read_counts(d.get("room_clears", {}))
		var met: Variant = d.get("met_rooms", [])
		if met is Array:
			for id: Variant in met:
				if id is String and not reached_from.has(id):
					reached_from[id] = 1
		d["room_reached"] = reached_from
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
