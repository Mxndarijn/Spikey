extends SceneTree
## Walks through every screen and saves a screenshot of each, using a throwaway
## save file so the player's own profile is untouched. Opens a real window
## (rendering needs one), so only run it when the user asks for screenshots.
##   godot --path . --windowed --position -20000,-20000 -s res://tools/capture_tour.gd -- <out_dir>

const PROFILE := "user://tour_profile.json"

## [frame, action, screenshot name]
const STEPS := [
	[20, "", "01_home"],
	[21, "shop_flyer", ""],
	[45, "", "02_shop_flyers"],
	[46, "shop_world", ""],
	[70, "", "03_shop_worlds"],
	[71, "shop_trail", ""],
	[95, "", "04_shop_trails"],
	[96, "play", ""],
	[100, "tap", ""],
	[280, "", "05_run"],
	[281, "pause", ""],
	[295, "", "06_paused"],
	[296, "pause", ""],
	[300, "", "07_countdown"],
	[480, "stop_tapping", ""],
	[650, "", "08_game_over"],
]

var _main: Node
var _frame := 0
var _out := "user://tour"
var _tapping := false


func _initialize() -> void:
	# Never play sound on the developer's PC (this tool opens a real window).
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	DirAccess.remove_absolute(PROFILE)
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _tapping:
		var s: SimState = _main._run.sim.state
		if not s.started or (s.y > SimConfig.BIRD_START_Y and s.vy >= 0):
			_main._run.request_tap()
	for step: Array in STEPS:
		if step[0] != _frame:
			continue
		if step[1] != "":
			_act(step[1])
		if step[2] != "":
			var path: String = _out.path_join(step[2] + ".png")
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	if _frame > STEPS[STEPS.size() - 1][0]:
		DirAccess.remove_absolute(PROFILE)
		return true
	return false


func _act(action: String) -> void:
	var screen: Control = _main._menus.current()
	match action:
		"shop_flyer":
			_main.show_shop(ItemKind.FLYER)
		"shop_world":
			(screen as CollectionScreen)._show_kind(ItemKind.WORLD)
		"shop_trail":
			(screen as CollectionScreen)._show_kind(ItemKind.TRAIL)
		"play":
			_main.start_run()
		"tap":
			_tapping = true
		"pause":
			_main._toggle_pause()
		"stop_tapping":
			_tapping = false
