extends SceneTree
## Renders the main scene, plays it with a simple hover bot and saves a PNG.
## Run it through tools/screenshot.ps1, which keeps the window off-screen.
##   -- <out.png> [frame=200]

var _frame := 0


func _initialize() -> void:
	# Never steal focus from the user's desktop.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	root.add_child(load("res://game/main.tscn").instantiate())


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screen.png"
	var at := int(args[1]) if args.size() > 1 else 200
	_frame += 1
	var run: RunController = root.get_child(root.get_child_count() - 1).get_node("RunController")
	var s := run.sim.state
	if _frame == 5 or (_frame > 5 and s.y > SimConfig.BIRD_START_Y and s.vy >= 0):
		run.request_tap()
	if _frame >= at:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
