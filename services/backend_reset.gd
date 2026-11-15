class_name BackendReset
extends RefCounted
## The one-time fresh start when the game moves to a new server
## (docs/SERVER_MIGRATION.md, "The one-time reset on the phones"). The new
## build's backend config names its server (`server_id`); the save remembers the
## server it was used with (Profile.backend_server). On the first launch where
## they differ, before anything signs in, the phone starts over: the old
## server's players, boards and diamonds don't exist on the new one, and the
## first sync would otherwise upload old gold and items to it.
## Cleared: gold, cosmetics, best score, rooms, earn and streak state, the
## cached diamonds, today's Daily Run state, the runs waiting to be sent, the
## old session and device key (file and Keychain) and Your runs.
## Kept: this phone's settings and the leaderboard name.
## The save is written last, so a crash halfway just runs the reset again.

## The old backend's files on this phone.
const OLD_FILES: Array[String] = [
	OnlineLeaderboard.QUEUE_PATH,
	SupabaseClient.SESSION_PATH,
	SupabaseClient.DEVICE_PATH,
]


## Whether this config asks for a fresh start of this save.
static func needed(profile: Profile, config: Dictionary) -> bool:
	var id := str(config.get("server_id", ""))
	return not id.is_empty() and profile.backend_server != id


## Whether the save held anything a player would miss (then the game says
## why it is gone; a new install starts quietly).
static func had_progress(profile: Profile) -> bool:
	return (
		profile.runs > 0
		or profile.coins > 0
		or profile.best_score > 0
		or profile.diamonds > 0
		or not profile.met_rooms.is_empty()
	)


## A new save for `server_id` with the old one's settings and name.
static func fresh_profile(old: Profile, server_id: String) -> Profile:
	var p := Profile.new()
	var kept := {}
	old.settings.write_to(kept)
	p.settings.read_from(kept)
	p.leaderboard_name = old.leaderboard_name
	p.backend_server = server_id
	return p


## Starts this phone over for `server_id`: removes the old backend's files and
## Your runs, clears `profile` in place (settings and name kept) and writes it.
## `files` and `keychain` (null: none) are for tests.
static func apply(
	profile: Profile,
	server_id: String,
	profile_path: String,
	runs_path: String,
	files: Array[String] = OLD_FILES,
	keychain: Object = _keychain()
) -> void:
	for path in files + [runs_path]:
		# With its .tmp and .bak copies, or a read would bring the backup back.
		SafeFile.remove(path)
	if keychain != null:
		keychain.call("write", SupabaseClient.KEYCHAIN_ITEM, "{}")
	clear(profile, server_id)
	profile.save(profile_path)


## Empties `profile` in place, keeping its settings and name: every holder of
## it sees the fresh start (also used when the player moved to another phone).
static func clear(profile: Profile, server_id: String) -> void:
	var fresh := fresh_profile(profile, server_id)
	for prop in fresh.get_property_list():
		if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			profile.set(prop.name, fresh.get(prop.name))


static func _keychain() -> Object:
	var name := BackendClient.KEYCHAIN_SINGLETON
	return Engine.get_singleton(name) if Engine.has_singleton(name) else null
