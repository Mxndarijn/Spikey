extends SceneTree
## Visual review of the world backgrounds: for every world, the Leaderboards
## screen and a seeded practice run (planner bot), saved as JPGs. Draws for
## real, so run it only through tools/capture_worlds.ps1 (a hidden desktop, like
## tools/render_run.ps1) and only when the user asked for frames.
##   -- <out_dir> <tag> [notch] [worlds]
## `notch` (canvas px) fakes a notch: the safe area starts that far down, so the
## room sits under it the way ScreenLayout places it on such a phone.
## Writes <out_dir>/<world>__<tag>__board.jpg and <world>__<tag>__run.jpg.

const PROFILE := "user://capture_worlds_profile.json"
const SEED := 4242
## Frames the Leaderboards screen settles for, and the run tick to grab.
const BOARD_FRAMES := 30
const RUN_TICK := 150

var _main: Node
var _out := ""
var _tag := ""
var _notch := 0.0
var _worlds: Array[String] = []
var _i := -1
var _phase := 0
var _wait := 0
var _bot := PlannerBot.new(7)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	_tag = args[1] if args.size() > 1 else "shot"
	_notch = float(args[2]) if args.size() > 2 else 0.0
	var filter := args[3] if args.size() > 3 else ""
	for t in Catalog.worlds():
		if filter.is_empty() or t.id in filter.split(","):
			_worlds.append(t.id)
	DirAccess.make_dir_recursive_absolute(_out)
	DirAccess.remove_absolute(PROFILE)
	var p := Profile.new()
	p.onboarded = true
	p.leaderboard_name = "Capture"
	for id in _worlds:
		p.grant(ItemKind.WORLD, id)
	p.save(PROFILE)
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	_main.board_config_path = RunRender.NO_BOARD_CONFIG
	root.add_child(_main)


## Puts the room under the fake notch, as ScreenLayout would on that phone.
func _fit() -> void:
	var visible: Vector2 = _main.get_viewport().get_visible_rect().size
	var safe := Rect2(0, _notch, visible.x, visible.y - _notch)
	_main.set_room_rect(ScreenLayout.room_rect(visible, safe))


func _save(kind: String) -> void:
	var name := "%s__%s__%s.jpg" % [_worlds[_i], _tag, kind]
	root.get_texture().get_image().save_jpg(_out.path_join(name), 0.9)


func _next_world() -> bool:
	_i += 1
	if _i >= _worlds.size():
		DirAccess.remove_absolute(PROFILE)
		print("captured %d worlds" % _worlds.size())
		quit(0)
		return true
	_main._profile.equip(ItemKind.WORLD, _worlds[_i])
	_main._look.use_equipped()
	_main.show_leaderboard()
	_phase = 0
	_wait = 0
	return false


func _process(_delta: float) -> bool:
	if _i < 0:
		return _next_world()
	_fit()
	if _phase == 0:
		_wait += 1
		if _wait >= BOARD_FRAMES:
			_save("board")
			seed(SEED)
			_bot = PlannerBot.new(7)
			_main.start_seed_practice(SEED)
			_phase = 1
		return false
	var run: RunController = _main._run
	if run.paused:
		_main._set_paused(false)
	var sim: GameSim = run.sim
	if sim == null:
		return false
	if sim.state.tick >= RUN_TICK or sim.is_over():
		_save("run")
		return _next_world()
	if _bot.decide(sim):
		run.request_tap()
	return false
