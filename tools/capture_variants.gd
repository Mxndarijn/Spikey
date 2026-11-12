extends SceneTree
## Visual review: plays every room variant (boss rooms too) as a debug-picker
## practice run with the planner bot and saves JPG frames at fixed sim ticks.
## Draws for real, so run it only through tools/capture_variants.ps1 (a hidden
## desktop, like tools/render_run.ps1) and only when the user asked for frames.
##   -- <out_dir> <world_id> [filter]
## Writes <out_dir>/<room>__<variant>__t<tick>.jpg.

const PROFILE := "user://capture_variants_profile.json"
## Sim ticks to grab in normal rooms and in boss rooms.
const TICKS: Array[int] = [60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360, 390, 420, 450, 480]
const BOSS_TICKS: Array[int] = [
	60, 180, 300, 420, 540, 660, 780, 900, 1020, 1140, 1260, 1380, 1500, 1620, 1740
]
## Restarts after a death before moving on.
const MAX_TRIES := 6

var _main: Node
var _out := ""
var _jobs: Array = []
var _i := -1
var _k := 0
var _tries := 0
var _bot := PlannerBot.new(7)
var _started := false


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var world := args[1] if args.size() > 1 else ""
	var filter := args[2] if args.size() > 2 else ""
	DirAccess.make_dir_recursive_absolute(_out)
	for def in RoomCatalog.all():
		if not filter.is_empty() and not def.id in filter.split(","):
			continue
		var vs := RoomPicker.variant_ids(def)
		if vs.is_empty():
			vs = [""]
		for v in vs:
			_jobs.append([def.id, v, def.group == "boss"])
	DirAccess.remove_absolute(PROFILE)
	var p := Profile.new()
	p.onboarded = true
	if not world.is_empty():
		p.grant(ItemKind.WORLD, world)
		p.equip(ItemKind.WORLD, world)
	p.save(PROFILE)
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	_main.board_config_path = RunRender.NO_BOARD_CONFIG
	root.add_child(_main)


func _ticks() -> Array[int]:
	return BOSS_TICKS if _jobs[_i][2] else TICKS


func _next() -> bool:
	_i += 1
	_k = 0
	_tries = 0
	if _i >= _jobs.size():
		DirAccess.remove_absolute(PROFILE)
		print("captured %d variants" % _jobs.size())
		quit(0)
		return true
	_start()
	return false


## Starts the current job's practice run on a fixed seed (main draws the
## practice seed with randi() right away), so a capture of the same room on
## another build shows the same moments.
func _start() -> void:
	seed(hash("%s/%s/%d" % [_jobs[_i][0], _jobs[_i][1], _tries]))
	_bot = PlannerBot.new(7)
	_main.start_picker_practice(_jobs[_i][0], _jobs[_i][1])


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _next()
	var run: RunController = _main._run
	# The hidden window has no focus, and the game pauses when focus goes.
	if run.paused:
		_main._set_paused(false)
	var sim: GameSim = run.sim
	if sim == null:
		return false
	if sim.is_over():
		_tries += 1
		if _tries > MAX_TRIES:
			printerr("gave up on %s %s at frame %d" % [_jobs[_i][0], _jobs[_i][1], _k])
			return _next()
		_start()
		return false
	var ticks := _ticks()
	if sim.state.tick >= ticks[_k]:
		var name := "%s__%s__t%04d.jpg" % [_jobs[_i][0], _jobs[_i][1], ticks[_k]]
		root.get_texture().get_image().save_jpg(_out.path_join(name), 0.88)
		_k += 1
		if _k >= ticks.size():
			return _next()
	if _bot.decide(sim):
		run.request_tap()
	return false
