class_name BoardAlerts
extends RefCounted
## The player's place on today's board: noticing when someone pushed them past
## a prize line (a line on Home), and push alerts for it (Settings > Board
## alerts), asking for the OS permission once, when it means something: the
## first prize spot, or the first battle (your-turn alerts). The Board alerts
## switch covers battle alerts too (the server keeps one switch per phone).

var _profile: Profile
var _push: PushService
var _save: Callable
## A lost prize spot to tell the player about on Home (SpotAlert), or "".
var _notice := ""
## Settings > Board alerts as last sent to the server.
var _alerts_on := true


## `save`: writes the profile. `battles`: a loaded battle asks for permission.
func _init(
	profile: Profile, push: PushService, save: Callable, battles: BattleService = null
) -> void:
	_profile = profile
	_push = push
	_save = save
	if battles != null:
		battles.battle_loaded.connect(on_battle.unbind(1))
	_alerts_on = profile.settings.board_alerts
	# Permission given on an earlier start (or none needed, on Android): fetch
	# this start's token.
	if profile.settings.board_alerts and (profile.push_asked or push.fetches_silently()):
		push.start()


## Today's board arrived with the player at `rank` (0: not on it). Remembers
## the place and notices a lost prize spot since the last look. Also the
## moment to send a token the server didn't take yet (no network at start).
func on_daily_board(board: LeaderboardBoard, rank: int) -> void:
	_push.retry_register()
	var now := int(Time.get_unix_time_from_system())
	if now >= _profile.daily_spot_until:
		# Yesterday's place says nothing about today's board.
		_profile.daily_spot_rank = 0
	if board.status != LeaderboardBoard.Status.OK or rank <= 0:
		return
	var notice := SpotAlert.message(_profile.daily_spot_rank, rank, board.entries)
	if not notice.is_empty():
		_notice = notice
	if rank != _profile.daily_spot_rank:
		_profile.daily_spot_rank = rank
		_profile.daily_spot_until = now + maxi(board.resets_in_s, 0)
		_save.call()
	_ask_for_push(rank)


## The waiting lost-spot line, once ("" when there is none).
func take_notice() -> String:
	var out := _notice
	_notice = ""
	return out


## Settings changed: when Board alerts flipped, tell the server; switched on
## by a player who already holds a prize spot, ask for permission now.
func on_settings_changed() -> void:
	if _profile.settings.board_alerts == _alerts_on:
		return
	_alerts_on = _profile.settings.board_alerts
	_push.set_enabled(_alerts_on)
	if _alerts_on:
		if _profile.push_asked or _push.fetches_silently():
			_push.start()
		_ask_for_push(_profile.daily_spot_rank)


## A battle loaded (made, joined or opened): the moment your-turn alerts mean
## something, so ask for permission if it never was.
func on_battle() -> void:
	_ask()


## Asks for notification permission once, at the moment it means something:
## the player holds a place that wins diamonds.
func _ask_for_push(rank: int) -> void:
	if rank < 1 or Economy.daily_prize(rank) == 0:
		return
	_ask()


func _ask() -> void:
	if _profile.push_asked or not _profile.settings.board_alerts or not _push.is_available():
		return
	_profile.push_asked = true
	_save.call()
	_push.request_permission()
