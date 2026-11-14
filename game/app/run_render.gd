class_name RunRender
extends RefCounted
## Plays a RunFile in the real game (main.tscn, its views and painters) the
## way a leaderboard replay plays: tools/render_run.gd drives it frame by
## frame, headless to check a run or in Movie Maker mode to film it
## (docs/RENDERING.md). Uses a throwaway profile and no server, so the
## player's save and the leaderboards never change.

## Where the throwaway profile goes (removed again by finish()).
const PROFILE_PATH := "user://render_run_profile.json"
## A board config that never exists: the boards stay samples, nothing goes online.
const NO_BOARD_CONFIG := "user://render_run_no_board_config.json"
const HUD_REPLAY := "replay"
const HUD_LIVE := "live"

var run_file: RunFile
var main: Node


func _init(p_run_file: RunFile) -> void:
	run_file = p_run_file


## Why this run can't be rendered, or "": the file itself, then every
## loadout id against the catalog (the game would quietly show its own look).
func problem() -> String:
	if not run_file.read_problem.is_empty():
		return run_file.read_problem
	var version := run_file.replay.gameplay_version
	if version != SimConfig.GAMEPLAY_VERSION:
		return (
			"gameplay_version %d, this build plays %d: record the run again"
			% [version, SimConfig.GAMEPLAY_VERSION]
		)
	return look_problem(run_file.loadout)


static func look_problem(loadout: Dictionary) -> String:
	for kind: Variant in loadout:
		if not str(kind) in ItemKind.ALL:
			return 'unknown loadout kind "%s"' % kind
		var known := Catalog.ids(str(kind))
		if not str(loadout[kind]) in known:
			return 'unknown %s "%s" (known: %s)' % [kind, loadout[kind], ", ".join(known)]
	return ""


## Builds the game under `parent` and starts the replay. Check problem() first.
## `hud`: HUD_REPLAY shows the replay overlay (chip, "<name> scored N");
## HUD_LIVE the HUD a player sees in a run ("Tap to flap", then the score,
## coins and pause), and after the crash the final score stays up.
func start(parent: Node, hud: String = HUD_REPLAY) -> void:
	var p := Profile.new()
	p.onboarded = true
	run_file.apply_settings(p.settings)
	p.save(PROFILE_PATH)
	main = load("res://game/main.tscn").instantiate()
	main.profile_path = PROFILE_PATH
	main.board_config_path = NO_BOARD_CONFIG
	main.season = run_file.replay.season
	parent.add_child(main)
	main._scrub.shown = false
	main.play_replay(run_file.to_dict())
	if hud == HUD_LIVE:
		_live_hud()
		# After main's own handler, which shows the replay result.
		controller().died.connect(_on_died_live.unbind(1))


## The run's own HUD in place of the replay overlay.
func _live_hud() -> void:
	main._hud.replay_hud().set_run("", 0)
	main._hud.show_ready()


func _on_died_live() -> void:
	main._hud.replay_hud().set_run("", 0)
	main._hud.show_running()


func controller() -> RunController:
	return main.get_node("RunController") as RunController


## The run in the game has ended (died for good, or RunFile.LONG_MAX_TICKS).
func run_over() -> bool:
	var sim := controller().sim
	return sim.is_over() or sim.state.tick >= RunFile.LONG_MAX_TICKS


## The run as the game played it against the sim replay and the file's
## claimed result. {ok, reason, score, coins, end_tick, checksum}.
func result() -> Dictionary:
	var sim := controller().sim
	var out := {
		"ok": false,
		"reason": "",
		"score": sim.state.score,
		"coins": sim.state.coins,
		"end_tick": sim.state.tick,
		"checksum": sim.checksum(),
	}
	var verified := run_file.check()
	if not verified.ok:
		out.reason = "replay check failed: %s" % verified.reason
		return out
	for key in ["score", "coins", "end_tick", "checksum"]:
		if out[key] != verified[key]:
			out.reason = (
				"the game ended on %s %d, the sim replay on %d" % [key, out[key], verified[key]]
			)
			return out
	out.ok = true
	return out


func finish() -> void:
	if main != null:
		main.free()
		main = null
	SafeFile.remove(PROFILE_PATH)
