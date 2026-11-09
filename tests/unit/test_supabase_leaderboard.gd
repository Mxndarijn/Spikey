extends TestCase
## The Supabase client without a network: its config file, how it reads boards
## from the server's answers, what it sends for a run, and that runs it can't
## send wait on the phone for later.

const CONFIG := "user://test_supabase_config.json"
const SESSION := "user://test_supabase_session.json"
const QUEUE := "user://test_supabase_queue.json"


func _profile() -> Profile:
	var p := Profile.new()
	p.leaderboard_name = "buzzybee"
	p.grant(Catalog.FLYER, "dash")
	p.equip(Catalog.FLYER, "dash")
	return p


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _client(p: Profile) -> SupabaseLeaderboard:
	# No host node: every request fails at once, like a phone without internet.
	var c := SupabaseLeaderboard.new(p, null, "https://example.supabase.co/", "public-key")
	c.session_path = SESSION
	c.queue_path = QUEUE
	return c


func _clean() -> void:
	for path in [CONFIG, SESSION, QUEUE]:
		DirAccess.remove_absolute(path)


func test_config_needs_an_https_url_and_a_key() -> void:
	_clean()
	assert_eq(SupabaseLeaderboard.load_config(CONFIG), {}, "no file: sample boards")
	_write(CONFIG, "not json")
	assert_eq(SupabaseLeaderboard.load_config(CONFIG), {}, "broken file")
	_write(CONFIG, '{"url": "http://insecure.example", "anon_key": "k"}')
	assert_eq(SupabaseLeaderboard.load_config(CONFIG), {}, "https only")
	_write(CONFIG, '{"url": "https://abc.supabase.co", "anon_key": ""}')
	assert_eq(SupabaseLeaderboard.load_config(CONFIG), {}, "a key is needed")
	_write(CONFIG, '{"url": "https://abc.supabase.co", "anon_key": "PASTE-THE-KEY-HERE"}')
	assert_eq(SupabaseLeaderboard.load_config(CONFIG), {}, "a placeholder key")
	_write(CONFIG, '{"url": "https://abc.supabase.co", "anon_key": "k"}')
	assert_eq(
		SupabaseLeaderboard.load_config(CONFIG), {"url": "https://abc.supabase.co", "anon_key": "k"}
	)
	_clean()


func test_reads_a_board_from_the_server_answer() -> void:
	var answer: Variant = (
		JSON
		. parse_string(
			(
				'{"entries": [{"rank": 1, "name": "Noor", "flyer": "pip", "score": 131, "is_me": false,'
				+ ' "verified": true},'
				+ ' {"rank": 2, "name": "buzzybee", "flyer": "dash", "score": 87, "is_me": true, "run": 5,'
				+ ' "verified": false}],'
				+ ' "me": {"rank": 2, "score": 87, "verified": false}, "players": 2, "resets_in_s": 3600}'
			)
		)
	)
	var b := SupabaseLeaderboard.parse_board(LeaderboardService.DAILY, answer)
	assert_eq(b.status, LeaderboardBoard.Status.OK)
	assert_eq(b.entries.size(), 2)
	assert_eq(b.entries[0].player_name, "Noor")
	assert_eq(b.entries[0].score, 131)
	assert_true(b.entries[1].is_me, "the player's own row is marked")
	assert_true(b.entries[0].verified, "the checker replayed this run")
	assert_false(b.entries[1].verified, "the player's own new run waits for the checker")
	assert_false(b.me.verified)
	assert_eq(b.me.rank, 2)
	assert_eq(b.entries[1].run_id, 5, "each row knows its run for the replay")
	assert_eq(b.me.score, 87)
	assert_eq(b.players, 2)
	assert_eq(b.resets_in_s, 3600)
	var nobody: Variant = JSON.parse_string(
		'{"entries": [], "me": null, "players": 0, "resets_in_s": -1}'
	)
	var empty := SupabaseLeaderboard.parse_board(LeaderboardService.ALL_TIME, nobody)
	assert_true(empty.is_empty(), "an empty board")
	assert_true(empty.me == null, "no run yet")
	var broken := SupabaseLeaderboard.parse_board(LeaderboardService.DAILY, "oops")
	assert_eq(broken.status, LeaderboardBoard.Status.OFFLINE, "a strange answer reads as offline")


func test_a_run_is_sent_with_its_seed_taps_name_and_flyer() -> void:
	var body := (
		SupabaseLeaderboard
		. run_body(
			_profile(),
			42,
			{
				"gameplay_version": 5,
				"seed": 123456,
				"season": Seasons.WINTER,
				"taps": [3, 40, 77],
				"coins": 4,
				"end_tick": 300,
			},
			0
		)
	)
	assert_eq(body.p_name, "buzzybee")
	assert_eq(body.p_flyer, "dash")
	assert_eq(body.p_score, 42)
	assert_eq(body.p_gameplay_version, 5)
	assert_eq(body.p_seed, 123456)
	assert_eq(body.p_taps, [3, 40, 77])
	assert_eq(body.p_played_at, "1970-01-01T00:00:00Z")
	assert_eq(body.p_loadout.get("flyer"), "dash", "the look goes along for replays")
	assert_eq(body.p_season, Seasons.WINTER, "the checker replays the same seasonal rooms")
	assert_eq(body.p_coins, 4, "coins are checked too")
	assert_eq(body.p_end_tick, 300)


func test_older_databases_get_the_arguments_they_know() -> void:
	var body := SupabaseLeaderboard.run_body(_profile(), 42, {"seed": 1, "taps": []}, 0)
	var no_check := SupabaseLeaderboard.older_body(body)
	assert_false(no_check.has("p_season") or no_check.has("p_coins"), "before verified runs")
	assert_true(no_check.has("p_loadout"), "drops only the newest arguments first")
	var oldest := SupabaseLeaderboard.older_body(no_check)
	assert_false(oldest.has("p_loadout"), "before loadouts")
	assert_true(oldest.has("p_taps"))
	assert_eq(SupabaseLeaderboard.older_body(oldest), {}, "nothing left to drop")
	assert_true(body.has("p_season"), "the original body is left alone")


func test_loadout_has_every_equipped_cosmetic() -> void:
	var p := _profile()
	for kind in Catalog.KINDS:
		var id: String = Catalog.ids(kind)[0] if not Catalog.ids(kind).is_empty() else ""
		if not id.is_empty():
			p.grant(kind, id)
			p.equip(kind, id)
	var look := LeaderboardService.loadout_of(p)
	for kind in Catalog.KINDS:
		if not p.equipped_id(kind).is_empty():
			assert_eq(look.get(kind), p.equipped_id(kind), "%s is in the loadout" % kind)


func test_reads_a_run_for_its_replay() -> void:
	var answer: Variant = JSON.parse_string(
		(
			'{"run": 12, "name": "Noor", "score": 31, "gameplay_version": 9, "seed": 77,'
			+ ' "taps": [4, 18, 40], "loadout": {"flyer": "pip", "world": "ice"}}'
		)
	)
	var run := SupabaseLeaderboard.parse_run(answer)
	assert_eq(run.run, 12)
	assert_eq(run.seed, 77)
	assert_eq(run.gameplay_version, 9)
	assert_eq(run.taps, [4, 18, 40])
	assert_eq(run.loadout.get("world"), "ice")
	assert_false(run.has("season"), "an old run without a season replays in today's")
	answer.season = float(Seasons.HALLOWEEN)
	answer.erase("loadout")
	assert_eq(SupabaseLeaderboard.parse_run(answer).season, Seasons.HALLOWEEN, "its own season")
	assert_eq(SupabaseLeaderboard.parse_run(null), {}, "no run")


## Offline: runs stay on the phone, survive a restart, and the board says offline.
func test_runs_wait_while_offline_and_survive_a_restart() -> void:
	_clean()
	var p := _profile()
	var c := _client(p)
	c.submit_run(42, {"seed": 1, "taps": []})
	c.submit_run(55, {"seed": 2, "taps": [10]})
	assert_eq(c.pending_runs(), 2, "both runs wait")
	var again := _client(p)
	again.restore()
	assert_eq(again.pending_runs(), 2, "still there after a restart")
	var got: Array[LeaderboardBoard] = []
	again.board_loaded.connect(func(b: LeaderboardBoard) -> void: got.append(b))
	again.request_board(LeaderboardService.DAILY)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(got.size(), 1, "a board still arrives")
	if got.size() == 1:
		assert_eq(got[0].status, LeaderboardBoard.Status.OFFLINE)
	assert_eq(again.pending_runs(), 2, "nothing was lost")
	_clean()


func test_a_saved_session_is_restored() -> void:
	_clean()
	_write(SESSION, '{"access_token": "a", "refresh_token": "r", "expires_at": 4102444800}')
	var c := _client(_profile())
	c.restore()
	assert_true(await c._ensure_session(), "an unexpired token is used without asking the server")
	_clean()
