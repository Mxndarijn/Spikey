extends SceneTree
## Plays one run file (RunFile) in the real game, one sim tick per frame, and
## writes a JSON summary: whether the game ended on the same score, coins,
## tick and checksum as the sim replay (RunRender.result()). Run it through
## tools/render_run.ps1 (docs/RENDERING.md):
##   headless + --fixed-fps 60: checks the run, draws nothing;
##   --write-movie + --fixed-fps 60: films every frame (the .ps1 starts Godot
##   on a hidden desktop, so no window shows).
##   -- <run.json> <summary.json> [hold_frames=90] [hud=replay|live]
## Exits 0 when the run matches, 1 when it doesn't or can't be played.

## Frames past the end of the run before giving up (the run should end by RunFile.LONG_MAX_TICKS).
const SPARE_FRAMES := 600

var _render: RunRender
var _summary_path := ""
var _hold := 90
var _frames := 0
var _held := 0
var _hud := RunRender.HUD_REPLAY


func _initialize() -> void:
	# Never play sound on the developer's PC, never take focus.
	AudioServer.set_bus_mute(0, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <run.json> <summary.json> [hold_frames] [hud]")
		quit(2)
		return
	_summary_path = args[1]
	if args.size() > 2:
		_hold = maxi(0, int(args[2]))
	if args.size() > 3:
		_hud = args[3]
	_render = RunRender.new(RunFile.load_file(args[0]))
	var problem := _render.problem()
	if not problem.is_empty():
		_end({"ok": false, "reason": problem}, 1)


func _process(_delta: float) -> bool:
	if _render == null:
		return false
	if _render.main == null:
		# The tree is ready by the first frame (main's _ready needs it).
		_render.start(root, _hud)
		return false
	_frames += 1
	if _render.run_over():
		_held += 1
		if _held > _hold:
			var result := _render.result()
			_end(result, 0 if result.ok else 1)
	elif _frames > RunFile.LONG_MAX_TICKS + SPARE_FRAMES:
		_end({"ok": false, "reason": "the run never ended"}, 1)
	return false


func _end(result: Dictionary, code: int) -> void:
	result["frames"] = _frames
	result["gameplay_version"] = SimConfig.GAMEPLAY_VERSION
	var f := FileAccess.open(_summary_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "  ", false) + "\n")
		f.close()
	if result.ok:
		print("render_run: ok, score %d, %d frames" % [result.score, _frames])
	else:
		printerr("render_run: FAILED: %s" % result.reason)
	if _render != null:
		_render.finish()
		_render = null
	quit(code)
