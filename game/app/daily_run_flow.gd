class_name DailyRunFlow
extends RefCounted
## Daily Run from the app's side (DailyRunRules): the Daily Run screen, a try
## from the server's seed and season, its game over (place, tries left, Share)
## and the next try. Main asks `playing` whether the run in play is a try:
## then it plays `playing.seed_value` in `playing.season`, offers no revive and
## hands the finished run here instead of to the Today board.
## A try counts once the server started it, even when it is left early.

## Shown after Share copied the text.
const COPIED := "Copied. Paste it anywhere to share."
const CANT_WATCH := "That run can't be watched right now."

## Today's Daily Run as last loaded (null: not asked yet).
var info: DailyRunInfo
## The try in play or just finished (null: the run is not a Daily Run).
var playing: DailyTry

var _leaderboard: LeaderboardService
var _menus: MenuLayer
var _hud: Hud
var _popups: HomePopups
## start(daily_try): starts the run of a try.
var _start: Callable
var _home: Callable
## show_board(): Leaderboards on the Daily Run tab.
var _board: Callable
## replay(run, back): plays a leaderboard run back; its Back calls `back`.
var _replay: Callable
## When `info` arrived (ticks ms), so the countdown stays right.
var _info_at_ms := 0
## A run asked for to watch (0: none).
var _watching := 0
## The last finished try, for Share.
var _score := 0
var _cleared := 0
var _rank := 0
var _players := 0
## A try was asked for and not answered yet (one at a time).
var _starting := false


func _init(
	leaderboard: LeaderboardService,
	menus: MenuLayer,
	hud: Hud,
	popups: HomePopups,
	start: Callable,
	home: Callable,
	board: Callable,
	replay: Callable
) -> void:
	_leaderboard = leaderboard
	_menus = menus
	_hud = hud
	_popups = popups
	_start = start
	_home = home
	_board = board
	_replay = replay
	leaderboard.daily_loaded.connect(_on_loaded)
	leaderboard.daily_try_started.connect(_on_try)
	leaderboard.board_loaded.connect(_on_board)
	leaderboard.run_loaded.connect(_on_run)
	popups.watch_requested.connect(watch)


## The Daily Run screen, filled from the last info until a fresh one arrives.
func open() -> DailyRunScreen:
	var screen := DailyRunScreen.new(info)
	screen.closed.connect(func() -> void: _home.call())
	screen.play_pressed.connect(start_try)
	screen.board_pressed.connect(func() -> void: _board.call())
	screen.watch_requested.connect(watch)
	screen.refresh_requested.connect(refresh)
	_menus.show_screen(screen)
	refresh()
	return screen


func refresh() -> void:
	_leaderboard.request_daily()


## Asks the server for the next try; the run starts when it answers.
func start_try() -> void:
	if _starting:
		return
	_starting = true
	_leaderboard.start_daily_try()


## Game over's main action: the next try, or the Daily Run screen after the last.
func again() -> void:
	if playing != null and DailyRunRules.tries_left(playing.n, playing.tries_max) > 0:
		start_try()
	else:
		open()


## The board Ranks opens on: the Daily Run after a try, else Today.
func board_id() -> String:
	return LeaderboardService.DAILY_RUN if playing != null else LeaderboardService.DAILY


func _on_try(daily_try: DailyTry) -> void:
	_starting = false
	if daily_try.ok():
		_start.call(daily_try)
		return
	# No try left (another phone used it) or offline: the screen says which.
	open()


func _on_loaded(loaded: DailyRunInfo) -> void:
	info = loaded
	_info_at_ms = Time.get_ticks_msec()
	var screen := _menus.current() as DailyRunScreen
	if screen != null:
		screen.show_info(loaded)
	_popups.on_daily(loaded)


## A try ended: send it, and turn Game over into the try's. Nothing for a run
## that is not a try.
func finished(replay: Replay, cleared: int) -> void:
	if playing == null:
		return
	_leaderboard.submit_daily_run(playing, replay.score, replay.to_dict())
	_score = replay.score
	_cleared = cleared
	_rank = 0
	if info != null and info.is_online():
		info.tries_used = maxi(info.tries_used, playing.n)
		info.best = maxi(info.best, replay.score)
	var next := DailyRunRules.next_try_label(playing.n, playing.tries_max)
	_hud.game_over.show_daily(
		playing.number, tries_line(), next if not next.is_empty() else "Board"
	)
	_leaderboard.request_board(LeaderboardService.DAILY_RUN)


## "1 try left · new map in 4h 12m".
func tries_line() -> String:
	if playing == null:
		return ""
	var line := DailyRunRules.tries_text(playing.n, playing.tries_max)
	var left := resets_in_s()
	if left >= 0:
		line += " · new map in %s" % LeaderboardScreen.duration(left)
	return line


## Seconds to the reset now, from the last info (-1: unknown).
func resets_in_s() -> int:
	if info == null or not info.is_online() or info.resets_in_s < 0:
		return -1
	@warning_ignore("integer_division")
	return maxi(info.resets_in_s - (Time.get_ticks_msec() - _info_at_ms) / 1000, 0)


func _on_board(board: LeaderboardBoard) -> void:
	if board.id != LeaderboardService.DAILY_RUN or playing == null:
		return
	_rank = board.me.rank if board.me != null else 0
	_players = board.players
	_hud.game_over.set_daily_run_rank(_rank)


## Game over's Share: the short result text, on the clipboard.
func share() -> String:
	if playing == null:
		return ""
	var text := DailyRunRules.share_text(
		playing.number, _score, _rank, _players, playing.n, playing.tries_max, _cleared
	)
	DisplayServer.clipboard_set(text)
	_hud.show_toast(COPIED)
	return text


## Plays a run of yesterday's Daily Run; its Back returns to the Daily Run.
func watch(run_id: int) -> void:
	if run_id <= 0:
		return
	_watching = run_id
	_leaderboard.request_run(run_id)


func _on_run(run_id: int, run: Dictionary) -> void:
	if run_id != _watching:
		return
	_watching = 0
	if run.is_empty():
		_hud.show_toast(CANT_WATCH)
		return
	_replay.call(run, open)
