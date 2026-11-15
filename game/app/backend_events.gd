class_name BackendEvents
extends RefCounted
## What the app does when the backend itself has news: the one-time fresh
## start when the config names a new server (BackendReset), "please update"
## when the server is newer than this app (BackendClient.update_required) and
## "moved to another phone" after a transfer code was used elsewhere
## (BackendClient.account_moved). Each shows a NoticePopup on Home.

## The fresh start cleared a save that had progress (Home says why).
var fresh := false

var _profile: Profile
var _runs: RunStore
var _popups: HomePopups
## The first start (free flyer and world) and Home, for a new player here.
var _first_start: Callable
var _home: Callable
var _profile_path := ""


## Runs the one-time fresh start, before anything signs in or reads the
## runs file.
func _init(profile: Profile, config_path: String, profile_path: String, runs_path: String) -> void:
	_profile = profile
	_profile_path = profile_path
	fresh = fresh_start(profile, config_path, profile_path, runs_path)


## Listens to the backend the leaderboards use (none for sample boards), and
## shows the fresh start's notice.
## On our own server it also sets up Move to a new phone (services.phone_move).
func watch(
	runs: RunStore, popups: HomePopups, services: AppServices, first_start: Callable, home: Callable
) -> void:
	_runs = runs
	_popups = popups
	_first_start = first_start
	_home = home
	if fresh:
		popups.notice(NoticePopup.FRESH_START)
	var api := AppServices.backend_of(services.leaderboard)
	if api == null:
		return
	api.update_required.connect(popups.notice.bind(NoticePopup.UPDATE))
	api.account_moved.connect(on_account_moved)
	if api is FlapjawClient:
		var save := func() -> void: _profile.save(_profile_path)
		services.phone_move = PhoneMove.new(api, _profile, services, runs, save, first_start)
		services.phone_move.moved.connect(home)


## The one-time fresh start. True when the save held progress the player will
## miss.
static func fresh_start(
	profile: Profile, config_path: String, profile_path: String, runs_path: String
) -> bool:
	var config := AppServices.config_at(config_path)
	if not BackendReset.needed(profile, config):
		return false
	var had := BackendReset.had_progress(profile)
	BackendReset.apply(profile, str(config.server_id), profile_path, runs_path)
	return had


## This player now lives on another phone: start over here as a new player.
func on_account_moved() -> void:
	BackendReset.clear(_profile, _profile.backend_server)
	_runs.clear()
	_first_start.call()
	_popups.notice(NoticePopup.MOVED)
	if _popups.home_open():
		_home.call()
