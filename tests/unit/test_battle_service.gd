extends TestCase
## Battle's client side: the rules' numbers, how a battle from the server is
## read, what the service sends and what it says when the server says no.


## The server as canned answers per operation; remembers what was sent.
class FakeServer:
	extends FlapjawClient
	var answers := {}
	var sent: Array[Array] = []

	func _init() -> void:
		super(null, "https://api.example.com")

	func call_db(function: String, body: Dictionary) -> Dictionary:
		sent.append([function, JSON.parse_string(JSON.stringify(body))])
		return answers.get(function, {"ok": false, "code": 0, "data": null})


func _view_data() -> Dictionary:
	return {
		"battle": 12,
		"status": "open",
		"first_to": 6,
		"random": false,
		"starter": true,
		"wins_me": 2,
		"wins_them": 2,
		"turn": "me",
		"opponent": {"name": "Mira", "flyer": "dash", "bot": false},
		"last_move_s": 7200,
		"ended_by": null,
		"winner": null,
		"can_close": false,
		"can_nudge": false,
		"rounds":
		[
			{"number": 1, "blind": false, "my_score": 19, "their_score": 14, "winner": "me"},
		],
		"play":
		{
			"round": 5,
			"role": "answer",
			"blind": false,
			"rival": {"score": 27, "coins": 2, "taps": [4, 30], "seed": 99, "season": -1},
		},
	}


func test_the_rules_match_the_server() -> void:
	assert_eq(MatchRules.FIRST_TO, 6)
	assert_eq(MatchRules.MAX_OPEN, 20)
	assert_eq(MatchRules.round_outcome(10, 0, 9, 5), MatchRules.Outcome.WIN, "score first")
	assert_eq(MatchRules.round_outcome(10, 1, 10, 3), MatchRules.Outcome.LOSS, "then coins")
	assert_eq(MatchRules.round_outcome(10, 3, 10, 3), MatchRules.Outcome.DRAW)
	assert_true(MatchRules.starter_opens(1) and not MatchRules.starter_opens(2))
	assert_true(MatchRules.is_blind(5, 5), "round 11 at 5-5 is blind")
	assert_false(MatchRules.is_blind(5, 4))
	assert_true(MatchRules.is_decided(6, 4))
	assert_eq(MatchRules.since_text(30), "just now")
	assert_eq(MatchRules.since_text(7200), "2 h ago")
	assert_eq(MatchRules.since_text(86400 * 3), "3 days ago")


func test_a_battle_is_read_from_the_server() -> void:
	var v := BattleView.parse(_view_data())
	assert_eq(v.id, 12)
	assert_true(v.my_turn())
	assert_eq(v.rival_name, "Mira")
	assert_eq(v.play_round, 5)
	assert_eq(v.rival_score(), 27, "the rival's checked run is the ghost")
	assert_eq(v.status_line(), "Round 5 · Mira scored 27")
	assert_eq(v.rounds.size(), 1)
	var blind := _view_data()
	blind.play = {"round": 11, "role": "answer", "blind": true}
	assert_eq(BattleView.parse(blind).status_line(), "Round 11 · Mira has played")
	var theirs := _view_data()
	theirs.turn = "them"
	theirs.play = null
	assert_eq(BattleView.parse(theirs).status_line(), "Waiting for Mira · 2 h ago")
	var over := _view_data()
	over.status = "finished"
	over.winner = "them"
	over.ended_by = "resigned"
	over.wins_them = 6
	assert_eq(BattleView.parse(over).status_line(), "Mira won 6-2 (resigned)")
	assert_eq(BattleView.parse(null).id, 0, "nothing usable reads as empty")
	var waiting := BattleView.parse({"battle": 3, "status": "waiting", "opponent": null})
	assert_eq(waiting.rival_label(), "Waiting for a rival")


func test_the_service_sends_the_operations_arguments() -> void:
	var p := Profile.new()
	p.leaderboard_name = "Ada"
	var server := FakeServer.new()
	var data := _view_data()
	data.code = "KD7WQ3"
	server.answers["battle_create"] = {"ok": true, "code": 200, "data": data}
	var service := BattleService.new(p, server)
	var got: Array[BattleView] = []
	service.battle_loaded.connect(func(v: BattleView) -> void: got.append(v))
	await service.create("invite")
	assert_eq(server.sent[0][0], "battle_create")
	assert_eq(server.sent[0][1].p_opponent, "invite")
	assert_eq(int(server.sent[0][1].p_gameplay_version), SimConfig.GAMEPLAY_VERSION)
	assert_eq(server.sent[0][1].p_name, "Ada")
	assert_eq(got[0].code, "KD7WQ3")
	var replay := {"seed": 99, "season": -1, "taps": [3, 8], "coins": 1, "end_tick": 400}
	var body := BattleService.submit_body(p, 12, 5, 31, replay)
	assert_eq(body.p_battle, 12)
	assert_eq(body.p_round, 5)
	assert_eq(body.p_score, 31)
	assert_eq(body.p_seed, 99)
	assert_eq(body.p_taps, [3, 8])
	assert_eq(body.p_end_tick, 400)


func test_a_lost_run_comes_back_as_the_battle() -> void:
	var server := FakeServer.new()
	var lost := _view_data()
	lost.lost = true
	server.answers["battle_start_run"] = {"ok": true, "code": 200, "data": lost}
	var service := BattleService.new(Profile.new(), server)
	var views: Array[BattleView] = []
	var starts: Array[Dictionary] = []
	service.battle_loaded.connect(func(v: BattleView) -> void: views.append(v))
	service.run_started.connect(func(d: Dictionary) -> void: starts.append(d))
	await service.start_run(12, 5)
	assert_eq(starts.size(), 0)
	assert_true(views.size() == 1 and views[0].lost, "the run before was lost: it counts as 0")
	server.answers["battle_start_run"] = {
		"ok": true, "code": 200, "data": {"battle": 12, "round": 5, "seed": 77, "season": -1}
	}
	await service.start_run(12, 5)
	assert_eq(int(starts[0].seed), 77)


func test_what_the_player_is_told_when_it_fails() -> void:
	var offline := BattleService.new(Profile.new(), null)
	var told: Array[String] = []
	offline.failed.connect(func(_op: String, m: String) -> void: told.append(m))
	await offline.request_list()
	assert_eq(told, [BattleService.OFFLINE], "no server: offline")
	var refused := {"ok": false, "code": 400, "data": {"message": "too many battles"}}
	assert_eq(BattleService.message_for("battle_create", refused), BattleService.TOO_MANY)
	var code := {"ok": false, "code": 400, "data": {"message": "unknown code"}}
	assert_eq(BattleService.message_for("battle_join", code), BattleService.BAD_CODE)
	assert_eq(BattleService.message_for("battle_get", {"code": 0}), BattleService.OFFLINE)


func test_an_older_app_hears_update_required() -> void:
	var server := FakeServer.new()
	var refused := {"ok": false, "code": 409, "data": {"error": "update_required", "message": "x"}}
	server.answers["battle_list"] = refused
	var service := BattleService.new(Profile.new(), server)
	var versions: Array[int] = []
	var told: Array[String] = []
	service.version_known.connect(func(v: int) -> void: versions.append(v))
	service.failed.connect(func(_op: String, m: String) -> void: told.append(m))
	await service.request_list()
	assert_eq(versions, [SimConfig.GAMEPLAY_VERSION + 1], "the server's game is newer")
	assert_eq(told, [BattleService.UPDATE])
	assert_true(BattleService.is_update_required(refused))
