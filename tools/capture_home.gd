extends SceneTree
## Home on one world, for the design page in docs/ui-rework: Home with two
## battles on your turn, the mode sheet, no battles, many battles with the
## lost-spot line. Opens a real window
## (rendering needs one): only when the user asks for screenshots.
##   -- <out_dir> <world>

const PROFILE := "user://capture_home_profile.json"

var _main: Node
var _left_s := 240.0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.remove_absolute(PROFILE)
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	root.add_child(_main)
	_tour.call_deferred()


func _process(delta: float) -> bool:
	_left_s -= delta
	return _left_s <= 0.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _tour() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _frames(10)
	var profile: Profile = _main._profile
	profile.best_score = 87
	profile.coins = 1240
	profile.diamonds = 12
	_main.set_world(args[1])
	await _frames(240)
	await _home(out, "home", 2, false, false)
	await _home(out, "sheet", 2, true, false)
	await _home(out, "none", 0, false, false)
	await _home(out, "many", 5, false, true)
	DirAccess.remove_absolute(PROFILE)
	quit()


func _home(out: String, name: String, turns: int, sheet: bool, notice: bool) -> void:
	_main.show_home()
	await _frames(2)
	var home := _main._menus.current() as HomeScreen
	home.set_daily_rank(14)
	home.set_battle_turns(turns)
	var info := DailyRunInfo.parse({"number": 12, "resets_in_s": 15120, "tries_used": 1})
	home.set_daily_info(info)
	if notice:
		home.show_notice("Kofi took your #3 spot on today's board")
	if sheet:
		home.open_modes()
	await _frames(40)
	var path := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
