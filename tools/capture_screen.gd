extends SceneTree
## Renders the main scene, plays it with a simple hover bot and saves a PNG.
## Run it through tools/screenshot.ps1, which keeps the window off-screen.
##   -- <out.png> [frame=200] [world=sunset] [die=0]
## With die=1 the bot stops tapping early, so the shot shows the game-over panel.

const DIE_AFTER_FRAME := 40

var _frame := 0
var _main: Node


func _initialize() -> void:
	# Never steal focus from the user's desktop.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_main = load("res://game/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screen.png"
	var at := int(args[1]) if args.size() > 1 else 200
	var world := args[2] if args.size() > 2 else ""
	var die := args.size() > 3 and args[3] == "1"
	_frame += 1
	if _frame == 2 and not world.is_empty():
		_main.set_world(world)
	var run: RunController = _main.get_node("RunController")
	var s := run.sim.state
	var hover := s.y > SimConfig.BIRD_START_Y and s.vy >= 0
	if _frame == 5 or (_frame > 5 and hover and not (die and _frame > DIE_AFTER_FRAME)):
		run.request_tap()
	if _frame >= at:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
