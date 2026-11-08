extends TestCase
## Watching a leaderboard run: the driver taps on the recorded ticks, the run
## ends on the recorded score, the recorded look shows only for the replay, and
## nothing in the save or on the leaderboards changes.

const TEST_PATH := "user://test_replay_playback_profile.json"


## Counts submitted runs, so a replay can prove it sent none.
class SpyBoard:
	extends SampleLeaderboard
	var submitted := 0

	func _init() -> void:
		super(Profile.new())

	func submit_run(_score: int, _replay: Dictionary = {}) -> void:
		submitted += 1


func _make_main(board: LeaderboardService) -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.leaderboard = board
	# Bot runs are recorded without a season.
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


## A run as SupabaseLeaderboard.parse_run() gives it, from a bot recording.
static func _run_of(replay: Replay, look: Dictionary = {}) -> Dictionary:
	return {
		"run": 7,
		"name": "Noor",
		"score": replay.score,
		"gameplay_version": replay.gameplay_version,
		"seed": replay.seed_value,
		"taps": Array(replay.taps),
		"loadout": look,
	}


## An id of `kind` that isn't `not_this` (a real item, not a music pick).
static func _other_id(kind: String, not_this: String) -> String:
	for id in Catalog.ids(kind):
		if id == not_this:
			continue
		if kind == Catalog.MUSIC and Catalog.track(id) == null:
			continue
		return id
	return not_this


static func _play_out(run: RunController) -> void:
	while run.sim != null and not run.sim.is_over() and run.sim.state.tick < SimConfig.MAX_TICKS:
		run.advance()


func test_driver_reaches_recorded_score() -> void:
	var recorded := SimBots.play(5150, SimBots.gap_seeker, 3)
	assert_true(recorded.score > 0, "the bot scored")
	# Through JSON, as the run comes from the server: tap ticks arrive as floats.
	var run: Dictionary = JSON.parse_string(JSON.stringify(_run_of(recorded)))
	var rc := RunController.new()
	rc.new_replay(ReplayDriver.from_run(run))
	_play_out(rc)
	assert_true(rc.sim.is_over(), "the replay ends")
	assert_eq(rc.sim.state.score, recorded.score, "same score")
	assert_eq(rc.sim.state.tick, recorded.end_tick, "same end tick")
	assert_eq(rc.sim.checksum(), recorded.checksum, "same final state")
	rc.free()


func test_driver_ignores_input_taps() -> void:
	var recorded := SimBots.play(5151, SimBots.gap_seeker, 4, 300)
	var rc := RunController.new()
	rc.new_replay(ReplayDriver.from_run(_run_of(recorded)))
	while not rc.sim.is_over() and rc.sim.state.tick < SimConfig.MAX_TICKS:
		rc.request_tap()
		rc.advance()
	assert_eq(rc.sim.state.score, recorded.score, "player taps change nothing")
	assert_eq(rc.sim.checksum(), recorded.checksum)
	# A normal run afterwards takes input again.
	rc.new_run(1)
	rc.request_tap()
	assert_true(rc._tap_pending, "new_run drops the driver")
	rc.free()


func test_problems() -> void:
	assert_eq(ReplayDriver.problem({}), ReplayDriver.EMPTY_MESSAGE)
	var run := _run_of(SimBots.play(5152, SimBots.gap_seeker, 5, 120))
	assert_eq(ReplayDriver.problem(run), "")
	run.gameplay_version = SimConfig.GAMEPLAY_VERSION - 1
	assert_eq(ReplayDriver.problem(run), ReplayDriver.OLD_VERSION_MESSAGE)


func test_replay_plays_with_their_look_and_changes_nothing() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	var p: Profile = main._profile
	var own := {}
	for kind in Catalog.KINDS:
		own[kind] = p.equipped_id(kind)
	# What the player sees now, for kinds the save leaves empty.
	var shown := own.duplicate()
	shown[Catalog.TRAIL] = main._trail_style.id
	shown[Catalog.PORTAL] = main._room.portal_style.id
	var look := {}
	for kind in Catalog.KINDS:
		look[kind] = _other_id(kind, shown[kind])
		assert_ne(look[kind], shown[kind], "a different %s to show" % kind)
	var before := JSON.stringify(p.to_dict())
	var saved_before := FileAccess.get_file_as_string(TEST_PATH)
	var recorded := SimBots.play(5153, SimBots.gap_seeker, 6, 600)
	main.show_leaderboard(LeaderboardService.ALL_TIME)
	main._replay_board = LeaderboardService.ALL_TIME
	main.play_replay(_run_of(recorded, look))
	assert_eq(main.mode, main.Mode.REPLAY)
	assert_true(main._menus.current() == null, "the room shows, no menu")
	assert_eq(main._hud.replay_hud().chip_text(), "Replay: Noor, %d" % recorded.score)
	assert_eq(main._bird._character.id, look[Catalog.FLYER], "their flyer")
	assert_eq(main._theme.id, look[Catalog.WORLD], "their world")
	assert_eq(main._trail_style.id, look[Catalog.TRAIL], "their trail")
	assert_eq(main._room.portal_style.id, look[Catalog.PORTAL], "their portal")
	assert_eq(main._audio.track.id, look[Catalog.MUSIC], "their music")
	# Touching the screen does nothing.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)
	assert_false(main._run._tap_pending, "taps come from the replay only")
	_play_out(main._run)
	assert_eq(main._run.sim.state.score, recorded.score, "ends on the recorded score")
	var hud: ReplayHud = main._hud.replay_hud()
	assert_true(hud.can_watch_again(), "Watch again and Back")
	assert_eq(hud.title_text(), "Noor scored %d" % recorded.score)
	assert_eq(board.submitted, 0, "nothing sent to the leaderboards")
	assert_eq(JSON.stringify(p.to_dict()), before, "the profile is unchanged")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), saved_before, "the save is unchanged")
	for kind in Catalog.KINDS:
		assert_eq(p.equipped_id(kind), own[kind], "nothing equipped: %s" % kind)
	# Watch again: the same run from the top.
	main._replay_again()
	assert_eq(main._run.sim.state.tick, 0)
	assert_false(hud.is_over_showing())
	_play_out(main._run)
	assert_eq(main._run.sim.state.score, recorded.score, "the same run again")
	# Back: the leaderboards, and the player's own look returns.
	main._leave_replay()
	assert_eq(main.mode, main.Mode.MENU)
	var screen := main._menus.current() as LeaderboardScreen
	assert_true(screen != null, "back on the leaderboards")
	assert_eq(screen.board_id(), LeaderboardService.ALL_TIME, "on the same board")
	assert_eq(main._bird._character.id, own[Catalog.FLYER], "own flyer back")
	assert_eq(main._theme.id, own[Catalog.WORLD], "own world back")
	assert_eq(main._room.portal_style.id, PortalStyle.equipped(p).id, "own portal back")
	assert_false(main._hud.replay_hud().visible, "the replay HUD is gone")
	assert_eq(JSON.stringify(p.to_dict()), before, "still unchanged")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_unknown_look_falls_back_to_own() -> void:
	var main := _make_main(SpyBoard.new())
	var p: Profile = main._profile
	var look := {Catalog.FLYER: "no_such_flyer", Catalog.WORLD: "", Catalog.PORTAL: "gone"}
	main.play_replay(_run_of(SimBots.play(5154, SimBots.gap_seeker, 7, 120), look))
	assert_eq(main._bird._character.id, p.equipped_id(Catalog.FLYER), "own flyer")
	assert_eq(main._theme.id, p.equipped_id(Catalog.WORLD), "own world")
	assert_eq(main._room.portal_style.id, PortalStyle.equipped(p).id, "own portal")
	main.free()
	DirAccess.remove_absolute(TEST_PATH)


func test_old_version_and_empty_run_show_messages() -> void:
	var board := SpyBoard.new()
	var main := _make_main(board)
	var run := _run_of(SimBots.play(5155, SimBots.gap_seeker, 8, 120))
	run.gameplay_version = SimConfig.GAMEPLAY_VERSION - 1
	main.play_replay(run)
	var hud: ReplayHud = main._hud.replay_hud()
	assert_true(hud.is_over_showing())
	assert_false(hud.can_watch_again(), "only Back")
	assert_eq(hud.title_text(), ReplayDriver.OLD_VERSION_MESSAGE)
	assert_true(main._run.driver == null, "not played")
	main.play_replay({})
	assert_eq(hud.title_text(), ReplayDriver.EMPTY_MESSAGE)
	hud.back_pressed.emit()
	assert_true(main._menus.current() is LeaderboardScreen, "Back to the leaderboards")
	assert_eq(board.submitted, 0)
	main.free()
	DirAccess.remove_absolute(TEST_PATH)
