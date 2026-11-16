extends TestCase
## Move to a new phone (PhoneMove, PhoneMovePage in Settings) against a
## scripted server: the old phone's code, the new phone's preview and move,
## the save, wallet and Your runs that come along, and what a refusal says.

const TEST_PATH := "user://test_phone_move_profile.json"
const SESSION := "user://test_phone_move_session.json"
const DEVICE := "user://test_phone_move_device.json"
## A golden replay of the sim's current gameplay version.
const GOLDEN := "res://tests/replay/golden/g%d_seed_2024.json"


## Our own server as a script: each path answers from `answers`.
class ScriptedServer:
	extends FlapjawClient
	var answers := {}
	var sent: Array = []

	func _init() -> void:
		super(null, "https://api.example.com")

	func post(path: String, body: Dictionary, signed_in: bool) -> Dictionary:
		sent.append([path, body, signed_in])
		if answers.has(path):
			var a: Variant = answers[path]
			if a is Callable:
				return (a as Callable).call(body)
			return (a as Dictionary).duplicate(true)
		return {"ok": true, "code": 200, "data": {}}

	func paths() -> Array:
		return sent.map(func(s: Array) -> String: return s[0])


static func _ok(data: Variant) -> Dictionary:
	return {"ok": true, "code": 200, "data": data}


static func _session(player: String) -> Dictionary:
	return _ok(
		{
			"player_id": player,
			"access_token": "acc-" + player,
			"refresh_token": "ref-" + player,
			"expires_in": 3600,
		}
	)


func _server() -> ScriptedServer:
	var s := ScriptedServer.new()
	s.session_path = SESSION
	s.device_path = DEVICE
	s.keychain = null
	s.answers = {
		"/v1/auth/anon": _session("new-phone"),
		"/v1/get_wallet": _ok({"diamonds": 0, "prizes": []}),
		"/v1/sync_profile": _ok({"status": "saved", "revision": 1, "paid": []}),
		"/v1/get_board": _ok({"entries": [], "players": 0}),
		"/v1/get_daily_run": _ok({}),
	}
	return s


func _clean() -> void:
	for path in [TEST_PATH, SESSION, DEVICE, TEST_PATH.get_basename() + "_runs.json"]:
		SafeFile.remove(path)


func _make_main(server: ScriptedServer, profile: Profile) -> Node:
	_clean()
	profile.save(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.board_config_path = ""
	main.leaderboard = OnlineLeaderboard.new(profile, server)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _home(main: Node) -> HomeScreen:
	return (main.get("_menus") as MenuLayer).current() as HomeScreen


func _golden_row() -> Dictionary:
	var g: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(GOLDEN % SimConfig.GAMEPLAY_VERSION)
	)
	return {
		"run": 41,
		"score": g.score,
		"gameplay_version": g.gameplay_version,
		"seed": g.seed,
		"season": g.season,
		"taps": g.taps,
		"revives": [],
		"coins": g.coins,
		"end_tick": g.end_tick,
		"loadout": {"flyer": "dash", "world": "sunset"},
		"board": "endless",
		"played_at": 1794700000,
	}


func _player() -> Profile:
	var p := Profile.new()
	p.onboarded = true
	p.coins = 140
	p.best_score = 12
	p.leaderboard_name = "newbee"
	p.settings.music_volume = 33
	return p


func test_a_server_run_becomes_a_watchable_your_run() -> void:
	var r := PhoneMove.record_of(_golden_row())
	assert_eq(r.score(), int(_golden_row().score))
	assert_true(r.watchable(), "the same gameplay version replays")
	assert_eq(r.played_at, 1794700000)
	assert_eq(r.world, "sunset")
	assert_eq(r.rooms, 1 + floori(r.score() / 10.0))
	assert_false(r.revived())
	var verdict := r.run.replay.verify()
	assert_true(verdict.ok, str(verdict.reason))


func test_refusals_say_what_to_do() -> void:
	assert_eq(PhoneMove.problem({"code": 0}), PhoneMove.PROBLEMS.offline)
	assert_eq(
		PhoneMove.problem({"code": 404, "data": {"error": "unknown_code"}}),
		PhoneMove.PROBLEMS.unknown_code
	)
	assert_eq(
		PhoneMove.problem({"code": 429, "data": {"error": "rate_limited"}}),
		PhoneMove.PROBLEMS.rate_limited
	)
	assert_eq(PhoneMove.grouped("K7QF3MZDPX9W"), "K7QF-3MZD-PX9W")


func test_no_account_row_without_our_own_server() -> void:
	var sheet := SettingsSheet.new(Profile.new(), AppServices.offline(Profile.new()))
	assert_true(sheet.find_child("MovePhone", true, false) == null)
	sheet.free()


func test_the_old_phone_gets_a_code() -> void:
	var server := _server()
	var expires := int(Time.get_unix_time_from_system()) + 86400
	server.answers["/v1/transfer/create"] = _ok({"code": "K7QF3MZDPX9W", "expires_at": expires})
	var main := _make_main(server, _player())
	var sheet := _home(main).open_settings()
	assert_true(sheet.find_child("MovePhone", true, false) != null, "the Account row")
	sheet.show_move(true)
	var page := sheet.move_page()
	assert_eq(page.step, PhoneMovePage.Step.CHOOSE)
	(page.find_child("GetCode", true, false) as Button).pressed.emit()
	await _settle(page, PhoneMovePage.Step.CODE)
	assert_eq(page.code_text(), "K7QF-3MZD-PX9W")
	var paths := server.paths()
	assert_true(paths.has("/v1/sync_profile"), "the save went first")
	assert_true(paths.find("/v1/sync_profile") < paths.find("/v1/transfer/create"))
	(page.find_child("CancelCode", true, false) as Button).pressed.emit()
	await _settle(page, PhoneMovePage.Step.CHOOSE)
	assert_true(server.paths().has("/v1/transfer/cancel"))
	main.queue_free()
	_clean()


func test_a_refused_code_says_why() -> void:
	var server := _server()
	server.answers["/v1/transfer/preview"] = {
		"ok": false, "code": 404, "data": {"error": "unknown_code"}
	}
	var main := _make_main(server, _player())
	var sheet := _home(main).open_settings()
	sheet.show_move(true)
	var page := sheet.move_page()
	page.open_enter()
	page.field().text = "AAAA-BBBB-CCCC"
	page.field().text_changed.emit(page.field().text)
	(page.find_child("Continue", true, false) as Button).pressed.emit()
	await _wait(func() -> bool: return page.problem_text() != "")
	assert_eq(page.problem_text(), PhoneMove.PROBLEMS.unknown_code)
	assert_eq(page.step, PhoneMovePage.Step.ENTER)
	main.queue_free()
	_clean()


func test_the_new_phone_takes_the_progress() -> void:
	var server := _server()
	server.answers["/v1/transfer/preview"] = _ok(
		{
			"name": "movingbee",
			"best": 87,
			"gold": 2310,
			"diamonds": 45,
			"items": 18,
			"this_phone": {"best": 12, "gold": 140, "diamonds": 0, "items": 3},
		}
	)
	server.answers["/v1/transfer/redeem"] = _session("old-player")
	var cloud := {
		"coins": 2310,
		"best_score": 87,
		"onboarded": true,
		"leaderboard_name": "movingbee",
		"owned": {"flyer": ["buzz", "dash"]},
		"equipped": {"flyer": "dash"},
		"music_volume": 55,
	}
	server.answers["/v1/sync_profile"] = func(b: Dictionary) -> Dictionary:
		if int(b.p_base) == 7:
			return _ok({"status": "saved", "revision": 8, "paid": []})
		return _ok({"status": "conflict", "revision": 7, "data": cloud, "paid": []})
	server.answers["/v1/get_my_runs"] = _ok({"runs": [_golden_row()]})
	var main := _make_main(server, _player())
	var sheet := _home(main).open_settings()
	sheet.show_move(true)
	var page := sheet.move_page()
	page.open_enter()
	page.field().text = "k7qf-3mzd-px9w"
	page.field().text_changed.emit(page.field().text)
	(page.find_child("Continue", true, false) as Button).pressed.emit()
	await _settle(page, PhoneMovePage.Step.CONFIRM)
	assert_true("Best 87" in page.summary(false), page.summary(false))
	assert_true("2,310 gold" in page.summary(false))
	assert_true("movingbee" in page.summary(false))
	assert_true("Best 12" in page.summary(true))
	(page.find_child("MoveHere", true, false) as Button).pressed.emit()
	await _wait(
		func() -> bool: return not is_instance_valid(sheet) or sheet.is_queued_for_deletion()
	)
	var is_redeem := func(s: Array) -> bool: return s[0] == "/v1/transfer/redeem"
	var redeem: Array = server.sent.filter(is_redeem)[0]
	assert_eq(redeem[1].code, "k7qf-3mzd-px9w", "the server reads the code as typed")
	assert_eq(server.player_id(), "old-player", "this phone is that player now")
	var saved := Profile.load_or_new(TEST_PATH)
	assert_eq(saved.coins, 2310, "the server's save, not this phone's 140")
	assert_eq(saved.best_score, 87)
	assert_true(saved.owns(ItemKind.FLYER, "dash"))
	assert_eq(saved.settings.music_volume, 55, "the moved player's settings come along")
	var runs: RunStore = main.get("_runs")
	assert_eq(runs.history.latest().size(), 1, "Your runs came along")
	assert_true(_home(main) != null, "back on Home")
	main.queue_free()
	_clean()


## Waits a few frames for the page's awaited requests to finish.
func _settle(page: PhoneMovePage, step: PhoneMovePage.Step) -> void:
	await _wait(func() -> bool: return page.step == step)
	assert_eq(page.step, step)


func _wait(done: Callable) -> void:
	for i in 60:
		if done.call():
			return
		await (Engine.get_main_loop() as SceneTree).process_frame
