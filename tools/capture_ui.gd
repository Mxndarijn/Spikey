extends SceneTree
## Walks every screen of the app and saves a PNG of each (docs/ui-rework/),
## with made-up battles, boards and a Daily Run so the screens are full. Uses a
## throwaway save, so the player's own profile is untouched. Opens a real window
## (rendering needs one): run it through tools/capture_ui.ps1, only when the
## user asks for screenshots.
##   -- <out_dir> [only=name,name] [world=id]

const PROFILE := "user://capture_ui_profile.json"
const RIVAL := "Maximilianus12"

var _main: Node
var _out := "user://capture_ui"
var _only: Array[String] = []
var _world := ""
var _saved := 0
## Gives up after this long, so a script error never leaves the window open.
var _left_s := 300.0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1 and args[1] != "-":
		for n in args[1].split(","):
			_only.append(n)
	if args.size() > 2 and args[2] != "-":
		_world = args[2]
	DirAccess.make_dir_recursive_absolute(_out)
	DirAccess.remove_absolute(PROFILE)
	DirAccess.remove_absolute(PROFILE.get_basename() + "_runs.json")
	_main = load("res://game/main.tscn").instantiate()
	_main.profile_path = PROFILE
	root.add_child(_main)
	_tour.call_deferred()


func _process(delta: float) -> bool:
	_left_s -= delta
	if _left_s <= 0.0:
		printerr("capture_ui: gave up (timed out)")
		return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait: int = 30) -> void:
	await _frames(wait)
	if not _only.is_empty() and not name in _only:
		return
	var path: String = _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	_saved += 1
	# Every shot asked for is saved: done, no need to walk the rest.
	if not _only.is_empty() and _saved >= _only.size():
		DirAccess.remove_absolute(PROFILE)
		quit()


func _menus() -> MenuLayer:
	return _main._menus


func _tour() -> void:
	await _frames(10)
	var profile: Profile = _main._profile
	profile.best_score = 87
	profile.leaderboard_name = "Merry"
	if not _world.is_empty():
		_main.set_world(_world)
		# The world's name shows over the room for a moment: let it go.
		await _frames(240)
	_main.show_home()
	# Two battles wait for this player's turn (BattleFlow fills it online).
	(_menus().current() as HomeScreen).set_battle_turns(2)
	await _shot("01_home")
	# The bare room behind Home (for mockups): the menus hidden for one shot.
	_menus().current().visible = false
	await _shot("00_room", 10)
	_menus().current().visible = true
	await _home_modes()
	var home := _menus().current() as HomeScreen
	home.open_settings()
	await _shot("03_settings")
	var sheet := home.settings()
	if _main._services.phone_move == null:
		_main._services.phone_move = PhoneMove.new(
			null, profile, _main._services, _main._runs, func() -> void: pass, func() -> void: pass
		)
	sheet.close_dialog()
	await _frames(2)
	home.open_settings()
	sheet = home.settings()
	sheet.show_move(true)
	await _shot("04_settings_account")
	sheet.show_move(false)
	sheet.show_about(true)
	await _shot("05_settings_about")
	sheet.show_debug(true)
	await _shot("06_settings_debug")
	sheet.close_dialog()
	_main.show_look()
	await _shot("07_style")
	_main.show_shop(ItemKind.FLYER)
	await _shot("08_customize_flyers")
	_main.show_store()
	await _shot("09_shop")
	_main.show_rooms()
	await _shot("10_rooms")
	_main.show_room(RoomCatalog.all()[3].id)
	await _shot("11_room_detail")
	_main.show_leaderboard()
	await _shot("12_board_scores", 60)
	var wins: WinsScreen = _main._battle.open_wins()
	await _frames(20)
	wins.show_board("battle", "week", _wins_board())
	await _shot("13_board_wins")
	wins.show_record(_record())
	await _shot("14_board_record")
	var list: BattleListScreen = _main._battle.open()
	await _frames(20)
	list.show_battles(_battles())
	await _shot("15_battle_list")
	_menus().show_screen(BattleScreen.new(_view({"turn": "them", "play": null})))
	await _shot("16_battle")
	_menus().show_screen(BattleScreen.new(_view()))
	await _shot("17_round_intro")
	var duel := DuelScreen.new()
	_menus().show_screen(duel)
	await _frames(2)
	duel.show_start()
	await _shot("18_duel")
	duel.show_countdown(3, RIVAL, 1, 1, 3)
	await _shot("19_duel_countdown")
	duel.show_result("me", 2, 1, RIVAL, false)
	await _shot("20_duel_result")
	var daily: DailyRunScreen = _main._daily.open()
	await _frames(10)
	daily.show_info(_daily_info())
	await _shot("21_daily_run")
	await _run_shots()
	DirAccess.remove_absolute(PROFILE)
	quit()


## Home's mode sheet open.
func _home_modes() -> void:
	var home := _menus().current() as HomeScreen
	home.open_modes()
	await _shot("02_home_modes", 15)
	home.call("_close_modes")
	await _frames(5)


## A run with the HUD, the pause screen, the revive offer, game over and a replay.
func _run_shots() -> void:
	_main.start_run()
	var run: RunController = _main._run
	var tapping := true
	# Early in the run, while the hover bot is surely alive (later it may have
	# crashed, and Paused would show Game over).
	for i in 110:
		var s := run.sim.state
		if tapping and (not s.started or (s.y > SimConfig.BIRD_START_Y and s.vy >= 0)):
			run.request_tap()
		await process_frame
		if i == 90:
			await _shot("23_hud", 0)
	_main._toggle_pause()
	await _shot("24_paused", 20)
	_main._toggle_pause()
	await _frames(int(60 * 3.5))
	# Stop tapping: the bird falls. The hover bot's score is too low for the
	# revive offer, so the offer is shown by hand over the crash.
	for i in 200:
		await process_frame
		if _main._revive.is_offering() or _main._hud.game_over.visible:
			break
	await _shot("26_game_over", 90)
	var over: Control = _main._hud.game_over
	over.visible = false
	_main._hud.revive_offer.show_offer(ReviveFlow.MIN_SCORE + 7, 1)
	await _shot("25_revive", 30)
	_main._hud.revive_offer.visible = false
	over.visible = true
	_main.show_runs()
	await _shot("22_runs")
	var records: Array[RunRecord] = _main.runs().history.latest()
	if not records.is_empty():
		_main.watch_run(records[0])
		await _shot("27_replay", 90)


func _wins_board() -> Dictionary:
	var entries := []
	var names := ["Jun", RIVAL, "Pip", "Ola", "Merry", "Sam", "Noor", "Kit"]
	for i in names.size():
		(
			entries
			. append(
				{
					"rank": i + 1,
					"name": names[i],
					"who": "p%d" % i,
					"wins": 30 - i * 3,
					"losses": 5 + i,
					"rate": 80 - i * 6,
					"is_me": names[i] == "Merry",
				}
			)
		)
	return {
		"entries": entries,
		"players": 214,
		"resets_in_s": 200000,
		"me": {"rank": 5, "wins": 18, "losses": 9, "rate": 66},
	}


func _record() -> Dictionary:
	return {
		"name": RIVAL,
		"wins": 27,
		"losses": 6,
		"draws": 1,
		"rate": 81,
		"best_streak": 9,
		"last":
		[
			{"opponent": "Merry", "result": "won", "score": "6-4", "how": "friend"},
			{"opponent": "Jun", "result": "lost", "score": "3-6", "how": "resigned"},
			{"opponent": "Pip", "result": "won", "score": "6-2", "how": "random"},
		],
	}


func _view(changes: Dictionary = {}) -> BattleView:
	var d := {
		"battle": 12,
		"status": "open",
		"first_to": 6,
		"starter": true,
		"wins_me": 2,
		"wins_them": 2,
		"turn": "me",
		"opponent": {"name": RIVAL, "flyer": "buzz", "bot": false},
		"last_move_s": 4000,
		"rounds":
		[
			{"number": 1, "winner": "me", "my_score": 31, "their_score": 20},
			{"number": 2, "winner": "them", "my_score": 12, "their_score": 40},
			{"number": 3, "winner": "me", "my_score": 55, "their_score": 54},
			{"number": 4, "winner": "them", "my_score": 9, "their_score": 22},
		],
		"play":
		{
			"round": 5,
			"role": "answer",
			"blind": false,
			"rival": {"score": 42, "taps": [], "seed": 7, "season": 0},
		},
	}
	d.merge(changes, true)
	return BattleView.parse(d)


func _battles() -> Array[BattleView]:
	var out: Array[BattleView] = []
	out.append(_view())
	out.append(_view({"battle": 13, "opponent": {"name": "Jun"}, "wins_me": 4, "wins_them": 1}))
	out.append(_view({"battle": 14, "turn": "them", "play": null, "opponent": {"name": "Pip"}}))
	(
		out
		. append(
			_view(
				{
					"battle": 15,
					"status": "finished",
					"winner": "me",
					"turn": "",
					"wins_me": 6,
					"wins_them": 3,
					"play": null,
					"opponent": {"name": "Ola", "bot": true},
				}
			)
		)
	)
	return out


func _daily_info() -> DailyRunInfo:
	return (
		DailyRunInfo
		. parse(
			{
				"day": "2026-11-17",
				"number": 12,
				"season": 0,
				"resets_in_s": 15120,
				"tries_max": 3,
				"tries_used": 1,
				"best": 64,
				"rank": 14,
				"players": 1210,
			}
		)
	)
