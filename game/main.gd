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
## A real run that crashes with a fair score first gets the revive offer (once
## per run): one of the day's free revives, or a rewarded ad when those are
## used. Skip, or a second crash, ends the run (docs/REVIVE.md).
## Leaderboards -> a run -> Replay plays that run back in the live room with
## the recorded player's look; it never touches the save or the leaderboards,
## and Back returns to the leaderboards.

enum Mode { MENU, RUN, PRACTICE, REPLAY }

const RESTART_DELAY_MS := 450
## Resume counts 3, 2, 1 before the run plays on.
const RESUME_COUNTDOWN := 3.0
## Settings > Haptics: a short buzz on flap, a longer one on a crash.
const HAPTIC_FLAP_MS := 12
const HAPTIC_CRASH_MS := 40
## show_store(): go back to "Your look" instead of a Customize list.
const BACK_TO_LOOK := "look"
## No revive offer below this score: a quick crash restarts with one tap.
const REVIVE_MIN_SCORE := 5
## The AdMob provider and the native plugin it needs (addons/admob).
const ADMOB_ADS := "res://services/admob_ads.gd"
const ADMOB_SINGLETON := "PoingGodotAdMob"
## The Firebase push service and the native plugin it needs (addons/godotx_firebase).
const FIREBASE_PUSH := "res://services/firebase_push.gd"
const FIREBASE_SINGLETON := "GodotxFirebaseMessaging"

## Where the save lives; tests point this somewhere else.
var profile_path := Profile.PATH
## The Supabase config that turns on the online boards and wallet; tests that
## need the offline ones clear it, so a config on the PC changes nothing.
var board_config_path := SupabaseLeaderboard.CONFIG_PATH
var mode := Mode.MENU
## Seasonal rooms in play (Seasons.*), from today's date; tests can set it.
var season := SeasonCalendar.today()
## The leaderboards; tests can swap in their own before _ready.
var leaderboard: LeaderboardService
## Real-money purchases; tests can swap in their own before _ready.
var store: StoreService
## Where the diamonds live; tests can swap in their own before _ready.
var wallet: WalletService
## Push notifications (Board alerts); tests can swap in their own before _ready.
var push: PushService
## Rewarded ads for the revive; tests can swap in their own before _ready.
var ads: AdsService

var _profile: Profile
var _game_over_at_ms := -1
var _theme: ThemeDef
var _character: CharacterDef
var _trail_style: TrailStyle
var _crash_style: CrashStyle
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
## The room group the Rooms screen last showed ("" for the group cards).
var _rooms_group := ""
## A lost prize spot to tell the player about on Home (SpotAlert), or "".
var _spot_notice := ""
## Settings > Board alerts as last sent to the server.
var _alerts_on := true
## The crashed run while the revive offer shows (null: no offer).
var _offer_replay: Replay
## The score this run was revived at (-1: not revived).
var _revived_at := -1
## Just revived: the run waits, paused, for the player's tap.
var _revive_wait := false
## Seconds left in the 3, 2, 1 before a resumed run plays on (0: none).
var _countdown := 0.0

@onready var _run: RunController = $RunController
@onready var _room: RoomView = $RoomView
@onready var _trail: TrailView = $TrailView
@onready var _crash: CrashView = $CrashView
@onready var _bird: BirdView = $BirdView
@onready var _coin: CoinView = $CoinView
@onready var _hazards: HazardLayer = $HazardLayer
@onready var _hud: Hud = $Hud


func _ready() -> void:
	add_child(_menus)
	add_child(_audio)
	_profile = Profile.load_or_new(profile_path)
	_alerts_on = _profile.board_alerts
	if leaderboard == null:
		leaderboard = _make_leaderboard()
	leaderboard.board_loaded.connect(_on_board_loaded)
	if wallet == null:
		wallet = _make_wallet()
	wallet.synced.connect(_on_wallet_synced)
	if store == null:
		store = _make_store()
	if push == null:
		push = _make_push()
	PushService.current = push
	# Permission given on an earlier start: fetch this start's token.
	if _profile.board_alerts and _profile.push_asked:
		push.start()
	store.purchased.connect(_on_purchased)
	if ads == null:
		ads = _make_ads()
	AdsService.current = ads
	ads.rewarded_closed.connect(_on_ad_closed)
	ads.start()
	_load_equipped()
	_audio.bind(_run)
	_run.run_started.connect(_hud.show_running)
	_run.run_started.connect(_trail.start)
	_run.flapped.connect(_bird.on_flap)
	_run.flapped.connect(_trail.on_flap)
	_run.bounced.connect(_bird.on_bounce)
	_run.room_changed.connect(_room.on_room_changed)
	_run.died.connect(_on_died)
	_run.revived.connect(_on_revived)
	_run.coin_spawned.connect(_coin.on_spawned)
	_run.coin_collected.connect(_coin.on_collected)
	_run.coin_collected.connect(_on_coin_collected)
	_hud.pause_pressed.connect(_toggle_pause)
	_hud.play_again_pressed.connect(_try_restart)
	_hud.home_pressed.connect(show_home)
	_hud.restart_pressed.connect(_restart_practice)
	_hud.rooms_pressed.connect(show_rooms)
	_hud.leaderboard_pressed.connect(show_leaderboard)
	_hud.style_pressed.connect(show_look)
	_hud.sound_toggled.connect(_on_sound_toggled)
	_hud.replay_again_pressed.connect(_replay_again)
	_hud.replay_back_pressed.connect(_leave_replay)
	_hud.revive_offer.revive_pressed.connect(_on_revive_pressed)
	_hud.revive_offer.skip_pressed.connect(_on_revive_skipped)
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
	ads.preload_rewarded()


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
	# The dock's Style opens Customize on "Your look".
	home.customize_pressed.connect(show_look)
	home.shop_pressed.connect(show_shop)
	home.rooms_pressed.connect(show_rooms)
	home.store_pressed.connect(show_store)
	home.settings_changed.connect(_on_settings_changed)
	_menus.show_screen(home)
	leaderboard.request_board(LeaderboardService.DAILY)
	# The balance and any daily prize waiting to be claimed.
	wallet.sync()
	_show_spot_notice()


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
	_audio.menu()
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
	var crash := Catalog.crash(str(look.get(Catalog.CRASH, "")))
	if crash != null:
		_crash_style = crash
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


## Leaving a replay: the player's own look comes back, and a replay still
## playing stops. Without the fresh run it would play on behind the menus.
func _drop_replay() -> void:
	_replay_driver = null
	if _replay_look:
		_replay_look = false
		_load_equipped()
	if _run.driver != null:
		_new_run()


func _on_leaderboard_name(player_name: String) -> void:
	_profile.save(profile_path)
	leaderboard.set_player(player_name, _profile.equipped_id(Catalog.FLYER))


## Supabase when its config file is there (docs/LEADERBOARD_SETUP.md), else samples.
func _make_leaderboard() -> LeaderboardService:
	var config := SupabaseLeaderboard.load_config(board_config_path)
	if config.is_empty():
		return SampleLeaderboard.new(_profile)
	var online := SupabaseLeaderboard.new(_profile, self, config.url, config.anon_key)
	online.restore()
	return online


## AdMob on a phone whose build has the plugin's native side (debug builds
## ask for Google's test ads). Elsewhere: a stand-in ad in debug builds, so
## the ad path can be played on a PC, and no ads at all in release builds.
func _make_ads() -> AdsService:
	var test_ads := OS.is_debug_build() or _profile.test_ads
	var unit := AdsService.revive_unit(OS.get_name(), test_ads)
	if not unit.is_empty() and Engine.has_singleton(ADMOB_SINGLETON):
		# Loaded by path: naming the class would load the plugin on every PC too.
		return (load(ADMOB_ADS) as GDScript).new(unit)
	return FakeAds.new() if OS.is_debug_build() else AdsService.new()


## Today's rank reached home: show it on the Leaderboard button.
func _on_board_loaded(board: LeaderboardBoard) -> void:
	var home := _menus.current() as HomeScreen
	if board.id != LeaderboardService.DAILY:
		return
	var rank := board.me.rank if board.me != null else 0
	_track_spot(board, rank)
	if home != null:
		home.set_daily_rank(rank)
		_show_spot_notice()
	# Game over shows today's rank too, once the board with this run arrives.
	_hud.set_daily_rank(rank)


## Remembers the player's place on today's board and notices when someone
## pushed them past a prize line since the last look (never during a run: the
## line shows on Home).
func _track_spot(board: LeaderboardBoard, rank: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	if now >= _profile.daily_spot_until:
		# Yesterday's place says nothing about today's board.
		_profile.daily_spot_rank = 0
	if board.status != LeaderboardBoard.Status.OK or rank <= 0:
		return
	var notice := SpotAlert.message(_profile.daily_spot_rank, rank, board.entries)
	if not notice.is_empty():
		_spot_notice = notice
	if rank != _profile.daily_spot_rank:
		_profile.daily_spot_rank = rank
		_profile.daily_spot_until = now + maxi(board.resets_in_s, 0)
		_save_profile()
	_ask_for_push(rank)


## Shows a waiting lost-spot line on Home, once.
func _show_spot_notice() -> void:
	var home := _menus.current() as HomeScreen
	if home == null or _spot_notice.is_empty():
		return
	home.show_notice(_spot_notice)
	_spot_notice = ""


## The Rooms screen: the room groups, or one group's rooms. Leaving practice
## goes back to the practised room's group.
func show_rooms(group: String = "") -> void:
	if group.is_empty() and not _practice_id.is_empty():
		var practised := RoomCatalog.find(_practice_id)
		if practised != null:
			group = RoomInfo.group(practised)
	mode = Mode.MENU
	_practice_id = ""
	_rooms_group = group
	_new_run()
	_hud.show_menu()
	_show_flyer(false)
	var rooms := RoomsScreen.new(_profile, group)
	if group.is_empty():
		rooms.closed.connect(show_home)
	else:
		rooms.closed.connect(show_rooms.bind(""))
	rooms.group_opened.connect(show_rooms)
	rooms.room_opened.connect(show_room)
	_menus.show_screen(rooms)


func show_room(id: String) -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var detail := RoomDetailScreen.new(_profile, id)
	detail.closed.connect(show_rooms.bind(_rooms_group))
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


## Customize starts on "Your look": one card per cosmetic kind with what is in
## use. A card opens that kind's list (show_shop); Back goes Home.
func show_look() -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	# A world previewed in a list gives way to the one in use.
	_room.set_theme(_theme)
	_hazards.set_theme(_theme)
	var look := LookScreen.new(_profile)
	look.closed.connect(show_home)
	look.kind_pressed.connect(show_shop)
	look.store_pressed.connect(show_store.bind(BACK_TO_LOOK))
	_menus.show_screen(look)


## One kind's list in Customize (its shop and the player's own items in one
## screen). Back returns to "Your look".
func show_shop(tab: String = Catalog.FLYER) -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var shop := CollectionScreen.new(_profile, CollectionScreen.Mode.SHOP, tab)
	shop.wallet_service = wallet
	shop.closed.connect(show_look)
	shop.equipped.connect(_on_equipped)
	shop.previewed.connect(_preview)
	shop.store_pressed.connect(func() -> void: show_store(shop.kind))
	shop.wallet_changed.connect(_save_profile)
	_menus.show_screen(shop)


## The Shop: diamond packs and turning diamonds into gold. `back_tab`: the
## Customize list to go back to, BACK_TO_LOOK for "Your look", or "" for Home.
func show_store(back_tab: String = "") -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_show_flyer(false)
	var screen := StoreScreen.new(_profile, store)
	screen.wallet_service = wallet
	if back_tab.is_empty():
		screen.closed.connect(show_home)
	elif back_tab == BACK_TO_LOOK:
		screen.closed.connect(show_look)
	else:
		screen.closed.connect(show_shop.bind(back_tab))
	screen.changed.connect(_save_profile)
	_menus.show_screen(screen)


## A pretend store in debug builds with a local wallet, else a closed one
## until the app-store billing is in (services/store_service.gd). With the
## diamonds on the server a pretend purchase would be undone by the next sync.
func _make_store() -> StoreService:
	if OS.is_debug_build() and not wallet.is_online():
		return SampleStore.new()
	return StoreService.new()


## Firebase push in a phone build that carries the plugin, else no push.
func _make_push() -> PushService:
	var api := leaderboard as SupabaseLeaderboard
	if Engine.has_singleton(FIREBASE_SINGLETON):
		# Loaded by path, like the ads: naming the class here crashes Godot 4.6
		# beta 2 on exit when every script is loaded (tools/ci/load_all.gd).
		return (load(FIREBASE_PUSH) as GDScript).new(api)
	return PushService.new(api)


## Diamonds on the server when the leaderboards are (Supabase), else in the save.
func _make_wallet() -> WalletService:
	var online := leaderboard as SupabaseLeaderboard
	return SupabaseWallet.new(_profile, online) if online != null else WalletService.new(_profile)


## The wallet answered: keep the copy in the save, show it on Home, and offer
## any daily prize that waits to be claimed.
func _on_wallet_synced(_diamonds: int, prizes: Array) -> void:
	_save_profile()
	var home := _menus.current() as HomeScreen
	if home == null:
		return
	home.wallet().show_balance(_profile)
	if prizes.is_empty() or home.prize_popup() != null:
		return
	var popup := home.show_prizes(prizes)
	popup.claim_pressed.connect(_claim_prizes.bind(popup))


func _claim_prizes(popup: DailyPrizePopup) -> void:
	@warning_ignore("redundant_await")
	var won: int = await wallet.claim()
	if not is_instance_valid(popup):
		_save_profile()
		return
	if won <= 0:
		popup.show_failed()
		return
	_save_profile()
	AudioDirector.sound("purchase")
	var home := _menus.current() as HomeScreen
	if home != null:
		home.wallet().show_balance(_profile)
		home.close_prizes()


## The store confirmed a payment: hand out the pack and save at once.
func _on_purchased(pack_id: String) -> void:
	if DiamondPacks.grant(_profile, pack_id):
		_save_profile()
		AudioDirector.sound("purchase")


func _save_profile() -> void:
	_profile.save(profile_path)


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
	_crash.visible = value


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
	_crash_style = CrashStyle.equipped(_profile)
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
	_apply_board_alerts()


## Settings > Board alerts changed: tell the server, and when it was switched
## on by a player who already reached the top 10, ask for permission now.
func _apply_board_alerts() -> void:
	if _profile.board_alerts == _alerts_on:
		return
	_alerts_on = _profile.board_alerts
	push.set_enabled(_alerts_on)
	if _alerts_on:
		_ask_for_push(_profile.daily_spot_rank)


## Asks for notification permission once, at the moment it means something:
## the player holds a place that wins diamonds.
func _ask_for_push(rank: int) -> void:
	if rank < 1 or Economy.daily_prize(rank) == 0:
		return
	if _profile.push_asked or not _profile.board_alerts or not push.is_available():
		return
	_profile.push_asked = true
	_save_profile()
	push.request_permission()


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
	_crash.clear()
	_coin.bind(_run)
	_hud.set_run_coins(0)
	_trail.bind(_bird, _trail_style, _theme)
	# The HUD shows the score at the top now; the ghost score stays off.
	_room.show_score = false
	_rooms_cleared = 0
	_game_over_at_ms = -1
	_offer_replay = null
	_revived_at = -1
	_revive_wait = false
	_countdown = 0.0


func _in_play() -> bool:
	return mode == Mode.RUN or mode == Mode.PRACTICE


func _try_restart() -> void:
	if mode == Mode.PRACTICE:
		_restart_practice()
		return
	# The revive offer has its own buttons: a tap beside them does nothing.
	if _offer_replay != null:
		return
	if mode == Mode.RUN and Time.get_ticks_msec() - _game_over_at_ms >= RESTART_DELAY_MS:
		_new_run()
		_hud.show_ready()
		ads.preload_rewarded()


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
		# A tap during the countdown does nothing; it is not a flap.
		if _countdown <= 0.0:
			_resume()
	elif _run.sim.is_over():
		_try_restart()
	else:
		_run.request_tap()


## Lets go of the shared caches so Godot can free them when the game closes
## (otherwise it reports leaked resources on exit).
func _exit_tree() -> void:
	if AdsService.current == ads:
		AdsService.current = null
	if PushService.current == push:
		PushService.current = null
	AudioServer.set_bus_mute(0, false)
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


## Pause, or Resume: pause again during the countdown and it stops there.
func _toggle_pause() -> void:
	if not (_run.is_running() or _run.paused):
		return
	if _run.paused and _countdown <= 0.0:
		_resume()
	else:
		_set_paused(true)


## Resume from the pause screen: the scrim goes and a 3, 2, 1 counts down over
## the frozen room, so the player can find the bird before it moves. The tap
## after a revive plays on at once (the bird is already in view).
func _resume() -> void:
	if _revive_wait:
		_set_paused(false)
		return
	_hud.show_paused(false, _profile.music_on, _profile.sfx_on)
	_countdown = RESUME_COUNTDOWN
	_hud.countdown.show_count(ceili(_countdown))


func _process(delta: float) -> void:
	_tick_countdown(delta)


func _tick_countdown(delta: float) -> void:
	if _countdown <= 0.0:
		return
	_countdown -= delta
	if _countdown > 0.0:
		_hud.countdown.show_count(ceili(_countdown))
	else:
		_set_paused(false)


## Pauses or plays on at once (no countdown).
func _set_paused(value: bool) -> void:
	_countdown = 0.0
	_hud.countdown.show_count(0)
	_run.set_paused(value)
	_hud.show_paused(value, _profile.music_on, _profile.sfx_on)
	if not value and _revive_wait:
		# The tap after a revive: "Tap to flap" goes, the run plays on.
		_revive_wait = false
		_hud.show_running()


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
	_play_crash()
	_room.show_score = false
	_trail.stop()
	if mode == Mode.PRACTICE:
		_hud.show_practice_over(RoomView.practice_points(_run.sim))
		return
	if mode == Mode.REPLAY:
		# Someone else's run: no coins, best score or leaderboard.
		_hud.replay_hud().show_over()
		return
	# Only a real run counts: nothing that ends behind a menu is the player's.
	if mode != Mode.RUN:
		return
	if _can_offer_revive(replay):
		_offer_replay = replay
		_hud.revive_offer.show_offer(replay.score, _profile.free_revives_left(Profile.today()))
		return
	_finish_run(replay)


## Whether this crash gets the revive offer: the run has its revive left, the
## score is worth it, and there is a free revive or a loaded ad to pay with.
func _can_offer_revive(replay: Replay) -> bool:
	if not _run.can_revive() or replay.score < REVIVE_MIN_SCORE:
		return false
	return _profile.free_revives_left(Profile.today()) > 0 or ads.is_ready()


## Revive on the offer: a free one if the day has any left, else the ad.
func _on_revive_pressed() -> void:
	if _offer_replay == null:
		return
	if _profile.use_free_revive(Profile.today()):
		_profile.save(profile_path)
		_revive()
	elif ads.is_ready():
		# No game sound under the ad; _on_ad_closed turns it back on.
		AudioServer.set_bus_mute(0, true)
		ads.show_rewarded()
	else:
		# Nothing to pay with any more (the ad went away): the run just ends.
		_on_revive_skipped()


## The rewarded ad closed. Watched: revive. Closed early: that is a Skip, the
## run ends. An ad that broke after the player asked for it revives anyway.
func _on_ad_closed(result: int) -> void:
	AudioServer.set_bus_mute(0, false)
	if _offer_replay == null:
		return
	if result == AdsService.Result.DISMISSED:
		_on_revive_skipped()
	else:
		_revive()


func _on_revive_skipped() -> void:
	if _offer_replay != null:
		_finish_run(_offer_replay)


## Brings the bird back and waits, paused, for a tap.
func _revive() -> void:
	_offer_replay = null
	_revived_at = _run.sim.state.score
	if not _run.revive():
		return
	_revive_wait = true
	_run.set_paused(true)
	_hud.show_running(true)


## The sim revived the bird (also in a replay of a revived run).
func _on_revived() -> void:
	_room.on_revived()
	_trail.start()


## A real run is over for good: coins, best score, the boards and Game over.
func _finish_run(replay: Replay) -> void:
	_offer_replay = null
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
		leaderboard.cached_rank(LeaderboardService.DAILY),
		replay.seed_value,
		_revived_at
	)


## The crash effect in use, where the flyer is drawn; its pieces fly away from
## the wall the flyer was heading for. Looks only: the run is already over.
func _play_crash() -> void:
	if _crash_style == null or _run.sim == null:
		return
	var away := -1.0 if _run.sim.state.vx > 0 else 1.0
	var palette := PackedColorArray()
	if _crash_style.piece == CrashStyle.SHARD and _character != null:
		palette = CrashPainter.flyer_palette(_character.idle)
	_crash.play(_crash_style, _bird.position, away, palette)
	if _crash_style.hides_flyer:
		_bird.fade_out()


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
