extends TestCase
## Run files (RunFile) and playing one in the real game (RunRender), the way
## tools/render_run.gd does before it films anything: same end as the sim
## replay, the file's look, and loud failures. Headless: nothing is drawn.

const TMP := "user://test_run_file.json"


static func _recorded(seed_value: int, ticks: int = 300) -> Replay:
	return SimBots.play(seed_value, SimBots.gap_seeker, 2, ticks)


## Some look that isn't the default one, from the catalog.
static func _look() -> Dictionary:
	return {
		ItemKind.FLYER: Catalog.ids(ItemKind.FLYER)[1],
		ItemKind.WORLD: Catalog.ids(ItemKind.WORLD)[1],
		ItemKind.TRAIL: Catalog.ids(ItemKind.TRAIL)[1],
		ItemKind.PORTAL: Catalog.ids(ItemKind.PORTAL)[1],
	}


func test_round_trip_through_json_file() -> void:
	var f := RunFile.from_replay(_recorded(7101), _look(), "tier 2")
	f.settings["color_blind_spikes"] = true
	assert_true(f.save_file(TMP), "saved")
	var back := RunFile.load_file(TMP)
	assert_eq(back.read_problem, "")
	assert_eq(back.to_dict(), f.to_dict(), "same file after JSON")
	assert_eq(back.replay.taps, f.replay.taps)
	assert_eq(back.loadout[ItemKind.FLYER], _look()[ItemKind.FLYER])
	assert_true(back.settings["color_blind_spikes"])
	assert_eq(back.name, "tier 2")
	var d := back.to_dict()
	assert_eq(d.format, RunFile.FORMAT)
	assert_eq(d.format_version, RunFile.FORMAT_VERSION)
	assert_eq(d.gameplay_version, SimConfig.GAMEPLAY_VERSION)
	DirAccess.remove_absolute(TMP)


func test_bad_files_say_why() -> void:
	var good := RunFile.from_replay(_recorded(7102, 60)).to_dict()
	assert_true(
		RunFile.load_file("user://no_such_run.json").read_problem.begins_with("no run file")
	)
	var d := good.duplicate()
	d.erase("format")
	assert_true(RunFile.from_dict(d).read_problem.begins_with("not a run file"))
	d = good.duplicate()
	d.format_version = RunFile.FORMAT_VERSION + 1
	assert_true(RunFile.from_dict(d).read_problem.contains("format_version"))
	d = good.duplicate()
	d.erase("taps")
	assert_eq(RunFile.from_dict(d).read_problem, 'run file has no "taps"')
	d = good.duplicate()
	d.loadout = {"hat": "top"}
	assert_true(RunFile.from_dict(d).read_problem.begins_with('unknown loadout kind "hat"'))
	d = good.duplicate()
	d.settings = {"sparkles": true}
	assert_true(RunFile.from_dict(d).read_problem.begins_with("unknown setting"))
	assert_false(RunFile.from_dict(d).check().ok, "a bad file never checks out")


func test_check_replays_the_claim() -> void:
	var f := RunFile.from_replay(_recorded(7103))
	assert_true(f.check().ok, "a bot run checks out")
	var lying := RunFile.from_dict(f.to_dict())
	lying.replay.score += 1
	assert_true(lying.check().reason.begins_with("score mismatch"))
	var old := RunFile.from_dict(f.to_dict())
	old.replay.gameplay_version -= 1
	assert_false(old.check().ok, "an older gameplay version fails")


func test_render_problems_fail_loudly() -> void:
	var f := RunFile.from_replay(_recorded(7104, 60), _look())
	assert_eq(RunRender.new(f).problem(), "")
	var old := RunFile.from_dict(f.to_dict())
	old.replay.gameplay_version = SimConfig.GAMEPLAY_VERSION - 1
	var why := RunRender.new(old).problem()
	assert_true(why.begins_with("gameplay_version %d" % old.replay.gameplay_version), why)
	var odd := RunFile.from_dict(f.to_dict())
	odd.loadout[ItemKind.FLYER] = "no_such_flyer"
	assert_true(RunRender.new(odd).problem().begins_with('unknown flyer "no_such_flyer"'))
	var broken := RunFile.from_dict({})
	assert_eq(RunRender.new(broken).problem(), broken.read_problem)


## The real game plays the file with its look and ends where the sim replay does.
func test_game_plays_the_file_to_the_same_end() -> void:
	var f := RunFile.from_replay(_recorded(7105, 600), _look(), "tier 1")
	f.settings["color_blind_spikes"] = true
	# Through JSON, as a bot's file arrives.
	f = RunFile.from_dict(JSON.parse_string(JSON.stringify(f.to_dict())))
	var render := RunRender.new(f)
	render.start((Engine.get_main_loop() as SceneTree).root)
	var main := render.main
	assert_eq(main.mode, main.Mode.REPLAY)
	assert_eq(main._bird._character.id, f.loadout[ItemKind.FLYER], "their flyer")
	assert_eq(main._look.theme.id, f.loadout[ItemKind.WORLD], "their world")
	assert_eq(main._look.trail_style.id, f.loadout[ItemKind.TRAIL], "their trail")
	assert_eq(main._room.portal_style.id, f.loadout[ItemKind.PORTAL], "their portal")
	assert_true(main._profile.settings.color_blind_spikes, "their settings")
	assert_eq(main._hud.replay_hud().chip_text(), "Replay: tier 1, %d" % f.replay.score)
	assert_true(FileAccess.file_exists(RunRender.PROFILE_PATH), "a throwaway profile")
	var rc := render.controller()
	while not render.run_over():
		rc.advance()
	var result := render.result()
	assert_true(result.ok, str(result.reason))
	assert_eq(result.score, f.replay.score)
	assert_eq(result.end_tick, f.replay.end_tick)
	assert_eq(result.checksum, f.replay.checksum)
	render.finish()
	assert_false(FileAccess.file_exists(RunRender.PROFILE_PATH), "the throwaway profile is gone")


func test_result_fails_on_a_wrong_claim() -> void:
	var f := RunFile.from_replay(_recorded(7106, 120))
	f.replay.coins += 1
	var render := RunRender.new(f)
	render.start((Engine.get_main_loop() as SceneTree).root)
	while not render.run_over():
		render.controller().advance()
	var result := render.result()
	assert_false(result.ok)
	assert_true(str(result.reason).contains("coins mismatch"), str(result.reason))
	render.finish()


## The live HUD: no replay overlay, the run's score, and the score stays up after the crash.
func test_live_hud_shows_the_run_hud() -> void:
	var f := RunFile.from_replay(_recorded(7107, 240), {}, "tier 4")
	var render := RunRender.new(f)
	render.start((Engine.get_main_loop() as SceneTree).root, RunRender.HUD_LIVE)
	var hud: Hud = render.main._hud
	assert_false(hud.replay_hud().visible, "no replay chip")
	while not render.run_over():
		render.controller().advance()
	assert_true(render.result().ok, str(render.result().reason))
	assert_false(hud.replay_hud().visible, "no replay result screen")
	assert_true(hud._score.visible, "the final score stays up")
	render.finish()
