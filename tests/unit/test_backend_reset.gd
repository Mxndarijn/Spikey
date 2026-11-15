extends TestCase
## The one-time fresh start when the game moves to a new server (BackendReset,
## BackendEvents), the notices on Home, and a phone whose player moved away.

const TEST_PATH := "user://test_backend_reset_profile.json"
const RUNS := "user://test_backend_reset_profile_runs.json"
const CONFIG := "user://test_backend_reset_config.json"
const OLD_FILE := "user://test_backend_reset_old_queue.json"
const SESSION := "user://test_backend_reset_session.json"
const DEVICE := "user://test_backend_reset_device.json"


## Our own server's client, offline: nothing ever answers.
class OfflineClient:
	extends FlapjawClient

	func _init() -> void:
		super(null, "https://api.example.com")

	func post(_path: String, _body: Dictionary, _signed_in: bool) -> Dictionary:
		return {"ok": false, "code": 0, "data": null}


func _played() -> Profile:
	var p := Profile.new()
	p.coins = 420
	p.diamonds = 12
	p.best_score = 87
	p.runs = 40
	p.onboarded = true
	p.grant(ItemKind.FLYER, "dash")
	p.equip(ItemKind.FLYER, "dash")
	p.record_room_cleared("saw_hall")
	p.leaderboard_name = "buzzybee"
	p.settings.music_volume = 20
	p.settings.haptics = false
	p.cloud_revision = 9
	return p


func _clean() -> void:
	for path in [TEST_PATH, RUNS, CONFIG, OLD_FILE, SESSION, DEVICE]:
		SafeFile.remove(path)


func test_only_a_new_server_id_resets() -> void:
	var p := _played()
	assert_false(BackendReset.needed(p, {}), "no backend config")
	assert_false(BackendReset.needed(p, {"kind": "supabase", "url": "https://a.co"}), "Supabase")
	assert_true(BackendReset.needed(p, {"kind": "flapjaw", "server_id": "s1"}))
	p.backend_server = "s1"
	assert_false(BackendReset.needed(p, {"kind": "flapjaw", "server_id": "s1"}), "once only")
	assert_true(BackendReset.needed(p, {"kind": "flapjaw", "server_id": "s2"}), "the next move")


func test_the_fresh_save_keeps_settings_and_name_only() -> void:
	var old := _played()
	var p := BackendReset.fresh_profile(old, "s1")
	assert_eq(p.coins, 0)
	assert_eq(p.diamonds, 0)
	assert_eq(p.best_score, 0)
	assert_eq(p.runs, 0)
	assert_false(p.onboarded, "the first start hands out the free flyer again")
	assert_false(p.owns(ItemKind.FLYER, "dash"))
	assert_eq(p.met_rooms, [] as Array[String])
	assert_eq(p.cloud_revision, 0, "never synced with the new server")
	assert_eq(p.leaderboard_name, "buzzybee")
	assert_eq(p.settings.music_volume, 20)
	assert_false(p.settings.haptics)
	assert_eq(p.backend_server, "s1")


func test_apply_clears_the_old_files_and_writes_the_save() -> void:
	_clean()
	SafeFile.write_json(OLD_FILE, [{"p_score": 3}])
	SafeFile.write_json(OLD_FILE, [{"p_score": 4}])  # leaves a .bak behind
	SafeFile.write_json(RUNS, {"runs": []})
	var p := _played()
	var files: Array[String] = [OLD_FILE]
	BackendReset.apply(p, "s1", TEST_PATH, RUNS, files, null)
	assert_false(SafeFile.exists(OLD_FILE), "the queue and its backup are gone")
	assert_false(SafeFile.exists(RUNS), "Your runs too")
	assert_eq(p.coins, 0, "cleared in place")
	assert_eq(Profile.load_or_new(TEST_PATH).backend_server, "s1", "and saved")
	_clean()


func test_the_server_id_survives_a_save_and_never_syncs() -> void:
	var p := Profile.new()
	p.backend_server = "s1"
	assert_eq(Profile.from_dict(p.to_dict()).backend_server, "s1")
	assert_false(p.cloud_dict().has("backend_server"), "it belongs to this phone")


func test_only_a_save_with_progress_says_why() -> void:
	assert_false(BackendReset.had_progress(Profile.new()), "a new install starts quietly")
	assert_true(BackendReset.had_progress(_played()))


func _make_main(client: FlapjawClient, config: String) -> Node:
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.board_config_path = config
	var p := Profile.load_or_new(TEST_PATH)
	main.leaderboard = OnlineLeaderboard.new(p, client) if client != null else null
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _offline() -> OfflineClient:
	var c := OfflineClient.new()
	c.session_path = SESSION
	c.device_path = DEVICE
	c.keychain = null
	return c


func _notice(main: Node) -> NoticePopup:
	return (main.get("_popups") as HomePopups).notice_card()


func test_the_first_launch_on_the_new_server_starts_fresh() -> void:
	_clean()
	_played().save(TEST_PATH)
	SafeFile.write_json(RUNS, {"runs": []})
	SafeFile.write_json(
		CONFIG, {"kind": "flapjaw", "url": "https://api.example.com", "server_id": "s1"}
	)
	var main := _make_main(_offline(), CONFIG)
	var saved := Profile.load_or_new(TEST_PATH)
	assert_eq(saved.coins, 0)
	assert_eq(saved.best_score, 0)
	assert_true(saved.onboarded, "the first start ran on the fresh save")
	assert_eq(saved.leaderboard_name, "buzzybee")
	assert_eq(saved.settings.music_volume, 20)
	assert_eq(saved.backend_server, "s1")
	assert_false(SafeFile.exists(RUNS), "Your runs start over")
	var card := _notice(main)
	assert_true(card != null, "Home says why")
	assert_eq(card.id, NoticePopup.FRESH_START)
	card.button().pressed.emit()
	assert_true(_notice(main) == null, "pressed away")
	main.queue_free()
	# The next launch: nothing happens again.
	var again := _make_main(_offline(), CONFIG)
	assert_true(_notice(again) == null)
	again.queue_free()
	_clean()


func test_without_a_new_server_nothing_is_reset() -> void:
	_clean()
	_played().save(TEST_PATH)
	var main := _make_main(null, "")
	assert_eq(Profile.load_or_new(TEST_PATH).coins, 420)
	assert_true(_notice(main) == null)
	main.queue_free()
	_clean()


func test_a_moved_player_starts_over_here() -> void:
	_clean()
	var p := _played()
	p.backend_server = "s1"
	p.save(TEST_PATH)
	var client := _offline()
	var main := _make_main(client, "")
	client.account_moved.emit()
	var saved := Profile.load_or_new(TEST_PATH)
	assert_eq(saved.coins, 0, "the progress went with the player")
	assert_true(saved.onboarded, "a new player here, with the free flyer")
	assert_eq(saved.backend_server, "s1", "still this server")
	assert_eq(saved.leaderboard_name, "buzzybee")
	assert_eq(_notice(main).id, NoticePopup.MOVED)
	main.queue_free()
	_clean()


func test_too_old_an_app_says_so_on_home() -> void:
	_clean()
	var client := _offline()
	var main := _make_main(client, "")
	client.update_required.emit()
	assert_eq(_notice(main).id, NoticePopup.UPDATE)
	_notice(main).button().pressed.emit()
	client.update_required.emit()
	assert_eq(_notice(main).id, NoticePopup.UPDATE, "a later answer may ask again")
	main.queue_free()
	_clean()


func test_notices_wait_for_home_and_show_one_at_a_time() -> void:
	_clean()
	var client := _offline()
	var main := _make_main(client, "")
	var popups: HomePopups = main.get("_popups")
	main.call("start_run")
	popups.notice(NoticePopup.UPDATE)
	popups.notice(NoticePopup.MOVED)
	assert_true(popups.notice_card() == null, "not over a run")
	main.call("show_home")
	assert_eq(popups.notice_card().id, NoticePopup.UPDATE)
	popups.notice_card().button().pressed.emit()
	assert_eq(popups.notice_card().id, NoticePopup.MOVED, "then the next")
	main.queue_free()
	_clean()
