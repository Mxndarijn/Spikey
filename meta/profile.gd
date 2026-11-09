class_name Profile
extends RefCounted
## The player's save: coins, best score, what they own and use, and whether
## the first start (free flyer and world handed out) is done. Stored as JSON
## in user://.

const PATH := "user://profile.json"
## 2: met rooms and per-room clear counts (version 1 saves load with none).
## 3: diamonds and bought packs (older saves load with none).
const VERSION := 3

## Gold: collected in runs (Economy).
var coins := 0
## Diamonds: rare, won on the daily board or bought (Economy, DiamondPacks).
var diamonds := 0
## Ids of the diamond packs bought (a once-only pack can't be bought again).
var packs_bought: Array[String] = []
var best_score := 0
var runs := 0
var onboarded := false
## kind -> owned ids (Catalog.FLYER, WORLD, TRAIL, PORTAL, MUSIC)
var owned := {}
## kind -> equipped id
var equipped := {}
## Room ids (RoomCatalog) met in real runs: these are open for practice.
var met_rooms: Array[String] = []
## Room id -> times cleared in real runs (all of its points survived).
var room_clears := {}
## The name other players see on the leaderboards; "" until the player picks one.
var leaderboard_name := ""
## Sound settings: volumes 0..100 and on/off switches.
var music_volume := 80
var sfx_volume := 100
var music_on := true
var sfx_on := true
## Settings > Play (the Settings sheet behind the Home gear).
## A little buzz on flap and crash.
var haptics := true
## No room flash or shake, slow sky fades (RoomView.flash_enabled follows it).
var reduced_flashing := false
## Spikes turn dark with a white edge. Read by the room drawing (world-scenes);
## the UI only stores it.
var color_blind_spikes := false
## Pause and other HUD icon buttons grow to 56px (UiKit.large_buttons).
var large_buttons := false


func _init() -> void:
	for kind in Catalog.KINDS:
		owned[kind] = []
		equipped[kind] = ""
	# The default trail and portal are everyone's from the start.
	grant(Catalog.TRAIL, "world_ribbon")
	equipped[Catalog.TRAIL] = "world_ribbon"
	for id in Shop.starters(Catalog.PORTAL):
		grant(Catalog.PORTAL, id)
	equipped[Catalog.PORTAL] = PortalStyle.DEFAULT_ID
	# Music: the two picks and the free starter track; Match my world plays.
	for id in Catalog.MUSIC_PICKS + [MusicTrack.DEFAULT_ID]:
		grant(Catalog.MUSIC, id)
	equipped[Catalog.MUSIC] = MusicTrack.MATCH_WORLD


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


## The exit portal look in use (saved with the rest of `equipped`); older saves
## without one, or with a style that is gone (cloud_hole, ink_splat...), keep
## the default.
func equipped_portal() -> String:
	var id := equipped_id(Catalog.PORTAL)
	return id if Catalog.portal(id) != null else PortalStyle.DEFAULT_ID


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
	return {
		"version": VERSION,
		"coins": coins,
		"diamonds": diamonds,
		"packs_bought": packs_bought,
		"best_score": best_score,
		"runs": runs,
		"onboarded": onboarded,
		"owned": owned,
		"equipped": equipped,
		"met_rooms": met_rooms,
		"room_clears": room_clears,
		"leaderboard_name": leaderboard_name,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"music_on": music_on,
		"sfx_on": sfx_on,
		"haptics": haptics,
		"reduced_flashing": reduced_flashing,
		"color_blind_spikes": color_blind_spikes,
		"large_buttons": large_buttons,
	}


## Builds a profile from saved data, ignoring anything missing or malformed.
static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.coins = maxi(int(d.get("coins", 0)), 0)
	p.diamonds = maxi(int(d.get("diamonds", 0)), 0)
	var packs: Variant = d.get("packs_bought", [])
	if packs is Array:
		for pack_id: Variant in packs:
			if pack_id is String and pack_id not in p.packs_bought:
				p.packs_bought.append(pack_id)
	p.best_score = maxi(int(d.get("best_score", 0)), 0)
	p.runs = maxi(int(d.get("runs", 0)), 0)
	p.onboarded = bool(d.get("onboarded", false))
	var saved_name: Variant = d.get("leaderboard_name", "")
	if saved_name is String and LeaderboardService.is_valid_name(saved_name):
		p.leaderboard_name = saved_name
	p.music_volume = clampi(int(d.get("music_volume", p.music_volume)), 0, 100)
	p.sfx_volume = clampi(int(d.get("sfx_volume", p.sfx_volume)), 0, 100)
	p.music_on = bool(d.get("music_on", true))
	p.sfx_on = bool(d.get("sfx_on", true))
	p.haptics = bool(d.get("haptics", true))
	p.reduced_flashing = bool(d.get("reduced_flashing", false))
	p.color_blind_spikes = bool(d.get("color_blind_spikes", false))
	p.large_buttons = bool(d.get("large_buttons", false))
	var saved_owned: Variant = d.get("owned", {})
	if saved_owned is Dictionary:
		for kind in Catalog.KINDS:
			var list: Variant = saved_owned.get(kind, [])
			if list is Array:
				for id: Variant in list:
					if id is String:
						p.grant(kind, id)
	var saved_equipped: Variant = d.get("equipped", {})
	if saved_equipped is Dictionary:
		for kind in Catalog.KINDS:
			var id: Variant = saved_equipped.get(kind, "")
			if id is String:
				p.equip(kind, id)
	# A portal style that is gone falls back to Match my world.
	p.equipped[Catalog.PORTAL] = p.equipped_portal()
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
	return p


func save(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true


## Loads the save, or a fresh profile when there is none (first start).
static func load_or_new(path: String = PATH) -> Profile:
	if not FileAccess.file_exists(path):
		return Profile.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(data) if data is Dictionary else Profile.new()
