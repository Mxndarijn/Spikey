class_name BattleFlow
extends RefCounted
## Battle from the app's side (docs/DUEL_MODE.md, section 2): the battle list,
## New battle, one battle's screen and menu, and a round's run. Main asks
## `playing` whether the run in play is a battle round: then it plays
## `playing.seed_value` in `playing.season` with no revive, this flow puts the
## rival's run beside it as a see-through bird (RivalGhost), and the finished
## run comes back here instead of going to the Today board.
## One try: a round's run counts once the server handed out its seed.


## A battle round in play (or just finished).
class Round:
	extends RefCounted
	var battle := 0
	var number := 0
	var seed_value := 0
	var season := Seasons.NONE
	var view: BattleView
	## A Duel round: its live rival, and what to do when the run ends
	## (DuelFlow); a Battle round has neither.
	var ghost: RivalGhost
	var finish: Callable


## Shown after Copy put the invite on the clipboard.
const COPIED := "Copied. Send it to your friend."
const SENT := "Sent. %s's turn."
const CHECKING := "Checking your run…"
## Seconds after a crash before the battle shows again.
const AFTER_CRASH_S := 1.2

## The round in play (null: the run is not a battle round).
var playing: Round
var service: BattleService
## show_leaderboard(): the score boards (the wins boards' Scores switch).
var scores: Callable
## Duel, which plays its rounds through this flow's run path.
var duel: DuelFlow
var _menus: MenuLayer
var _hud: Hud
var _world: Node2D
var _bird: Node
## start(round): main starts the round's run.
var _start: Callable
var _home: Callable
var _ghost: RivalGhost
var _run_in_play: RunController
var _list: Array[BattleView] = []
## Invite codes this phone made (the server never shows one again).
var _codes := {}
## The battle the next answer is about, and what to say over it.
var _showing := 0
var _notice := ""
## A run that wasn't sent yet: [battle, round, score, replay].
var _unsent: Array = []
## One request at a time for a run's start, and the battle it is for.
var _starting := false
var _starting_view: BattleView


func _init(
	p_service: BattleService,
	menus: MenuLayer,
	hud: Hud,
	world: Node2D,
	bird: Node,
	start: Callable,
	home: Callable
) -> void:
	service = p_service
	_menus = menus
	_hud = hud
	_world = world
	_bird = bird
	_start = start
	_home = home
	service.list_loaded.connect(_on_list)
	service.battle_loaded.connect(_on_battle)
	service.run_started.connect(_on_run_started)
	service.failed.connect(_on_failed)
	service.wins_loaded.connect(_on_wins)
	service.record_loaded.connect(_on_record)
	menus.screen_shown.connect(_on_screen_shown)
	var link := DuelLink.new(service.client)
	world.add_child(link)
	duel = DuelFlow.new(link, self, menus, hud, service.profile)


## Home's Battle card opens Battles (and the list's turns fill its badge); the
## score boards' Wins switch opens the wins boards.
func _on_screen_shown(screen: Control) -> void:
	if screen is HomeScreen:
		(screen as HomeScreen).battle_pressed.connect(func() -> void: open())
		(screen as HomeScreen).duel_pressed.connect(func() -> void: duel.open())
		refresh()
	elif screen is LeaderboardScreen:
		(screen as LeaderboardScreen).wins_pressed.connect(func() -> void: open_wins())


## The wins boards (Leaderboards, Wins).
func open_wins(mode: String = "battle", period: String = "week") -> WinsScreen:
	var screen := WinsScreen.new(mode, period)
	screen.closed.connect(func() -> void: _home.call())
	screen.scores_pressed.connect(
		func() -> void:
			if scores.is_valid():
				scores.call()
	)
	screen.board_requested.connect(service.request_wins)
	screen.record_requested.connect(service.request_record)
	_menus.show_screen(screen)
	return screen


func _on_wins(mode: String, period: String, board: Dictionary) -> void:
	var screen := _menus.current() as WinsScreen
	if screen != null:
		screen.show_board(mode, period, board)


func _on_record(record: Dictionary) -> void:
	var screen := _menus.current() as WinsScreen
	if screen != null:
		screen.show_record(record)


## How many battles wait for this player (Home's Battle card badge).
func turns_waiting() -> int:
	return BattleListScreen.turns_waiting(_list)


## Battles: the list, filled when the server answers.
func open() -> BattleListScreen:
	_showing = 0
	var screen := BattleListScreen.new()
	screen.closed.connect(func() -> void: _home.call())
	screen.battle_picked.connect(open_battle)
	screen.new_pressed.connect(open_new)
	screen.refresh_requested.connect(service.request_list)
	_menus.show_screen(screen)
	if not _list.is_empty():
		screen.show_battles(_list)
	_send_unsent()
	service.request_list()
	return screen


func refresh() -> void:
	service.request_list()


## New battle over the list.
func open_new() -> NewBattleSheet:
	var open_count := _list.filter(func(b: BattleView) -> bool: return not b.is_over()).size()
	var sheet := NewBattleSheet.new(open_count)
	var host := _menus.current()
	var close := func() -> void: sheet.queue_free()
	sheet.closed.connect(close)
	sheet.invite_pressed.connect(
		func() -> void:
			close.call()
			_showing = -1
			service.create("invite")
	)
	sheet.random_pressed.connect(
		func() -> void:
			close.call()
			_showing = -1
			service.create("random")
	)
	sheet.join_pressed.connect(
		func(code: String) -> void:
			close.call()
			_showing = -1
			service.join(code)
	)
	if host != null:
		host.add_child(sheet)
	return sheet


## One battle's screen; the server's answer fills it.
func open_battle(battle: int) -> BattleScreen:
	_showing = battle
	var known: Array = _list.filter(func(b: BattleView) -> bool: return b.id == battle)
	var view: BattleView = known[0] if not known.is_empty() else BattleView.new()
	view.id = battle
	var screen := _battle_screen(view)
	service.request_battle(battle)
	return screen


func _battle_screen(view: BattleView) -> BattleScreen:
	var screen := BattleScreen.new(view, str(_codes.get(view.id, "")))
	screen.closed.connect(func() -> void: open())
	screen.play_pressed.connect(func(n: int) -> void: start_round(screen.view, n))
	screen.menu_pressed.connect(func() -> void: open_menu(screen))
	screen.nudge_pressed.connect(func() -> void: service.nudge(screen.view.id))
	screen.rematch_pressed.connect(
		func() -> void:
			_showing = -1
			service.rematch(screen.view.id)
	)
	screen.copy_pressed.connect(
		func(text: String) -> void:
			DisplayServer.clipboard_set(text)
			_hud.show_toast(COPIED)
	)
	screen.refresh_requested.connect(func() -> void: service.request_battle(screen.view.id))
	_menus.show_screen(screen)
	if not _notice.is_empty():
		screen.set_notice(_notice)
		if _notice == CHECKING:
			_check_again(view.id)
		_notice = ""
	return screen


## The checker takes a moment: ask once more a little later.
func _check_again(battle: int) -> void:
	var tree := _world.get_tree() if _world != null and _world.is_inside_tree() else null
	if tree == null:
		return
	await tree.create_timer(3.0).timeout
	var screen := _menus.current() as BattleScreen
	if screen != null and screen.view.id == battle:
		service.request_battle(battle)


## The battle's menu over its screen (K2).
func open_menu(screen: BattleScreen) -> BattleMenuSheet:
	var sheet := BattleMenuSheet.new(screen.view)
	var close := func() -> void: sheet.queue_free()
	sheet.closed.connect(close)
	sheet.nudge_pressed.connect(
		func() -> void:
			close.call()
			service.nudge(screen.view.id)
	)
	sheet.close_pressed.connect(
		func() -> void:
			close.call()
			service.close(screen.view.id)
	)
	sheet.resign_pressed.connect(
		func() -> void:
			close.call()
			service.resign(screen.view.id)
	)
	screen.add_child(sheet)
	return sheet


## Asks the server for the round's seed; the run starts when it answers.
func start_round(view: BattleView, number: int) -> void:
	if _starting or not view.my_turn() or number != view.play_round:
		return
	if view.play_role == "answer" and view.rival_pending:
		return
	_starting = true
	_starting_view = view
	_showing = view.id
	service.start_run(view.id, number)


func _on_run_started(start: Dictionary) -> void:
	_starting = false
	var r := Round.new()
	r.battle = int(start.get("battle", 0))
	r.number = int(start.get("round", 0))
	r.seed_value = int(start.get("seed", 0))
	r.season = int(start.get("season", Seasons.NONE))
	var known := _starting_view
	r.view = known if known != null and known.id == r.battle else _view_of(r.battle)
	_start.call(r)


func _view_of(battle: int) -> BattleView:
	var screen := _menus.current() as BattleScreen
	if screen != null and screen.view.id == battle:
		return screen.view
	for b in _list:
		if b.id == battle:
			return b
	var v := BattleView.new()
	v.id = battle
	return v


## The round's run is set up (main's _new_run): the rival's bird joins it when
## the rival played this round first and it isn't blind.
func on_new_run(run: RunController) -> void:
	_drop_ghost()
	_run_in_play = run if playing != null else null
	if playing != null and playing.ghost != null:
		_attach(playing.ghost, run)
		return
	if playing == null or playing.view == null or playing.view.rival.is_empty():
		return
	if playing.view.play_round != playing.number or playing.view.play_role != "answer":
		return
	var rival := playing.view.rival
	var loadout: Dictionary = rival.get("loadout", {}) if rival.get("loadout") is Dictionary else {}
	var character := Catalog.flyer(str(loadout.get("flyer", playing.view.rival_flyer)))
	if character == null:
		character = Catalog.flyers()[0]
	_attach(RivalGhost.new(rival, character, playing.view.rival_name), run)


func _attach(ghost_bird: RivalGhost, run: RunController) -> void:
	_ghost = ghost_bird
	_ghost.name = "RivalGhost"
	_world.add_child(_ghost)
	# Under your own bird.
	if _bird != null and _bird.get_parent() == _world:
		_world.move_child(_ghost, _bird.get_index())
	_ghost.follow(run)


## A Duel round's run (DuelFlow): started like a Battle round.
func start_external(r: Round) -> void:
	_start.call(r)


## The run in play now (a round's), for DuelFlow's ticks.
func run_in_play() -> RunController:
	return _run_in_play


## A Duel round is over: no round in play any more.
func end_external() -> void:
	if playing != null and playing.finish.is_valid():
		playing = null
		_drop_ghost()


func home() -> void:
	_home.call()


func ghost() -> RivalGhost:
	return _ghost


func _drop_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


## A round's run ended: send it, then show the battle again.
func finished(replay: Replay) -> void:
	if playing == null:
		return
	if playing.finish.is_valid():
		playing.finish.call(replay)
		return
	var r := playing
	_unsent = [r.battle, r.number, replay.score, replay.to_dict()]
	_showing = r.battle
	_notice = CHECKING
	_send_unsent()
	var tree := _world.get_tree() if _world != null and _world.is_inside_tree() else null
	if tree != null:
		await tree.create_timer(AFTER_CRASH_S).timeout
	_leave_run(r.battle)


func _leave_run(battle: int) -> void:
	playing = null
	_drop_ghost()
	open_battle(battle)


## The battle's screen at once (Game over's corner while a round ended).
func back_to_battle() -> void:
	if playing != null and not playing.finish.is_valid():
		_leave_run(playing.battle)


func _send_unsent() -> void:
	if _unsent.is_empty():
		return
	var u := _unsent
	service.submit(int(u[0]), int(u[1]), int(u[2]), u[3] as Dictionary)


func _on_list(battles: Array[BattleView]) -> void:
	_list = battles
	var screen := _menus.current() as BattleListScreen
	if screen != null:
		screen.show_battles(battles)
	var home := _menus.current() as HomeScreen
	if home != null and home.modes() != null:
		var n := turns_waiting()
		home.modes().set_line(
			GameModes.BATTLE, GameModes.rule_line(GameModes.BATTLE), str(n) if n > 0 else ""
		)


func _on_battle(view: BattleView) -> void:
	if not view.code.is_empty():
		_codes[view.id] = view.code
	if not _unsent.is_empty() and int(_unsent[0]) == view.id:
		_notice = round_notice(view, int(_unsent[1]))
		_unsent = []
	if view.lost:
		_notice = "Your last run of this round was lost: it counts as 0."
	elif view.redealt:
		_notice = "A game update needed a new map for this round."
	for i in _list.size():
		if _list[i].id == view.id:
			_list[i] = view
	var screen := _menus.current() as BattleScreen
	if screen != null and (screen.view.id == view.id or _showing == -1):
		if _showing == -1:
			_showing = view.id
			_battle_screen(view)
			return
		screen.code = str(_codes.get(view.id, screen.code))
		screen.show_view(view)
		if not _notice.is_empty():
			screen.set_notice(_notice)
			_notice = ""
	elif _showing == -1 and playing == null:
		_showing = view.id
		_battle_screen(view)


## What the battle says after a round's run was sent.
static func round_notice(view: BattleView, number: int) -> String:
	for r: Dictionary in view.rounds:
		if int(r.get("number", 0)) != number:
			continue
		var mine: Variant = r.get("my_score")
		var theirs: Variant = r.get("their_score")
		match r.get("winner"):
			"me":
				return "You win round %d · %s–%s" % [number, str(mine), str(theirs)]
			"them":
				return (
					"%s wins round %d · %s–%s"
					% [view.rival_label(), number, str(mine), str(theirs)]
				)
			"draw":
				return "Round %d is a draw" % number
	if view.turn == "them":
		return SENT % view.rival_label()
	return CHECKING


func _on_failed(op: String, message: String) -> void:
	_starting = false
	var screen := _menus.current() as BattleListScreen
	if screen != null and op == "battle_list":
		screen.show_offline(message)
		return
	if op == "battle_submit":
		# The run is kept and sent again when Battles opens.
		_notice = "Your run wasn't sent yet. It goes when you're online."
	_hud.show_toast(message)
