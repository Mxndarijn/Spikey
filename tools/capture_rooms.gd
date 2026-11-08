extends SceneTree
## Visual playtest: opens every room kind in practice (developer mode, a
## throwaway save), lets the playtest bot fly a little, and saves a screenshot.
## Opens a real window (rendering needs one); run it only when the user agrees.
##   godot --audio-driver Dummy --path . --windowed --position -20000,-20000
##     -s res://tools/capture_rooms.gd -- <out_dir> [filter]

const PROFILE := "user://capture_rooms_profile.json"
## Frames to fly before the shot (lets hazards move and wall spikes appear).
const FLY_FRAMES := 150

var _main: Node
var _out := "user://rooms"
var _ids: Array[String] = []
var _i := -1
var _frame := 0
var _bot := PlannerBot.new(7)


func _initialize() -> void:
	# Never play sound on the developer's PC (this tool opens a real window).
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var filter := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(_out)
	DevMode.override = 1
	for def in RoomCatalog.all():
		if filter.is_empty() or def.id.contains(filter):
			_ids.append(def.id)
	DirAccess.remove_absolute(PROFILE)
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _i < 0 or _frame > FLY_FRAMES:
		if _i >= 0:
			var path := _out.path_join("%02d_%s.png" % [_i, _ids[_i]])
			root.get_texture().get_image().save_png(path)
		_i += 1
		_frame = 0
		if _i >= _ids.size():
			DirAccess.remove_absolute(PROFILE)
			print("captured %d rooms" % _ids.size())
			return true
		_main.start_practice(_ids[_i])
		return false
	# The off-screen window has no focus, and the game pauses when focus goes.
	if _main._run.paused:
		_main._set_paused(false)
	var sim: GameSim = _main._run.sim
	if sim != null and not sim.is_over() and _bot.decide(sim):
		_main._run.request_tap()
	return false
