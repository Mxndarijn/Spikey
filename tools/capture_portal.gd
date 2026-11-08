extends SceneTree
## Visual check of the exit portals: plays a run with the playtest bot until
## an exit opens, then saves shots as it opens and while it
## is open; then the same for a Calm/Wild fork. Opens a real window.
##   godot --audio-driver Dummy --path . --windowed --position -20000,-20000
##     -s res://tools/capture_portal.gd -- <out_dir>

const PROFILE := "user://capture_portal_profile.json"
## Frames after the exit opens at which to take a shot.
const SHOTS: Array[int] = [8, 20, 45, 90]
## Give up (and close the window) after this many frames.
const MAX_FRAMES := 1800

var _main: Node
var _out := "user://portal"
var _bot := PlannerBot.new(5)
var _phase := 0
var _since := -1
var _fork := false
var _frames := 0


func _initialize() -> void:
	# Never play sound on the developer's PC (this tool opens a real window).
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	DevMode.override = 1
	DirAccess.remove_absolute(PROFILE)
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _phase == 0:
		_main.start_run()
		_phase = 1
		return false
	_frames += 1
	if _frames > MAX_FRAMES:
		print("gave up waiting for an exit")
		return true
	# The off-screen window has no focus, and the game pauses when focus goes.
	if _main._run.paused:
		_main._set_paused(false)
	var sim: GameSim = _main._run.sim
	if sim == null or sim.is_over():
		print("run ended before the exit")
		return true
	if _phase == 1 and sim.state.started and sim.state.score < 9:
		# Jump to 9 points so the next bounce opens an exit.
		sim.state.score = 9
	if _phase == 2 and not _fork and sim.state.started:
		# Second part: jump to 49 points so the next bounce opens a fork.
		sim.state.score = 49
		_fork = true
	if sim.state.exit_open and _since < 0:
		_since = 0
	if _since >= 0:
		_since += 1
		if _since in SHOTS:
			var name := "%s_%03d.png" % ["fork" if _fork else "exit", _since]
			root.get_texture().get_image().save_png(_out.path_join(name))
		if _since > SHOTS[SHOTS.size() - 1]:
			if _fork:
				print("portal shots saved")
				DirAccess.remove_absolute(PROFILE)
				return true
			# Fly through, then set up the fork.
			_since = -1
			_phase = 2
	if _bot.decide(sim):
		_main._run.request_tap()
	return false
