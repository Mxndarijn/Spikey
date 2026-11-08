extends SceneTree
## Renders the main scene, plays it with a simple hover bot and saves a PNG.
## Run it through tools/screenshot.ps1, which keeps the window off-screen.
##   -- <out.png> [frame=200] [world=sunset] [die=0] [screen=]
## screen "home" or "leaderboard" shows that menu instead of playing a run.
## With die=1 the bot stops tapping early, so the shot shows the game-over panel.

const DIE_AFTER_FRAME := 40

var _frame := 0
var _main: Node


func _initialize() -> void:
	# Never play sound on the developer's PC (this tool opens a real window).
	AudioServer.set_bus_mute(0, true)
	# Never steal focus from the user's desktop.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_main = load("res://game/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screen.png"
	var at := int(args[1]) if args.size() > 1 else 200
	# "-" means none (screenshot.ps1 can't pass empty arguments).
	var world := args[2] if args.size() > 2 and args[2] != "-" else ""
	var die := args.size() > 3 and args[3] == "1"
	var screen := args[4] if args.size() > 4 and args[4] != "-" else ""
	_frame += 1
	if not screen.is_empty():
		if _frame == 2:
			if not world.is_empty():
				_main.set_world(world)
			if screen == "leaderboard":
				_main.show_leaderboard()
			else:
				_main.show_home()
		if _frame >= at:
			_save(out)
			return true
		return false
	if _frame == 2:
		_main.start_run()
		if not world.is_empty():
			_main.set_world(world)
	var run: RunController = _main.get_node("RunController")
	var s := run.sim.state
	var hover := s.y > SimConfig.BIRD_START_Y and s.vy >= 0
	if _frame == 5 or (_frame > 5 and hover and not (die and _frame > DIE_AFTER_FRAME)):
		run.request_tap()
	if _frame >= at:
		_save(out)
		return true
	return false


func _save(out: String) -> void:
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
