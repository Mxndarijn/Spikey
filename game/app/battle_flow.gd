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
## Asking again while a sent run is checked: how often, how many times.
const CHECK_EVERY_S := 3.0
const CHECK_TRIES := 5
## Seconds after a crash before the battle shows again.
const AFTER_CRASH_S := 1.2

## The round in play (null: the run is not a battle round).
var playing: Round
var service: BattleService
## show_leaderboard(): the score boards (the wins boards' Scores switch).
var scores: Callable
## Main leaves play for the menus (a round's run handed over to a screen).
var to_menus: Callable
## Duel, which plays its rounds through this flow's run path.
var duel: DuelFlow
## What the phone opened the game with (a tapped push, a link).
var intents: AppIntents
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
## The round of the last run sent, until it is decided: [battle, round]; the
## battle's answers say how it goes (Checking, Sent, then who won).
var _checking: Array = []
## The server still checks that run.
var _check_pending := false
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
	service.version_known.connect(GameModes.set_server_version)
	menus.screen_shown.connect(_on_screen_shown)
	var link := DuelLink.new(service.client)
	world.add_child(link)
	intents = AppIntents.new()
	world.add_child(intents)
	intents.push_opened.connect(open_push)
	intents.link_opened.connect(open_link)
	duel = DuelFlow.new(link, self, menus, hud, service.profile)


## Home's Battle tab opens Battles (and the list's turns fill its badge, the
## last list's at once); the score boards' Wins switch opens the wins boards.
func _on_screen_shown(screen: Control) -> void:
	if screen is HomeScreen:
		var home := screen as HomeScreen
		home.battle_pressed.connect(func() -> void: open())
		home.duel_pressed.connect(func() -> void: duel.open())
		home.update_pressed.connect(StoreLink.open)
		# The battle list is only for Home's battles pill: not while Battle is
		# paused. The server's version still matters to Duel.
		if GameModes.battle_enabled:
			home.set_battle_turns(turns_waiting())
			refresh()
		service.request_server_version()
	elif screen is LeaderboardScreen:
		(screen as LeaderboardScreen).wins_pressed.connect(func() -> void: open_wins())


## A tapped battle push opens its battle (a Duel push the Duel screen). Not
## in the middle of a round: that round's run goes on.
func open_push(data: Dictionary) -> void:
	if playing != null:
		return
	match str(data.get("kind", "")):
		"battle_alert":
			var id := str(data.get("battle", "")).to_int()
			if not GameModes.battle_enabled:
				home()
			elif id > 0:
				open_battle(id)
			else:
				open()
		"duel_alert":
			duel.open()


## An invite on the clipboard, and a toast to say so (also Share off a phone).
func copy_invite(text: String) -> void:
	DisplayServer.clipboard_set(text)
	_hud.show_toast(COPIED)


## An invite link (https://flapjaw.mn-platform.tech/battle/CODE or /duel/CODE)
## joins that battle or Duel. Not in the middle of a round.
func open_link(url: String) -> void:
	if playing != null:
		return
	var parts := url.split("?")[0].split("#")[0].split("/", false)
	if parts.size() < 2:
		return
	var code := parts[parts.size() - 1].to_upper()
	match parts[parts.size() - 2]:
		"battle":
			if not GameModes.battle_enabled:
				home()
				return
			_showing = -1
			open()
			service.join(code)
		"duel":
			duel.open_joining(code)


## The wins boards (Leaderboards, Wins).
func open_wins(mode: String = "", period: String = "week") -> WinsScreen:
	if mode.is_empty():
		mode = "battle" if GameModes.battle_enabled else "duel"
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


## How many battles wait for this player (Home's Battle tab badge).
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
	if GameModes.needs_update(GameModes.BATTLE):
		screen.show_update(BattleService.UPDATE)
		return screen
	if not _list.is_empty():
		screen.show_battles(_list)
	_send_unsent()
	service.request_list()
	return screen


func refresh() -> void:
	if GameModes.battle_enabled:
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
	screen.copy_pressed.connect(copy_invite)
	screen.share_pressed.connect(
		func(text: String) -> void:
			if not ShareSheet.share(text):
				copy_invite(text)
	)
	screen.refresh_requested.connect(func() -> void: service.request_battle(screen.view.id))
	_menus.show_screen(screen)
	if not _notice.is_empty():
		screen.set_notice(_notice)
		if _notice == CHECKING:
			_check_again(view.id)
		_notice = ""
	return screen


## The checker takes a moment: ask again a little later, a few times, while
## the run is still being checked and its battle shows.
func _check_again(battle: int) -> void:
	var tree := _world.get_tree() if _world != null and _world.is_inside_tree() else null
	if tree == null:
		return
	for i in CHECK_TRIES:
		await tree.create_timer(CHECK_EVERY_S).timeout
		if not alive():
			return
		var screen := _menus.current() as BattleScreen
		if screen == null or screen.view.id != battle:
			return
		if i > 0 and not _check_pending:
			return
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
	_checking = []
	_check_pending = false
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
		_menus_now()


## The app is still there (a timer may end after the game closed, or after a
## test freed it).
func alive() -> bool:
	return is_instance_valid(_menus) and is_instance_valid(_world)


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
	# Again or Home may have left the round already.
	if not alive() or playing != r:
		return
	_leave_run(r.battle)


func _leave_run(battle: int) -> void:
	playing = null
	_drop_ghost()
	_menus_now()
	open_battle(battle)


func _menus_now() -> void:
	if to_menus.is_valid():
		to_menus.call()


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
	if home != null:
		home.set_battle_turns(turns_waiting())


func _on_battle(view: BattleView) -> void:
	if not view.code.is_empty():
		_codes[view.id] = view.code
	if not _unsent.is_empty() and int(_unsent[0]) == view.id:
		_checking = [view.id, int(_unsent[1])]
		_unsent = []
	if not _checking.is_empty() and int(_checking[0]) == view.id:
		_notice = round_notice(view, int(_checking[1]))
		_check_pending = _notice == CHECKING
		if _notice != CHECKING and _notice != SENT % view.rival_label():
			_checking = []
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
		var mine := _score_text(r.get("my_score"))
		var theirs := _score_text(r.get("their_score"))
		match r.get("winner"):
			"me":
				return "You win round %d · %s–%s" % [number, mine, theirs]
			"them":
				return "%s wins round %d · %s–%s" % [view.rival_label(), number, mine, theirs]
			"draw":
				return "Round %d is a draw" % number
	if view.turn == "them":
		return SENT % view.rival_label()
	return CHECKING


## A round's score: JSON numbers arrive as floats (9, not 9.0); none is "–".
static func _score_text(score: Variant) -> String:
	return str(int(score)) if score is float or score is int else "–"


func _on_failed(op: String, message: String) -> void:
	_starting = false
	var screen := _menus.current() as BattleListScreen
	if screen != null and op == "battle_list":
		if message == BattleService.UPDATE:
			screen.show_update(message)
		else:
			screen.show_offline(message)
		return
	# The wins boards say it in their own caption line, not in a toast over
	# their rows.
	var wins := _menus.current() as WinsScreen
	if wins != null and op in ["get_wins_board", "get_match_record"]:
		wins.show_offline(message)
		return
	# Home asks for the list only for the Battle tab's badge: offline, the tab
	# just shows no badge, with no toast over the wordmark.
	if op == "battle_list" and _menus.current() is HomeScreen:
		return
	if op == "battle_submit":
		# The run is kept and sent again when Battles opens.
		_notice = "Your run wasn't sent yet. It goes when you're online."
	_hud.show_toast(message)
