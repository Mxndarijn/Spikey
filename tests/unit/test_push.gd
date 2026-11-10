extends TestCase
## Board alerts: the setting, when the game asks for notification permission,
## and what it tells the server. Sending is the server's job
## (supabase/tests/20_test_push.sql).

const TEST_PATH := "user://test_push_profile.json"
const MIGRATION := "res://supabase/migrations/20261110110000_push_alerts.sql"


## A phone with push: records what the game asks of it.
class FakePush:
	extends PushService
	var asked := 0
	var started := 0
	var enabled_calls: Array = []

	func is_available() -> bool:
		return true

	func request_permission() -> void:
		asked += 1

	func start() -> void:
		started += 1

	func set_enabled(on: bool) -> void:
		enabled_calls.append(on)


func _make_main(push: PushService = null, profile: Profile = null) -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	if profile != null:
		profile.save(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	if push != null:
		main.push = push
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _board(my_rank: int) -> LeaderboardBoard:
	var b := LeaderboardBoard.make(LeaderboardService.DAILY)
	for i in 12:
		var e := LeaderboardBoard.Entry.new(i + 1, "P%d" % i, "buzz", 100 - i)
		e.is_me = i + 1 == my_rank
		if e.is_me:
			b.me = e
		b.entries.append(e)
	b.players = 12
	b.resets_in_s = 3600
	return b


func test_no_push_without_a_plugin() -> void:
	var push := PushService.new()
	assert_false(push.is_available())
	var got: Array = []
	push.token_received.connect(func(t: String, p: String) -> void: got.append([t, p]))
	push.accept_token("", PushService.ANDROID)
	assert_eq(got, [], "an empty token is no token")
	push.accept_token("abc-token-123", PushService.ANDROID)
	assert_eq(got, [["abc-token-123", "android"]])
	assert_eq(push.token(), "abc-token-123")


func test_registration_carries_token_platform_and_clock() -> void:
	assert_eq(
		PushService.register_body("tok-12345", PushService.IOS, 120),
		{"p_token": "tok-12345", "p_platform": "ios", "p_utc_offset_min": 120}
	)
	assert_eq(PushService.register_body("t", "android", 99999).p_utc_offset_min, 840, "clamped")
	assert_between(PushService.utc_offset_minutes(), -720, 840, "this PC's clock")


func test_migration_matches_the_game() -> void:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	for fn in ["register_push(text, text, integer)", "set_push_enabled(boolean)"]:
		assert_true(
			sql.contains("grant execute on function public.%s to authenticated" % fn),
			"the game may call %s" % fn
		)
	for key: String in PushService.register_body("t", "android", 0):
		assert_true(sql.contains(key), "register_push takes %s" % key)
	assert_true(sql.contains("p_enabled boolean"), "set_push_enabled takes p_enabled")
	for platform: String in [PushService.ANDROID, PushService.IOS]:
		assert_true(sql.contains("'%s'" % platform), "the database knows %s" % platform)
	for fn in [
		"worker_pending_alerts(integer)", "worker_mark_alerts(jsonb)", "spikey_check_spots(date)"
	]:
		assert_true(
			sql.contains("revoke all on function public.%s from public, anon, authenticated" % fn),
			"%s is not callable by the game" % fn
		)
	for table in ["push_devices", "spot_state", "spot_alerts"]:
		assert_true(
			sql.contains("alter table public.%s enable row level security" % table),
			"%s is locked" % table
		)
	assert_true(sql.contains("exception when others then"), "alerts never block the checker")


func test_board_alerts_is_a_saved_setting() -> void:
	var p := Profile.new()
	assert_true(p.board_alerts, "on by default")
	assert_false(p.push_asked)
	var sheet := SettingsSheet.new(p)
	(Engine.get_main_loop() as SceneTree).root.add_child(sheet)
	sheet.set_switch("board_alerts", false)
	assert_false(p.board_alerts, "the switch writes the profile")
	sheet.free()
	p.push_asked = true
	var back := Profile.from_dict(p.to_dict())
	assert_false(back.board_alerts)
	assert_true(back.push_asked)
	assert_true(Profile.from_dict({"version": 3}).board_alerts, "older saves have alerts on")


func test_permission_is_asked_once_at_the_first_prize_spot() -> void:
	var push := FakePush.new()
	var main := _make_main(push)
	assert_eq(push.started, 0, "never asked: nothing to fetch yet")
	main._on_board_loaded(_board(11))
	assert_eq(push.asked, 0, "11th wins nothing: not the moment")
	main._on_board_loaded(_board(7))
	assert_eq(push.asked, 1, "a top-10 place: ask now")
	assert_true(Profile.load_or_new(TEST_PATH).push_asked, "remembered")
	main._on_board_loaded(_board(3))
	main._on_board_loaded(_board(7))
	assert_eq(push.asked, 1, "only once")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_a_later_start_fetches_the_token_again() -> void:
	var p := Profile.new()
	p.push_asked = true
	var push := FakePush.new()
	var main := _make_main(push, p)
	assert_eq(push.started, 1, "permission was given before")
	assert_eq(push.asked, 0, "no second prompt")
	main.free()
	var off := Profile.new()
	off.push_asked = true
	off.board_alerts = false
	var quiet := FakePush.new()
	var main2 := _make_main(quiet, off)
	assert_eq(quiet.started, 0, "alerts off: no token")
	main2.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_the_switch_tells_the_server_and_asks_late() -> void:
	var p := Profile.new()
	p.board_alerts = false
	var push := FakePush.new()
	var main := _make_main(push, p)
	main._on_board_loaded(_board(2))
	assert_eq(push.asked, 0, "alerts off: never ask")
	main._profile.board_alerts = true
	main._on_settings_changed()
	assert_eq(push.enabled_calls, [true], "the server hears the switch")
	assert_eq(push.asked, 1, "switched on while holding a prize spot: ask now")
	main._on_settings_changed()
	assert_eq(push.enabled_calls, [true], "other settings don't repeat it")
	main._profile.board_alerts = false
	main._on_settings_changed()
	assert_eq(push.enabled_calls, [true, false])
	main.free()
	DirAccess.remove_absolute(TEST_PATH)
