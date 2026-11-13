extends SceneTree
## HUD readability review: the in-run HUD (score, pause, coins, boss bar, key
## counter, pause screen, revive countdown) over every world, at fixed moments
## of fixed seeds, so two builds show the same frames. Each moment is saved
## twice at the same tick: with the HUD and without it (`__clean`), so the
## contrast under each HUD element can be measured. Draws for real: run it only
## through tools/capture_hud.ps1 (hidden desktop) and only when the user asked.
##   -- <out_dir> <tag> [notch] [worlds]
## `tag` names the build in the file names (e.g. before, after); `notch`
## (canvas px) fakes a notch like capture_worlds.
## Writes <out_dir>/<world>__<tag>__<scene>__<moment>[__clean].jpg and
## <out_dir>/<world>__<tag>__rects.json (HUD element rects, room px).

const PROFILE := "user://capture_hud_profile.json"
const RUN_SEED := 4242
const RUN_TICKS: Array[int] = [240, 600, 1080]

var _main: Node
var _out := ""
var _tag := "none"
var _notch := 0.0
var _worlds: Array[String] = []
var _scenes: Array = []
var _wi := -1
var _si := -1
var _k := 0
## Capture steps in progress: 0 none, 1 save HUD frame, 2 save clean frame,
## 3 save paused, 4 save countdown.
var _step := 0
var _bot := PlannerBot.new(7)
var _rects := {}


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	_tag = args[1] if args.size() > 1 else "none"
	_notch = float(args[2]) if args.size() > 2 else 0.0
	var filter := args[3] if args.size() > 3 else ""
	for t in Catalog.worlds():
		if filter.is_empty() or t.id in filter.split(","):
			_worlds.append(t.id)
	# [name, room id ("" = a real run), variant, ticks, extras]
	_scenes = [
		["run", "", "", RUN_TICKS, true],
		["boss", "boss_saw", "", [420], false],
		["keys", "lockexit", "trio", [200], false],
	]
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


func _hud() -> Hud:
	return _main._hud


## The room under the fake notch, as ScreenLayout would on that phone.
func _fit() -> void:
	var visible: Vector2 = _main.get_viewport().get_visible_rect().size
	var safe := Rect2(0, _notch, visible.x, visible.y - _notch)
	_main.set_room_rect(ScreenLayout.room_rect(visible, safe))


func _name(moment: String, clean: bool) -> String:
	var s: Array = _scenes[_si]
	return "%s__%s__%s__%s%s.jpg" % [_worlds[_wi], _tag, s[0], moment, "__clean" if clean else ""]


func _save(moment: String, clean: bool) -> void:
	root.get_texture().get_image().save_jpg(_out.path_join(_name(moment, clean)), 0.92)


func _next_world() -> bool:
	if _wi >= 0:
		var f := FileAccess.open(
			_out.path_join("%s__%s__rects.json" % [_worlds[_wi], _tag]), FileAccess.WRITE
		)
		f.store_string(JSON.stringify(_rects, "  "))
	_wi += 1
	_si = -1
	_rects = {}
	if _wi >= _worlds.size():
		DirAccess.remove_absolute(PROFILE)
		print("captured %d worlds" % _worlds.size())
		quit(0)
		return true
	_main._profile.equip(ItemKind.WORLD, _worlds[_wi])
	_main._look.use_equipped()
	return _next_scene()


func _next_scene() -> bool:
	_si += 1
	_k = 0
	_step = 0
	if _si >= _scenes.size():
		return _next_world()
	var s: Array = _scenes[_si]
	seed(RUN_SEED)
	_bot = PlannerBot.new(7)
	if s[1] == "":
		_main.start_run()
	else:
		_main.start_picker_practice(s[1], s[2])
	return false


func _process(_delta: float) -> bool:
	if _wi < 0:
		return _next_world()
	_fit()
	if _step != 0:
		return _capture_step()
	return _play()


## One step of a capture in progress (the frame drawn last is saved). True
## when the whole capture is done.
func _capture_step() -> bool:
	var run: RunController = _main._run
	var s: Array = _scenes[_si]
	var ticks: Array = s[3]
	var next_scene := false
	match _step:
		1:
			_save("t%04d" % ticks[_k], false)
			_note_rects("t%04d" % ticks[_k])
			_hud().visible = false
			_step = 2
		2:
			_save("t%04d" % ticks[_k], true)
			_hud().visible = true
			_k += 1
			if _k < ticks.size():
				run.set_paused(false)
				_step = 0
			elif s[4]:
				_main._set_paused(true)
				_step = 3
			else:
				next_scene = true
		3:
			_save("paused", false)
			_main._set_paused(false)
			run.set_paused(true)
			_hud().countdown.show_count(3)
			_step = 4
		4:
			_save("count", false)
			_hud().countdown.show_count(0)
			next_scene = true
	return _next_scene() if next_scene else false


## The bot plays on until the next moment to grab.
func _play() -> bool:
	var run: RunController = _main._run
	var sim: GameSim = run.sim
	var s: Array = _scenes[_si]
	# The hidden window has no focus, and the game pauses when focus goes.
	if run.paused:
		_main._set_paused(false)
	if sim == null:
		return false
	# Practice scenes show the real run's HUD (no banner, coins on).
	if s[1] != "" and _hud().is_practicing():
		_hud().set_practice("")
		_hud().show_running()
	if sim.is_over():
		printerr("%s %s died at tick %d" % [_worlds[_wi], s[0], sim.state.tick])
		return _next_scene()
	if sim.state.tick >= s[3][_k]:
		run.set_paused(true)
		_step = 1
	elif _bot.decide(sim):
		run.request_tap()
	return false


func _note_rects(moment: String) -> void:
	var h := _hud()
	var origin: Vector2 = h._root.global_position
	var room: Rect2 = _main._hud.room_rect
	var out := {"room": [room.position.x, room.position.y], "hud_origin": [origin.x, origin.y]}
	for pair in [["score", h._score], ["pause", h._pause_button], ["coins", h._run_coins]]:
		var c: Control = pair[1]
		if c.visible:
			var r := c.get_global_rect()
			out[pair[0]] = [r.position.x, r.position.y, r.size.x, r.size.y]
	var sc: Label = h._score
	out["score_text"] = sc.text
	out["ink"] = sc.get_theme_color("font_color").to_html()
	_rects["%s/%s" % [_scenes[_si][0], moment]] = out
