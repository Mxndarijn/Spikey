extends Node2D
## The app: the live room and flyer always run in the background; menus
## (home, shop) sit on top, and Play starts a run.
## Flow: Home -> Play. A first start goes straight to Home with the first free
## flyer and the default world; players change them in Customize.
## Home -> Rooms -> a room -> Practice repeats that room; practice never touches
## coins, best score, cleared rooms or leaderboards.
## Home -> the Best / Rank sticker -> Leaderboards (sample boards until the
## leaderboard server exists, Phase 3).

enum Mode { MENU, RUN, PRACTICE }

const RESTART_DELAY_MS := 450

## Where the save lives; tests point this somewhere else.
var profile_path := Profile.PATH
var mode := Mode.MENU
## Seasonal rooms in play (Seasons.*), from today's date; tests can set it.
var season := SeasonCalendar.today()
## The leaderboards; tests can swap in their own before _ready.
var leaderboard: LeaderboardService

var _profile: Profile
var _game_over_at_ms := -1
var _theme: ThemeDef
var _character: CharacterDef
var _trail_style: TrailStyle
var _menus := MenuLayer.new()
var _audio := AudioDirector.new()
## Practice: the room id being repeated. Real runs: the room being played, so
## the next room change can count it as cleared.
var _practice_id := ""
var _room_id := ""

@onready var _run: RunController = $RunController
@onready var _room: RoomView = $RoomView
@onready var _trail: TrailView = $TrailView
@onready var _bird: BirdView = $BirdView
@onready var _coin: CoinView = $CoinView
@onready var _hazards: HazardLayer = $HazardLayer
@onready var _hud: Hud = $Hud


func _ready() -> void:
	add_child(_menus)
	add_child(_audio)
	_profile = Profile.load_or_new(profile_path)
	if leaderboard == null:
		leaderboard = SampleLeaderboard.new(_profile)
	leaderboard.board_loaded.connect(_on_board_loaded)
	_load_equipped()
	_audio.bind(_run)
	_run.run_started.connect(_hud.show_running)
	_run.run_started.connect(_trail.start)
	_run.flapped.connect(_bird.on_flap)
	_run.flapped.connect(_trail.on_flap)
	_run.bounced.connect(_bird.on_bounce)
	_run.room_changed.connect(_room.on_room_changed)
	_run.died.connect(_on_died)
	_run.coin_spawned.connect(_coin.on_spawned)
	_run.coin_collected.connect(_coin.on_collected)
	_run.coin_collected.connect(_on_coin_collected)
	_hud.pause_pressed.connect(_toggle_pause)
	_hud.play_again_pressed.connect(_try_restart)
	_hud.home_pressed.connect(show_home)
	_hud.restart_pressed.connect(_restart_practice)
	_hud.rooms_pressed.connect(show_rooms)
	_run.run_started.connect(_on_run_started)
	_run.room_changed.connect(_on_room_changed)
	_new_run()
	if not _profile.onboarded:
		_first_start()
	show_home()


## Starts a run from the menus (Play).
func start_run() -> void:
	mode = Mode.RUN
	_menus.clear()
	_show_flyer(true)
	_new_run()
	_audio.best_score = _profile.best_score
	_hud.show_ready()


func show_home() -> void:
	mode = Mode.MENU
	_audio.menu()
	_new_run()
	_hud.show_menu()
	_show_flyer(true)
	var home := HomeScreen.new(_profile, leaderboard.cached_rank(LeaderboardService.DAILY))
	home.play_pressed.connect(start_run)
	home.leaderboard_pressed.connect(show_leaderboard)
	# The loadout card and the Shop button both open Customize.
	home.customize_pressed.connect(show_shop.bind(Catalog.FLYER))
	home.shop_pressed.connect(show_shop)
	home.rooms_pressed.connect(show_rooms)
	home.settings_changed.connect(
		func() -> void:
			_profile.save(profile_path)
			apply_audio_settings()
	)
	_menus.show_screen(home)
	leaderboard.request_board(LeaderboardService.DAILY)


## The leaderboards: daily, tier, all-time and friends.
func show_leaderboard(board_id: String = LeaderboardService.DAILY) -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var screen := LeaderboardScreen.new(_profile, leaderboard, board_id)
	screen.closed.connect(show_home)
	screen.play_pressed.connect(start_run)
	screen.name_changed.connect(_on_leaderboard_name)
	_menus.show_screen(screen)


func _on_leaderboard_name(_name: String) -> void:
	_profile.save(profile_path)


## Today's rank reached home: show it on the Leaderboard button.
func _on_board_loaded(board: LeaderboardBoard) -> void:
	var home := _menus.current() as HomeScreen
	if home != null and board.id == LeaderboardService.DAILY:
		home.set_daily_rank(board.me.rank if board.me != null else 0)


## Every room kind, for practice.
func show_rooms() -> void:
	mode = Mode.MENU
	_practice_id = ""
	_new_run()
	_hud.show_menu()
	_show_flyer(false)
	var rooms := RoomsScreen.new(_profile)
	rooms.closed.connect(show_home)
	rooms.room_opened.connect(show_room)
	_menus.show_screen(rooms)


func show_room(id: String) -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var detail := RoomDetailScreen.new(_profile, id)
	detail.closed.connect(show_rooms)
	detail.practice_pressed.connect(start_practice)
	_menus.show_screen(detail)


## A practice run that repeats one room. Open rooms only (met in a real run).
func start_practice(id: String) -> void:
	var def := RoomCatalog.find(id)
	if def == null or not RoomInfo.is_open(_profile, def):
		return
	mode = Mode.PRACTICE
	_practice_id = id
	_menus.clear()
	_show_flyer(true)
	_hud.set_practice(RoomInfo.name_of(id))
	_new_run()
	_hud.show_ready()


func _restart_practice() -> void:
	if mode == Mode.PRACTICE:
		_set_paused(false)
		_new_run()
		_hud.show_ready()


## Customize (the shop and the loadout in one screen) on a tab and filter.
func show_shop(tab: String = Catalog.FLYER) -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var shop := CollectionScreen.new(_profile, CollectionScreen.Mode.SHOP, tab)
	shop.closed.connect(show_home)
	shop.equipped.connect(_on_equipped)
	shop.previewed.connect(_preview)
	_menus.show_screen(shop)


## Switches world right away; cosmetic only, so it is safe mid-run.
func set_world(id: String) -> void:
	var t := Catalog.world(id)
	if t != null:
		_apply_world(t)
		_hud.show_toast(t.display_name)


## First start: no pickers. The player gets the first free flyer and the
## default world, already in use, and goes straight to Home.
func _first_start() -> void:
	var flyer := Shop.starters(Catalog.FLYER)[0]
	_profile.grant(Catalog.FLYER, flyer)
	_profile.equip(Catalog.FLYER, flyer)
	_profile.grant(Catalog.WORLD, ThemeCatalog.DEFAULT_ID)
	_profile.equip(Catalog.WORLD, ThemeCatalog.DEFAULT_ID)
	_profile.onboarded = true
	_profile.save(profile_path)
	_load_equipped()


## Shows a world in the room behind the shop or picker without saving it.
## The equipped world comes back with the next screen or run.
func _preview(kind: String, id: String) -> void:
	if kind != Catalog.WORLD:
		return
	var t := Catalog.world(id)
	if t != null:
		_room.set_theme(t)
		_hazards.set_theme(t)


## The shop and pickers show the flyer big themselves, so the live one hides.
func _show_flyer(value: bool) -> void:
	_bird.visible = value
	_trail.visible = value


func _on_equipped(_kind: String, _id: String) -> void:
	_profile.save(profile_path)
	_load_equipped()


## Applies the player's flyer, world and trail, with safe defaults.
func _load_equipped() -> void:
	_character = Catalog.flyer(_profile.equipped_id(Catalog.FLYER))
	if _character == null:
		_character = Catalog.flyers()[0]
	_trail_style = Catalog.trail(_profile.equipped_id(Catalog.TRAIL))
	if _trail_style == null:
		_trail_style = TrailStyle.world_ribbon()
	var world := Catalog.world(_profile.equipped_id(Catalog.WORLD))
	_apply_world(world if world != null else ThemeCatalog.default_theme())
	if is_node_ready():
		_bird.set_character(_character)
		_room.portal_style = PortalStyle.equipped(_profile)
		apply_audio_settings()


## Sound settings and the chosen music, from the save. Customize and the
## settings panel call this after changing them.
func apply_audio_settings() -> void:
	var p := _profile
	_audio.set_volumes(p.music_volume, p.sfx_volume, p.music_on, p.sfx_on)
	# Music is a Customize kind ("music"): a track id, Match my world (the
	# default) or Shuffle owned.
	var pick := p.equipped_id(Catalog.MUSIC)
	var owned := PackedStringArray(p.owned.get(Catalog.MUSIC, []))
	_audio.choose_track(pick if not pick.is_empty() else MusicTrack.MATCH_WORLD, _theme.id, owned)


func _apply_world(t: ThemeDef) -> void:
	_theme = t
	if is_node_ready():
		_room.set_theme(t)
		_hazards.set_theme(t)
		_trail.set_style(_trail_style, t)


func _new_run() -> void:
	# Local seed for now; Phase 3 asks the server for a one-time seed.
	var practice := RoomCatalog.index_of(_practice_id) if mode == Mode.PRACTICE else -1
	var run_season := season
	# Practising a seasonal room plays it in its own season, whatever today is.
	if practice >= 0 and RoomCatalog.all()[practice].season != Seasons.NONE:
		run_season = RoomCatalog.all()[practice].season
	_run.new_run(randi(), run_season, practice)
	_room_id = RoomCatalog.all()[_run.sim.state.room_kind].id
	_room.bind(_run, _theme)
	_hazards.bind(_run, _theme)
	_bird.bind(_run, _character)
	_coin.bind(_run)
	_hud.set_run_coins(0)
	_trail.bind(_bird, _trail_style, _theme)
	_room.show_score = _in_play()
	_game_over_at_ms = -1


func _in_play() -> bool:
	return mode == Mode.RUN or mode == Mode.PRACTICE


func _try_restart() -> void:
	if mode == Mode.PRACTICE:
		_restart_practice()
		return
	if mode == Mode.RUN and Time.get_ticks_msec() - _game_over_at_ms >= RESTART_DELAY_MS:
		_new_run()
		_hud.show_ready()


func _unhandled_input(event: InputEvent) -> void:
	if not _in_play():
		return
	if event.is_action_pressed("ui_cancel") or _is_key(event, KEY_P):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not _is_tap(event):
		return
	get_viewport().set_input_as_handled()
	if _run.paused:
		_set_paused(false)
	elif _run.sim.is_over():
		_try_restart()
	else:
		_run.request_tap()


## Lets go of the shared caches so Godot can free them when the game closes
## (otherwise it reports leaked resources on exit).
func _exit_tree() -> void:
	UiTheme.release()
	GameFonts.release()
	Catalog.release()
	RoomView.release()
	HazardLayer.release()
	RoomCatalog.release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _run != null and _run.is_running():
			_set_paused(true)


func _toggle_pause() -> void:
	if _run.is_running() or _run.paused:
		_set_paused(not _run.paused)


func _set_paused(value: bool) -> void:
	_run.set_paused(value)
	_hud.show_paused(value)
	_room.show_score = not value


## The coin flies from where it was in the room into the counter.
func _on_coin_collected(total: int) -> void:
	var s := _run.sim.state
	_hud.fly_coin(Vector2(s.pickup_x, s.pickup_y) / float(SimConfig.SUB), total)


## A real run met its first room.
func _on_run_started() -> void:
	if mode == Mode.RUN:
		_profile.record_room_met(_room_id)


## A real run survived all of a room's points: count it, and meet the next.
func _on_room_changed(_room_index: int) -> void:
	if mode != Mode.RUN or _run.sim == null:
		return
	_profile.record_room_cleared(_room_id)
	_room_id = RoomCatalog.all()[_run.sim.state.room_kind].id
	_profile.record_room_met(_room_id)


func _on_died(replay: Replay) -> void:
	_bird.on_death()
	_room.show_score = false
	_trail.stop()
	if mode == Mode.PRACTICE:
		_hud.show_practice_over(RoomView.practice_points(_run.sim))
		return
	var previous_best := _profile.best_score
	var is_new_best := replay.score > previous_best
	var earned := _profile.record_run(replay.score, replay.coins)
	# Phase 3 sends the replay (seed + taps) for the server to verify.
	leaderboard.submit_run(replay.score)
	_profile.save(profile_path)
	_game_over_at_ms = Time.get_ticks_msec()
	_hud.show_game_over(replay.score, _profile.best_score, is_new_best, earned, previous_best)


static func _is_tap(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return _is_key(event, KEY_SPACE)


static func _is_key(event: InputEvent, key: Key) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo and k.keycode == key
	return false
