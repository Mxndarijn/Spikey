class_name BoardAlerts
extends RefCounted
## The player's place on today's board: noticing when someone pushed them past
## a prize line (a line on Home), and push alerts for it (Settings > Board
## alerts), asking for the OS permission once, when it means something.

var _profile: Profile
var _push: PushService
var _save: Callable
## A lost prize spot to tell the player about on Home (SpotAlert), or "".
var _notice := ""
## Settings > Board alerts as last sent to the server.
var _alerts_on := true


## `save`: writes the profile.
func _init(profile: Profile, push: PushService, save: Callable) -> void:
	_profile = profile
	_push = push
	_save = save
	_alerts_on = profile.settings.board_alerts
	# Permission given on an earlier start: fetch this start's token.
	if profile.settings.board_alerts and profile.push_asked:
		push.start()


## Today's board arrived with the player at `rank` (0: not on it). Remembers
## the place and notices a lost prize spot since the last look.
func on_daily_board(board: LeaderboardBoard, rank: int) -> void:
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
		_ask_for_push(_profile.daily_spot_rank)


## Asks for notification permission once, at the moment it means something:
## the player holds a place that wins diamonds.
func _ask_for_push(rank: int) -> void:
	if rank < 1 or Economy.daily_prize(rank) == 0:
		return
	if _profile.push_asked or not _profile.settings.board_alerts or not _push.is_available():
		return
	_profile.push_asked = true
	_save.call()
	_push.request_permission()
