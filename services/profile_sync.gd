class_name ProfileSync
extends RefCounted
## Keeps a copy of the player's save on the server (sync_profile in
## supabase/migrations/20261110150000_profiles.sql), so a reinstall that signs
## in as the same player (SupabaseClient's device key) gets its flyers, worlds,
## gold and rooms back. The save on the phone stays the one the game plays
## from; this only sends it after it changed and takes in the server's copy
## when the two went apart (Profile.merge_cloud).
## Every answer also lists the premium items this player bought with
## diamonds (20261110160000_paid_items.sql); they are granted here, so a
## reinstall gets them back even without the old save.
## Without a server (no Supabase config, tests) it does nothing.

## A sync finished. merged: the server's copy changed the save (worn items,
## gold, settings), so the look and the screens should be drawn again. The
## save should be written either way (the revision moved).
signal synced(merged: bool)

const SAVED := "saved"
const CONFLICT := "conflict"
## Merges in a row before giving up until the next save (two phones saving
## at the same moment, over and over).
const MAX_MERGES := 3

var _profile: Profile
var _api: SupabaseClient
var _busy := false
var _again := false
## What the server last took, to skip a call when nothing changed.
var _last_sent := ""


func _init(profile: Profile, api: SupabaseClient) -> void:
	_profile = profile
	_api = api


func is_online() -> bool:
	return _api != null


## Sends the save when it changed since the last one the server took. A call
## while one is on its way is sent after it, once.
func push() -> void:
	if _api == null:
		return
	if _busy:
		_again = true
		return
	_busy = true
	var merged := false
	_again = true
	while _again:
		_again = false
		merged = await _sync_once() or merged
	_busy = false
	synced.emit(merged)


func _sync_once() -> bool:
	var merged := false
	for attempt in MAX_MERGES:
		var data := _profile.cloud_dict()
		var text := JSON.stringify(data)
		if text == _last_sent and _profile.cloud_revision > 0:
			return merged
		var coins := _profile.coins
		var res := await _api.call_db(
			"sync_profile", {"p_data": data, "p_base": _profile.cloud_revision}
		)
		var answer := parse_answer(res)
		if grant_paid(_profile, answer.paid):
			merged = true
		if answer.status == SAVED:
			_profile.mark_cloud_saved(answer.revision, coins)
			_last_sent = text
			return merged
		if answer.status != CONFLICT:
			return merged
		_profile.merge_cloud(Profile.from_dict(answer.data), answer.revision)
		merged = true
	return merged


## Grants the bought items ("kind:id") the save is missing. True when it
## changed. Unknown kinds are skipped; Catalog.repair() handles unknown ids.
static func grant_paid(profile: Profile, paid: Array[String]) -> bool:
	var changed := false
	for ref in paid:
		var parts := ref.split(":", false, 1)
		if parts.size() != 2 or parts[0] not in ItemKind.ALL:
			continue
		if not profile.owns(parts[0], parts[1]):
			profile.grant(parts[0], parts[1])
			changed = true
	return changed


## sync_profile's answer as {"status": SAVED, CONFLICT or "" (no answer, or
## not one), "revision": int, "data": Dictionary (CONFLICT: the server's copy),
## "paid": Array[String] (bought premium items, "kind:id")}.
static func parse_answer(res: Dictionary) -> Dictionary:
	var paid: Array[String] = []
	var none := {"status": "", "revision": 0, "data": {}, "paid": paid}
	if not res.get("ok", false) or not res.get("data") is Dictionary:
		return none
	var d := res.data as Dictionary
	var raw: Variant = d.get("paid", [])
	if raw is Array:
		for ref: Variant in raw:
			if ref is String:
				paid.append(ref)
	var status := str(d.get("status", ""))
	var revision := int(d.get("revision", 0))
	if revision < 1:
		return none
	if status == SAVED:
		return {"status": SAVED, "revision": revision, "data": {}, "paid": paid}
	if status == CONFLICT and d.get("data") is Dictionary:
		return {"status": CONFLICT, "revision": revision, "data": d.data, "paid": paid}
	return none
