extends TestCase
## The save's copy on the server: what is sent, how the two copies merge, the
## sync service against a server stand-in, and the device key that signs a
## reinstalled phone in as the same player.

const MIGRATION := "res://supabase/migrations/20261110150000_profiles.sql"
const SESSION := "user://test_sync_session.json"
const DEVICE := "user://test_sync_device_key.json"


## sync_profile as the migration does it, in memory.
class FakeServer:
	extends SupabaseClient
	var data := {}
	var revision := 0
	var calls := 0
	var offline := false
	var paid: Array = []

	func _init() -> void:
		super(null, "https://example.supabase.co", "k")

	func call_db(function: String, body: Dictionary) -> Dictionary:
		calls += 1
		if offline or function != "sync_profile":
			return {"ok": false, "code": 0, "data": null}
		# The body goes over the wire as JSON.
		var sent: Dictionary = JSON.parse_string(JSON.stringify(body))
		if revision == 0 or int(sent.p_base) == revision:
			data = sent.p_data
			revision += 1
			return {
				"ok": true,
				"code": 200,
				"data": {"status": "saved", "revision": revision, "paid": paid}
			}
		return {
			"ok": true,
			"code": 200,
			"data": {"status": "conflict", "revision": revision, "data": data, "paid": paid},
		}


func _played() -> Profile:
	var p := Profile.new()
	p.coins = 120
	p.diamonds = 7
	p.best_score = 64
	p.runs = 30
	p.onboarded = true
	p.grant(ItemKind.FLYER, "dash")
	p.equip(ItemKind.FLYER, "dash")
	p.record_room_cleared("saw_hall")
	p.leaderboard_name = "buzzybee"
	p.settings.music_volume = 20
	p.settings.board_alerts = false
	return p


func test_the_server_copy_leaves_out_what_belongs_to_the_phone() -> void:
	var d := _played().cloud_dict()
	for key in Profile.LOCAL_KEYS:
		assert_false(d.has(key), key + " stays on the phone")
	assert_eq(d.coins, 120)
	assert_eq(d.music_volume, 20, "settings travel")
	assert_true("dash" in d.owned[ItemKind.FLYER])


func test_a_fresh_install_takes_the_old_save_back() -> void:
	var old := _played()
	var fresh := Profile.new()
	fresh.coins = 3  # one run before the first sync
	fresh.runs = 1
	fresh.settings.board_alerts = true
	fresh.merge_cloud(Profile.from_dict(old.cloud_dict()), 5)
	assert_eq(fresh.coins, 123, "the old gold and the new")
	assert_eq(fresh.best_score, 64)
	assert_eq(fresh.runs, 30)
	assert_true(fresh.onboarded)
	assert_true(fresh.owns(ItemKind.FLYER, "dash"))
	assert_eq(fresh.equipped_id(ItemKind.FLYER), "dash", "the old look comes back")
	assert_eq(fresh.clears("saw_hall"), 1)
	assert_eq(fresh.leaderboard_name, "buzzybee")
	assert_eq(fresh.settings.music_volume, 20)
	assert_true(fresh.settings.board_alerts, "this phone's alert switch stays")
	assert_eq(fresh.diamonds, 0, "diamonds come from the wallet, not from here")
	assert_eq(fresh.cloud_revision, 5)
	assert_eq(fresh.cloud_coins, 120)


func test_a_phone_that_synced_keeps_its_own_choices_and_its_gold_since() -> void:
	var server := _played()
	var phone := Profile.from_dict(server.to_dict())
	phone.mark_cloud_saved(4, 120)
	# Meanwhile the server's copy moved on (revision 5) with a new room and
	# 30 more gold; this phone spent 50 and wears something else.
	server.coins = 150
	server.record_room_met("pistons")
	server.settings.music_volume = 90
	phone.coins = 70
	phone.grant(ItemKind.FLYER, "zip")
	phone.equip(ItemKind.FLYER, "zip")
	phone.merge_cloud(Profile.from_dict(server.cloud_dict()), 5)
	assert_eq(phone.coins, 100, "150 on the server, 50 spent here")
	assert_true(phone.has_met_room("pistons"))
	assert_eq(phone.equipped_id(ItemKind.FLYER), "zip", "the newest choice stays")
	assert_eq(phone.settings.music_volume, 20)
	assert_true(phone.owns(ItemKind.FLYER, "dash") and phone.owns(ItemKind.FLYER, "zip"))
	assert_eq([phone.cloud_revision, phone.cloud_coins], [5, 150])


func test_gold_never_goes_below_zero() -> void:
	var server := Profile.new()
	var phone := Profile.new()
	phone.mark_cloud_saved(2, 500)
	phone.coins = 0
	phone.merge_cloud(server, 3)
	assert_eq(phone.coins, 0)


func test_the_sync_fields_survive_a_save() -> void:
	var p := Profile.new()
	p.mark_cloud_saved(9, 44)
	var back := Profile.from_dict(p.to_dict())
	assert_eq([back.cloud_revision, back.cloud_coins], [9, 44])
	var old := Profile.from_dict({"version": 3, "coins": 8})
	assert_eq(old.cloud_revision, 0, "an older save never synced")


func test_first_sync_sends_the_save() -> void:
	var p := _played()
	var server := FakeServer.new()
	var sync := ProfileSync.new(p, server)
	var got: Array = []
	sync.synced.connect(func(merged: bool) -> void: got.append(merged))
	await sync.push()
	assert_eq(got, [false], "nothing to merge")
	assert_eq(server.revision, 1)
	assert_eq(server.data.coins, 120)
	assert_false(server.data.has("diamonds"))
	assert_eq([p.cloud_revision, p.cloud_coins], [1, 120])
	await sync.push()
	assert_eq(server.calls, 1, "nothing changed: no call")
	p.coins += 5
	await sync.push()
	assert_eq([server.calls, server.revision, int(server.data.coins)], [2, 2, 125])


func test_a_reinstall_gets_the_save_back_and_sends_the_merge() -> void:
	var server := FakeServer.new()
	await ProfileSync.new(_played(), server).push()
	var fresh := Profile.new()
	var sync := ProfileSync.new(fresh, server)
	var got: Array = []
	sync.synced.connect(func(merged: bool) -> void: got.append(merged))
	await sync.push()
	assert_eq(got, [true], "the screens are told to redraw")
	assert_true(fresh.owns(ItemKind.FLYER, "dash"))
	assert_eq(fresh.coins, 120)
	assert_eq(server.revision, 2, "the merged save went back up")
	assert_eq(fresh.cloud_revision, 2)


func test_bought_items_come_back_with_a_sync() -> void:
	var p := Profile.new()
	var server := FakeServer.new()
	server.paid = ["flyer:bolt"]
	var sync := ProfileSync.new(p, server)
	var got: Array = []
	sync.synced.connect(func(merged: bool) -> void: got.append(merged))
	await sync.push()
	assert_true(p.owns(ItemKind.FLYER, "bolt"))
	assert_eq(got, [true], "the screens redraw")


func test_offline_the_save_stays_as_it_is() -> void:
	var p := _played()
	var server := FakeServer.new()
	server.offline = true
	var sync := ProfileSync.new(p, server)
	var got: Array = []
	sync.synced.connect(func(merged: bool) -> void: got.append(merged))
	await sync.push()
	assert_eq(got, [false])
	assert_eq(p.cloud_revision, 0)
	assert_eq(p.coins, 120)
	assert_false(ProfileSync.new(p, null).is_online(), "no server: does nothing")


func test_reads_the_server_answers() -> void:
	var saved := {"ok": true, "data": {"status": "saved", "revision": 3}}
	assert_eq(
		ProfileSync.parse_answer(saved), {"status": "saved", "revision": 3, "data": {}, "paid": []}
	)
	var conflict := {
		"ok": true, "data": {"status": "conflict", "revision": 4, "data": {"coins": 1}}
	}
	assert_eq(ProfileSync.parse_answer(conflict).data, {"coins": 1})
	for bad: Dictionary in [
		{"ok": false, "data": null},
		{"ok": true, "data": [1]},
		{"ok": true, "data": {"status": "saved", "revision": 0}},
		{"ok": true, "data": {"status": "conflict", "revision": 2}},
		{"ok": true, "data": {"status": "huh", "revision": 2}},
	]:
		assert_eq(ProfileSync.parse_answer(bad).status, "", str(bad))


## The game's call and the migration agree on the names.
func test_matches_the_migration() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true("function public.sync_profile(p_data jsonb, p_base bigint)" in sql)
	assert_true("'%s'" % ProfileSync.SAVED in sql)
	assert_true("'%s'" % ProfileSync.CONFLICT in sql)


func test_device_keys_are_long_random_and_checked() -> void:
	var a := SupabaseClient.new_device_key()
	var b := SupabaseClient.new_device_key()
	assert_true(SupabaseClient.is_device_key(a), a)
	assert_ne(a, b)
	assert_eq(a.length(), 67)
	assert_false(SupabaseClient.is_device_key(""))
	assert_false(SupabaseClient.is_device_key("Fj-" + "AB".repeat(32)), "lower case hex only")
	assert_false(SupabaseClient.is_device_key(a.substr(0, 66)))
	var fn := FileAccess.get_file_as_string("res://supabase/functions/device-key/index.ts")
	assert_true("^Fj-[0-9a-f]{64}$" in fn, "the function checks the same shape")


func _clean() -> void:
	SafeFile.remove(SESSION)
	SafeFile.remove(DEVICE)


func _api() -> SupabaseClient:
	var api := SupabaseClient.new(null, "https://example.supabase.co", "k")
	api.session_path = SESSION
	api.device_path = DEVICE
	return api


func test_a_restored_device_key_can_sign_in() -> void:
	_clean()
	var api := _api()
	api.restore()
	assert_false(api.has_device_login(), "no key yet")
	var key := SupabaseClient.new_device_key()
	SafeFile.write_json(DEVICE, {"key": key, "email": "x@device.flapjaw.invalid"})
	api = _api()
	api.restore()
	assert_true(api.has_device_login())
	SafeFile.write_json(DEVICE, {"key": "Fj-short", "email": "x@device.flapjaw.invalid"})
	api = _api()
	api.restore()
	assert_false(api.has_device_login(), "a broken key is not used")
	_clean()


## Offline with a dead session and a device key: no new player is made (that
## would lose the old one's diamonds); the phone just stays offline.
func test_no_answer_never_makes_a_new_player() -> void:
	_clean()
	SafeFile.write_json(SESSION, {"access_token": "a", "refresh_token": "r", "expires_at": 1})
	SafeFile.write_json(
		DEVICE, {"key": SupabaseClient.new_device_key(), "email": "x@device.flapjaw.invalid"}
	)
	var api := _api()
	api.restore()
	assert_false(await api.ensure_session())
	assert_eq(SafeFile.read_json(SESSION).refresh_token, "r", "the old session is kept")
	assert_true(api.has_device_login(), "and so is the key")
	_clean()


func test_only_a_refusal_tries_the_next_way_in() -> void:
	assert_true(SupabaseClient.refused({"code": 400}))
	assert_true(SupabaseClient.refused({"code": 429}))
	assert_false(SupabaseClient.refused({"code": 0}), "no answer")
	assert_false(SupabaseClient.refused({"code": 503}), "server busy")
