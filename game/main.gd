extends Node2D
## The app: the live room and flyer always run in the background; menus
## (home, shop) sit on top, and Play starts a run.
## Flow: Home -> Play. A first start goes straight to Home with the first free
## flyer and the default world; players change them in Customize.
## Home -> Rooms -> a room -> Practice repeats that room; practice never touches
## coins, best score, cleared rooms or leaderboards.
## Home -> the #rank item in the dock -> Leaderboards: the friends' Supabase
## boards when services/supabase_config.json exists, else made-up sample boards.
## Home -> Settings (the dock) -> the settings sheet; main applies each change.
## Game over has its own dock: Home, Rooms | Again | #rank, Style.
## Leaderboards -> a run -> Replay plays that run back in the live room with
## the recorded player's look; it never touches the save or the leaderboards,
## and Back returns to the leaderboards.

enum Mode { MENU, RUN, PRACTICE, REPLAY }

const RESTART_DELAY_MS := 450
## Settings > Haptics: a short buzz on flap, a longer one on a crash.
const HAPTIC_FLAP_MS := 12
const HAPTIC_CRASH_MS := 40

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
## Rooms cleared in the current real run, for the game-over stats.
var _rooms_cleared := 0
## Replay: the run being watched (parse_run output), its driver, and the board
## to go back to. `_replay_look` is on while its loadout replaces the player's.
var _replay_run := {}
var _replay_driver: ReplayDriver
var _replay_board := LeaderboardService.DAILY
var _replay_look := false

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
		leaderboard = _make_leaderboard()
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
	_hud.leaderboard_pressed.connect(show_leaderboard)
	_hud.style_pressed.connect(show_shop.bind(Catalog.FLYER))
	_hud.sound_toggled.connect(_on_sound_toggled)
	_hud.replay_again_pressed.connect(_replay_again)
	_hud.replay_back_pressed.connect(_leave_replay)
	_run.flapped.connect(_buzz.bind(HAPTIC_FLAP_MS))
	_hud.bind_run(_run)
	_run.run_started.connect(_on_run_started)
	_run.room_changed.connect(_on_room_changed)
	_new_run()
	if not _profile.onboarded:
		_first_start()
	apply_settings()
	get_viewport().size_changed.connect(fit_screen)
	fit_screen()
	show_home()


## Puts the room (world, HUD and menus) where ScreenLayout says on this phone.
func fit_screen() -> void:
	set_room_rect(ScreenLayout.current(get_viewport()))


## The world moves with Main (a Node2D); the HUD and menus are canvas layers,
## so they get the rect themselves.
func set_room_rect(rect: Rect2) -> void:
	position = rect.position
	_hud.room_rect = rect
	_menus.set_room_rect(rect)


## Starts a run from the menus (Play).
func start_run() -> void:
	_drop_replay()
	mode = Mode.RUN
	_menus.clear()
	_show_flyer(true)
	_new_run()
	_audio.best_score = _profile.best_score
	_hud.show_ready()


func show_home() -> void:
	_drop_replay()
	mode = Mode.MENU
	_audio.menu()
	_new_run()
	_hud.show_menu()
	# Home draws the flyer itself, bigger, so the live one hides.
	_show_flyer(false)
	var home := HomeScreen.new(_profile, leaderboard.cached_rank(LeaderboardService.DAILY))
	home.play_pressed.connect(start_run)
	home.leaderboard_pressed.connect(show_leaderboard)
	# The dock's Style opens Customize.
	home.customize_pressed.connect(show_shop.bind(Catalog.FLYER))
	home.shop_pressed.connect(show_shop)
	home.rooms_pressed.connect(show_rooms)
	home.settings_changed.connect(_on_settings_changed)
	_menus.show_screen(home)
	leaderboard.request_board(LeaderboardService.DAILY)


## The leaderboards: Daily and All-time.
func show_leaderboard(board_id: String = LeaderboardService.DAILY) -> void:
	_drop_replay()
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var screen := LeaderboardScreen.new(_profile, leaderboard, board_id)
	screen.closed.connect(show_home)
	screen.play_pressed.connect(start_run)
	screen.name_changed.connect(_on_leaderboard_name)
	if screen.has_signal("replay_requested"):
		screen.connect("replay_requested", _on_replay_requested.bind(screen))
	_menus.show_screen(screen)


func _on_replay_requested(run: Dictionary, screen: LeaderboardScreen) -> void:
	_replay_board = screen.board_id()
	play_replay(run)


## Plays a leaderboard run (SupabaseLeaderboard.parse_run output) back in the
## live room, with that player's flyer, world, trail, portal and music. Taps
## come only from the recording. A run from another gameplay version, or an
## empty one (it didn't load), shows a message instead.
func play_replay(run: Dictionary) -> void:
	mode = Mode.REPLAY
	_menus.clear()
	_replay_run = run
	var problem := ReplayDriver.problem(run)
	if not problem.is_empty():
		_replay_driver = null
		_show_flyer(false)
		_hud.show_menu()
		_hud.replay_hud().show_message(problem)
		return
	_replay_driver = ReplayDriver.from_run(run, season)
	_apply_loadout(run.get("loadout", {}) as Dictionary)
	var player := str(run.get("name", ""))
	var score := int(run.get("score", 0))
	_hud.replay_hud().set_run(player if not player.is_empty() else "Player", score)
	_replay_again()


## Watch again: the same run from its first tick.
func _replay_again() -> void:
	if mode != Mode.REPLAY or _replay_driver == null:
		return
	_set_paused(false)
	_show_flyer(true)
	_new_run()
	_hud.show_ready()


## Back (or the exit icon): the leaderboards, on the board the run came from.
func _leave_replay() -> void:
	show_leaderboard(_replay_board)


## The recorded player's look, for this replay only: nothing is saved or
## equipped. Ids we don't know fall back to the player's own, then the default.
func _apply_loadout(look: Dictionary) -> void:
	_replay_look = true
	var flyer := Catalog.flyer(str(look.get(Catalog.FLYER, "")))
	if flyer != null:
		_character = flyer
	var trail := Catalog.trail(str(look.get(Catalog.TRAIL, "")))
	if trail != null:
		_trail_style = trail
	var world := Catalog.world(str(look.get(Catalog.WORLD, "")))
	if world != null:
		_apply_world(world)
	_bird.set_character(_character)
	var portal := Catalog.portal(str(look.get(Catalog.PORTAL, "")))
	_room.portal_style = portal if portal != null else PortalStyle.equipped(_profile)
	var music := str(look.get(Catalog.MUSIC, ""))
	if Catalog.track(music) == null and not music in Catalog.MUSIC_PICKS:
		music = _profile.equipped_id(Catalog.MUSIC)
	if music.is_empty():
		music = MusicTrack.MATCH_WORLD
	# Shuffle picks from the watcher's own tracks: the recording doesn't say which.
	var owned := PackedStringArray(_profile.owned.get(Catalog.MUSIC, []))
	_audio.choose_track(music, _theme.id, owned)


## Leaving a replay: the player's own look comes back.
func _drop_replay() -> void:
	_replay_driver = null
	if _replay_look:
		_replay_look = false
		_load_equipped()


func _on_leaderboard_name(player_name: String) -> void:
	_profile.save(profile_path)
	leaderboard.set_player(player_name, _profile.equipped_id(Catalog.FLYER))


## Supabase when its config file is there (docs/LEADERBOARD_SETUP.md), else samples.
func _make_leaderboard() -> LeaderboardService:
	var config := SupabaseLeaderboard.load_config()
	if config.is_empty():
		return SampleLeaderboard.new(_profile)
	var online := SupabaseLeaderboard.new(_profile, self, config.url, config.anon_key)
	online.restore()
	return online


## Today's rank reached home: show it on the Leaderboard button.
func _on_board_loaded(board: LeaderboardBoard) -> void:
	var home := _menus.current() as HomeScreen
	if board.id != LeaderboardService.DAILY:
		return
	var rank := board.me.rank if board.me != null else 0
	if home != null:
		home.set_daily_rank(rank)
	# Game over shows today's rank too, once the board with this run arrives.
	_hud.set_daily_rank(rank)


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


## Paused: the Music and Sounds circles.
func _on_sound_toggled(which: String, on: bool) -> void:
	if which == "music":
		_profile.music_on = on
	else:
		_profile.sfx_on = on
	_on_settings_changed()


func _on_settings_changed() -> void:
	_profile.save(profile_path)
	apply_settings()


## Every setting from the save: sound, then Settings > Play.
func apply_settings() -> void:
	apply_audio_settings()
	var p := _profile
	# Reduced flashing: no room flash or shake.
	_room.flash_enabled = not p.reduced_flashing
	# Color-blind spikes: the room and hazard drawing read this flag when they
	# have it (world-scenes adds `color_blind_spikes` to RoomView/HazardLayer).
	for view: Node in [_room, _hazards]:
		if "color_blind_spikes" in view:
			view.set("color_blind_spikes", p.color_blind_spikes)
	UiKit.large_buttons = p.large_buttons
	_hud.reduced_motion = p.reduced_flashing
	_hud.set_large_buttons(p.large_buttons)


## A short vibration on phones, when Settings > Haptics is on.
func _buzz(ms: int) -> void:
	if _profile != null and _profile.haptics and _in_play():
		Input.vibrate_handheld(ms)


func _apply_world(t: ThemeDef) -> void:
	_theme = t
	# Night rooms get white text on the room; cards stay ink.
	_menus.set_room_theme(UiTheme.room_theme(t))
	if is_node_ready():
		_room.set_theme(t)
		_hazards.set_theme(t)
		_trail.set_style(_trail_style, t)
		_hud.set_room_theme(UiTheme.room_theme(t))


func _new_run() -> void:
	# Local seed for now; Phase 3 asks the server for a one-time seed.
	var practice := RoomCatalog.index_of(_practice_id) if mode == Mode.PRACTICE else -1
	var run_season := season
	# Practising a seasonal room plays it in its own season, whatever today is.
	if practice >= 0 and RoomCatalog.all()[practice].season != Seasons.NONE:
		run_season = RoomCatalog.all()[practice].season
	if mode == Mode.REPLAY and _replay_driver != null:
		_run.new_replay(_replay_driver)
	else:
		_run.new_run(randi(), run_season, practice)
	_room_id = RoomCatalog.all()[_run.sim.state.room_kind].id
	_room.bind(_run, _theme)
	_hazards.bind(_run, _theme)
	_bird.bind(_run, _character)
	_coin.bind(_run)
	_hud.set_run_coins(0)
	_trail.bind(_bird, _trail_style, _theme)
	# The HUD shows the score at the top now; the ghost score stays off.
	_room.show_score = false
	_rooms_cleared = 0
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
		# A replay just keeps playing; it has no pause button to resume with.
		if _run != null and _run.is_running() and mode != Mode.REPLAY:
			_set_paused(true)


func _toggle_pause() -> void:
	if _run.is_running() or _run.paused:
		_set_paused(not _run.paused)


func _set_paused(value: bool) -> void:
	_run.set_paused(value)
	_hud.show_paused(value, _profile.music_on, _profile.sfx_on)


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
	_rooms_cleared += 1
	_room_id = RoomCatalog.all()[_run.sim.state.room_kind].id
	_profile.record_room_met(_room_id)


func _on_died(replay: Replay) -> void:
	_buzz(HAPTIC_CRASH_MS)
	_bird.on_death()
	_room.show_score = false
	_trail.stop()
	if mode == Mode.PRACTICE:
		_hud.show_practice_over(RoomView.practice_points(_run.sim))
		return
	if mode == Mode.REPLAY:
		# Someone else's run: no coins, best score or leaderboard.
		_hud.replay_hud().show_over()
		return
	var previous_best := _profile.best_score
	var is_new_best := replay.score > previous_best
	var earned := _profile.record_run(replay.score, replay.coins)
	# Seed and taps go along, so a verification server can check the run later.
	leaderboard.submit_run(replay.score, replay.to_dict())
	_profile.save(profile_path)
	leaderboard.request_board(LeaderboardService.DAILY)
	_game_over_at_ms = Time.get_ticks_msec()
	_hud.show_game_over(
		replay.score,
		_profile.best_score,
		is_new_best,
		earned,
		previous_best,
		_rooms_cleared,
		leaderboard.cached_rank(LeaderboardService.DAILY)
	)


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
