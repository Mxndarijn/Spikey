extends Node2D
## The app: the live room and flyer always run in the background; menus
## (home, shop) sit on top, and Play starts a run. Main wires the parts
## together and moves between screens and run modes:
##   AppServices (leaderboards, wallet, store, push, ads), RunLook (what the
##   live room looks like), ReviveFlow (the revive offer), BoardAlerts (prize
##   spot and push alerts), RunController (the sim), Hud and MenuLayer.
## Flow: Home -> Play. A first start goes straight to Home with the first free
## flyer and the default world; players change them in Customize.
## Home -> Rooms -> a room -> Practice repeats that room; practice never touches
## coins, best score, room stats or leaderboards. The debug page's pickers
## practise any room and variant, or a whole run from a typed seed.
## Room stats (Profile: reached, cleared, deaths per room id; a variant counts
## under its room) come from real runs only: practice, replays and the bots
## (which run the sim without this app) never count. A run left from the pause
## menu counts its rooms as reached but neither cleared nor died in.
## Home -> the #rank item in the dock -> Leaderboards: the friends' Supabase
## boards when services/supabase_config.json exists, else made-up sample boards.
## Home -> Settings (the dock) -> the settings sheet; main applies each change.
## Game over has its own dock: Home, Rooms | Again | #rank, Style.
## Leaderboards -> a run -> Replay plays that run back in the live room with
## the recorded player's look; it never touches the save or the leaderboards,
## and Back returns to the leaderboards.
## Home -> Your runs: the player's own last 100 runs and up to 20 saved ones
## (RunStore, on this phone). Watch plays one back the same way, in the look
## it was played in; Back returns to Your runs (or Home, from Home's card).

enum Mode { MENU, RUN, PRACTICE, REPLAY }

const RESTART_DELAY_MS := 450
## Resume counts 3, 2, 1 before the run plays on.
const RESUME_COUNTDOWN := 3.0
## After a revive: 5, 4, 3, 2, 1 over the room, then the bird flies on by
## itself at 0. The last SimConfig.ARRIVAL_HOLD ticks of it are the sim's own
## frozen wait after a revive (taps ignored there too), so the run is paused
## only for the time before that.
const REVIVE_COUNTDOWN := 5
## Settings > Haptics: a short buzz on flap, a longer one on a crash.
const HAPTIC_FLAP_MS := 12
const HAPTIC_CRASH_MS := 40
## show_store(): go back to "Your look" instead of a Customize list.
const BACK_TO_LOOK := "look"
## show_store(): go back to Earn diamonds.
const BACK_TO_EARN := "earn"

## Where the save lives; tests point this somewhere else.
var profile_path := Profile.PATH
## Where Your runs keeps the player's runs; tests point this somewhere else.
var runs_path := RunStore.PATH
## The Supabase config that turns on the online boards and wallet; tests that
## need the offline ones clear it, so a config on the PC changes nothing.
var board_config_path := SupabaseClient.CONFIG_PATH
var mode := Mode.MENU
## Seasonal rooms in play (Seasons.*), from today's date; tests can set it.
var season := SeasonCalendar.today()
## The services; tests can swap in their own before _ready (AppServices makes
## the ones left empty).
var leaderboard: LeaderboardService
var store: StoreService
var wallet: WalletService
var push: PushService
var ads: AdsService
var profile_sync: ProfileSync

var _profile: Profile
var _runs: RunStore
## The save changed from the server's copy during a run: Home puts it on.
var _look_stale := false
var _services: AppServices
var _look: RunLook
var _revive: ReviveFlow
var _alerts: BoardAlerts
var _game_over_at_ms := -1
var _menus := MenuLayer.new()
var _audio := AudioDirector.new()
## Practice: the room id being repeated. Real runs: the room being played, so
## the next room change can count it as cleared.
var _practice_id := ""
## Practice from the debug page's room picker: the variant id it plays ("" =
## drawn as usual). Real runs never set it.
var _practice_variant := ""
## Practice from the debug page's seed picker: the seed every try plays (-1 =
## a new random seed each try). Real runs never set it.
var _practice_seed := -1
## The season that seed plays in (its seed code holds it), not today's.
var _practice_season := Seasons.NONE
## Practice started from the debug page: leaving it goes back there, not to Rooms.
var _practice_from_debug := false
var _room_id := ""
## Rooms cleared in the current real run, for the game-over stats.
var _rooms_cleared := 0
## Replay: the run's driver and the board to go back to.
var _replay_driver: ReplayDriver
var _replay_board := LeaderboardService.DAILY
## Where Back goes from a replay of the player's own run (show_runs or
## show_home); empty for a leaderboard run.
var _replay_back := Callable()
## Where Back goes from Earn diamonds (show_home unless set).
var _earn_back := Callable()
## The room group the Rooms screen last showed ("" for the group cards).
var _rooms_group := ""
## Counting down after a revive (REVIVE_COUNTDOWN): taps do nothing.
var _revive_count := false
## Seconds left in the 3, 2, 1 before a resumed run plays on (0: none).
var _countdown := 0.0

@onready var _run: RunController = $RunController
@onready var _room: RoomView = $RoomView
@onready var _trail: TrailView = $TrailView
@onready var _crash: CrashView = $CrashView
@onready var _bird: BirdView = $BirdView
@onready var _night: NightView = $NightView
@onready var _coin: CoinView = $CoinView
@onready var _hazards: HazardLayer = $HazardLayer
@onready var _hud: Hud = $Hud


func _ready() -> void:
	add_child(_menus)
	add_child(_audio)
	_profile = Profile.load_or_new(profile_path)
	Catalog.repair(_profile)
	# A test's own save keeps its runs next to it, never in the player's file.
	if runs_path == RunStore.PATH and profile_path != Profile.PATH:
		runs_path = profile_path.get_basename() + "_runs.json"
	_runs = RunStore.new(runs_path)
	_make_services()
	_look = RunLook.new(_profile, _room, _hazards, _trail, _bird, _crash, _menus, _hud, _audio)
	_look.use_equipped()
	_revive = ReviveFlow.new(_profile, _run, ads, _hud.revive_offer, _save_profile)
	_revive.ended.connect(_finish_run)
	_revive.revived.connect(_on_revive)
	_alerts = BoardAlerts.new(_profile, push, _save_profile)
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
	_hud.rooms_pressed.connect(_leave_to_rooms)
	_hud.leaderboard_pressed.connect(show_leaderboard)
	_hud.style_pressed.connect(show_look)
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
	# The server's copy of the save: on a reinstall this brings the old one back.
	profile_sync.push()


## The services: any a test set before _ready, the rest from AppServices.
func _make_services() -> void:
	if leaderboard == null:
		leaderboard = AppServices.make_leaderboard(_profile, self, board_config_path)
	var api := AppServices.supabase_of(leaderboard)
	if wallet == null:
		wallet = AppServices.make_wallet(_profile, api)
	if store == null:
		store = AppServices.make_store(wallet)
	if push == null:
		push = AppServices.make_push(api)
	if ads == null:
		ads = AppServices.make_ads(_profile)
	if profile_sync == null:
		profile_sync = ProfileSync.new(_profile, api)
	_services = AppServices.new()
	_services.leaderboard = leaderboard
	_services.wallet = wallet
	_services.store = store
	_services.push = push
	_services.ads = ads
	_services.profile_sync = profile_sync
	_services.audio = _audio
	_services.checkout = Checkout.new(_profile, wallet)
	_services.checkout.changed.connect(_save_profile)
	leaderboard.board_loaded.connect(_on_board_loaded)
	wallet.synced.connect(_on_wallet_synced)
	store.purchased.connect(_on_purchased)
	store.restored.connect(_on_restored)
	profile_sync.synced.connect(_on_profile_synced)
	ads.start()


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
	_practice_seed = -1
	_menus.clear()
	_look.show_flyer(true)
	_new_run()
	_audio.best_score = _profile.best_score
	_hud.show_ready()
	ads.preload_rewarded()


func show_home() -> void:
	_drop_replay()
	if _look_stale:
		_look_stale = false
		_look.use_equipped()
	mode = Mode.MENU
	_audio.menu()
	_new_run()
	_hud.show_menu()
	# Home draws the flyer itself, bigger, so the live one hides.
	_look.show_flyer(false)
	var home := HomeScreen.new(
		_profile, _services, leaderboard.cached_rank(LeaderboardService.DAILY), _runs.history.last()
	)
	home.play_pressed.connect(start_run)
	home.leaderboard_pressed.connect(show_leaderboard)
	# The dock's Style opens Customize on "Your look".
	home.customize_pressed.connect(show_look)
	home.shop_pressed.connect(show_shop)
	home.rooms_pressed.connect(show_rooms)
	home.store_pressed.connect(show_store)
	home.earn_pressed.connect(_show_earn)
	home.runs_pressed.connect(show_runs)
	home.watch_last_pressed.connect(watch_run.bind(show_home))
	home.settings_changed.connect(_on_settings_changed)
	home.practice_requested.connect(start_picker_practice)
	home.seed_requested.connect(start_seed_practice)
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
	_look.show_flyer(false)
	var screen := LeaderboardScreen.new(_profile, leaderboard, board_id)
	screen.closed.connect(show_home)
	screen.play_pressed.connect(start_run)
	screen.name_changed.connect(_on_leaderboard_name)
	screen.replay_requested.connect(_on_replay_requested.bind(screen))
	_menus.show_screen(screen)


func _on_replay_requested(run: Dictionary, screen: LeaderboardScreen) -> void:
	_replay_board = screen.board_id()
	_replay_back = Callable()
	play_replay(run)


## Your runs: Latest (the last 100 runs) or Saved.
func show_runs(tab: String = RunsScreen.LATEST) -> void:
	_drop_replay()
	mode = Mode.MENU
	_hud.show_menu()
	_look.show_flyer(false)
	var screen := RunsScreen.new(_runs, tab)
	screen.closed.connect(show_home)
	screen.watch_requested.connect(
		func(r: RunRecord) -> void: watch_run(r, show_runs.bind(screen.tab()))
	)
	_menus.show_screen(screen)


func runs() -> RunStore:
	return _runs


## Plays one of the player's own runs back, in the look it was played in;
## Back calls `back`. A run from an older version shows why it can't play.
func watch_run(record: RunRecord, back: Callable = Callable()) -> void:
	if record == null:
		return
	_replay_back = back if back.is_valid() else show_runs
	var run := record.run.to_dict()
	run["name"] = "You"
	if not record.watchable():
		# ReplayDriver.problem() turns it down with the older-version message.
		run = {"seed": record.run.replay.seed_value, "gameplay_version": -1}
	play_replay(run)


## Plays a leaderboard run (SupabaseLeaderboard.parse_run output) back in the
## live room, with that player's flyer, world, trail, portal and music. Taps
## come only from the recording. A run from another gameplay version, or an
## empty one (it didn't load), shows a message instead.
func play_replay(run: Dictionary) -> void:
	mode = Mode.REPLAY
	_menus.clear()
	var problem := ReplayDriver.problem(run)
	if not problem.is_empty():
		_replay_driver = null
		_look.show_flyer(false)
		_hud.show_menu()
		_hud.replay_hud().show_message(problem)
		return
	_replay_driver = ReplayDriver.from_run(run, season)
	_look.borrow(run.get("loadout", {}) as Dictionary)
	var player := str(run.get("name", ""))
	var score := int(run.get("score", 0))
	_hud.replay_hud().set_run(player if not player.is_empty() else "Player", score)
	_replay_again()


## Watch again: the same run from its first tick.
func _replay_again() -> void:
	if mode != Mode.REPLAY or _replay_driver == null:
		return
	_set_paused(false)
	_look.show_flyer(true)
	_new_run()
	_hud.show_ready()


## Back (or the exit icon): the leaderboards, on the board the run came from.
func _leave_replay() -> void:
	_audio.menu()
	if _replay_back.is_valid():
		var back := _replay_back
		_replay_back = Callable()
		back.call()
		return
	show_leaderboard(_replay_board)


## Leaving a replay: the player's own look comes back, and a replay still
## playing stops. Without the fresh run it would play on behind the menus.
func _drop_replay() -> void:
	_replay_driver = null
	if _look.borrowed:
		_look.use_equipped()
	if _run.driver != null:
		_new_run()


func _on_leaderboard_name(player_name: String) -> void:
	_save_profile()
	leaderboard.set_player(player_name, _profile.equipped_id(ItemKind.FLYER))


## Today's rank reached home: show it on the Leaderboard button.
func _on_board_loaded(board: LeaderboardBoard) -> void:
	if board.id != LeaderboardService.DAILY:
		return
	var rank := board.me.rank if board.me != null else 0
	_alerts.on_daily_board(board, rank)
	var home := _menus.current() as HomeScreen
	if home != null:
		home.set_daily_rank(rank)
		_show_spot_notice()
	# Game over shows today's rank too, once the board with this run arrives.
	_hud.set_daily_rank(rank)


## Shows a waiting lost-spot line on Home, once.
func _show_spot_notice() -> void:
	var home := _menus.current() as HomeScreen
	if home == null:
		return
	var notice := _alerts.take_notice()
	if not notice.is_empty():
		home.show_notice(notice)


## The Rooms screen: the room groups, or one group's rooms. Leaving practice
## goes back to the practised room's group.
func show_rooms(group: String = "") -> void:
	if group.is_empty() and not _practice_id.is_empty():
		var practised := RoomCatalog.find(_practice_id)
		if practised != null:
			group = RoomInfo.group(practised)
	mode = Mode.MENU
	_practice_id = ""
	_practice_variant = ""
	_practice_seed = -1
	_rooms_group = group
	_new_run()
	_hud.show_menu()
	_look.show_flyer(false)
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
	_look.show_flyer(false)
	var detail := RoomDetailScreen.new(_profile, id)
	detail.closed.connect(show_rooms.bind(_rooms_group))
	detail.practice_pressed.connect(start_practice)
	_menus.show_screen(detail)


## A practice run that repeats one room, from the Rooms screen. Open rooms
## only (met in a real run); the variant is drawn as usual.
func start_practice(id: String) -> void:
	var def := RoomCatalog.find(id)
	if def == null or not RoomInfo.is_open(_profile, def):
		return
	_practise(id, "")


## A practice run from the debug page's room picker, in every build: any room,
## and `variant` plays that variant every try ("" draws it as usual). Practice
## never changes the save, so this gives nothing away.
func start_picker_practice(id: String, variant: String = "") -> void:
	var def := RoomCatalog.find(id)
	if def == null:
		return
	if not variant.is_empty() and not RoomPicker.variant_ids(def).has(variant):
		return
	_practise(id, variant)
	_practice_from_debug = true


## A practice run from the debug page's seed picker, in every build: the whole
## run of seed `seed_value` in `season` (the seed code's, never today's) from
## its first room, again on every try. As practice it never changes the save
## or the leaderboards.
func start_seed_practice(seed_value: int, p_season: int = Seasons.NONE) -> void:
	if seed_value < 0 or seed_value > SeedCode.MAX_RANDOM:
		return
	if p_season < Seasons.NONE or p_season >= Seasons.COUNT:
		return
	_practice_season = p_season
	_practise("", "", seed_value)
	_practice_from_debug = true


func _practise(id: String, variant: String, seed_value: int = -1) -> void:
	mode = Mode.PRACTICE
	_practice_id = id
	_practice_variant = variant
	_practice_seed = seed_value
	_practice_from_debug = false
	_menus.clear()
	_look.show_flyer(true)
	var shown := RoomInfo.name_of(id)
	if seed_value >= 0:
		shown = "Seed " + SeedCode.current(seed_value, _practice_season)
	elif not variant.is_empty():
		shown = RoomPicker.choice_text(id, variant)
	_hud.set_practice(shown)
	_new_run()
	_hud.show_ready()


## The HUD's Rooms (practice over, pause, Ready's back arrow, game-over dock):
## practice from the debug page goes back to that page, the rest to Rooms.
func _leave_to_rooms() -> void:
	if mode == Mode.PRACTICE and _practice_from_debug:
		show_debug()
	else:
		show_rooms()


## Home with the settings sheet open on the debug page.
func show_debug() -> void:
	_practice_from_debug = false
	show_home()
	var home := _menus.current() as HomeScreen
	if home != null:
		home.open_settings().show_debug(true)


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
	_look.show_flyer(false)
	# A world previewed in a list gives way to the one in use.
	_look.show_own_world()
	var look := LookScreen.new(_profile)
	look.closed.connect(show_home)
	look.kind_pressed.connect(show_shop)
	look.earn_pressed.connect(_show_earn.bind(show_look))
	_menus.show_screen(look)


## One kind's list in Customize (its shop and the player's own items in one
## screen). Back returns to "Your look".
func show_shop(tab: String = ItemKind.FLYER) -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_look.show_flyer(false)
	var shop := CollectionScreen.new(_services.checkout, CollectionScreen.Mode.SHOP, tab)
	shop.audio = _audio
	shop.closed.connect(show_look)
	shop.equipped.connect(_on_equipped)
	shop.previewed.connect(_preview)
	shop.earn_pressed.connect(func() -> void: _show_earn(show_shop.bind(shop.kind)))
	_menus.show_screen(shop)


## The Shop: diamond packs and turning diamonds into gold. `back_tab`: the
## Customize list to go back to, BACK_TO_LOOK for "Your look", BACK_TO_EARN for
## Earn diamonds, or "" for Home.
func show_store(back_tab: String = "") -> void:
	mode = Mode.MENU
	_hud.show_menu()
	_look.show_flyer(false)
	var screen := StoreScreen.new(_services.checkout, store)
	if back_tab.is_empty():
		screen.closed.connect(show_home)
	elif back_tab == BACK_TO_LOOK:
		screen.closed.connect(show_look)
	elif back_tab == BACK_TO_EARN:
		screen.closed.connect(_show_earn.bind(_earn_back))
	else:
		screen.closed.connect(show_shop.bind(back_tab))
	_menus.show_screen(screen)


## Earn diamonds: every way to win diamonds and how far the player is. The
## cards fill in as the player's status (wallet) and the Daily board arrive.
## `back`: where its Back goes (Home when empty).
func _show_earn(back: Callable = Callable()) -> void:
	_earn_back = back if back.is_valid() else Callable(show_home)
	mode = Mode.MENU
	_hud.show_menu()
	_look.show_flyer(false)
	var screen := EarnScreen.new(_profile)
	screen.closed.connect(_earn_back)
	screen.store_pressed.connect(show_store.bind(BACK_TO_EARN))
	leaderboard.board_loaded.connect(screen.show_board)
	_menus.show_screen(screen)
	leaderboard.request_board(LeaderboardService.DAILY)
	@warning_ignore("redundant_await")
	var status: EarnStatus = await wallet.earn_status()
	if is_instance_valid(screen):
		screen.show_status(status)


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
	popup.earn_pressed.connect(
		func() -> void:
			home.close_prizes()
			_show_earn()
	)


func _claim_prizes(popup: DailyPrizePopup) -> void:
	@warning_ignore("redundant_await")
	var won: int = await wallet.claim()
	_save_profile()
	if not is_instance_valid(popup):
		return
	if won <= 0:
		popup.show_failed()
		return
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


## The store gave back earlier purchases: hand out the kept ones (the Revive
## Pass) the save is missing and save at once.
func _on_restored(pack_ids: Array[String]) -> void:
	if not DiamondPacks.restore(_profile, pack_ids).is_empty():
		_save_profile()
		AudioDirector.sound("purchase")


func _save_profile() -> void:
	_profile.save(profile_path)
	profile_sync.push()


## The server's copy of the save answered. Merged: worn items, gold or
## settings came from it, so the look is put on again (at once in the menus;
## a run keeps its look and gets it at the next Home).
func _on_profile_synced(merged: bool) -> void:
	_profile.save(profile_path)
	if not merged:
		return
	Catalog.repair(_profile)
	apply_settings()
	if mode != Mode.MENU:
		_look_stale = true
		return
	_look.use_equipped()
	if _menus.current() is HomeScreen:
		show_home()


## Switches world right away; cosmetic only, so it is safe mid-run.
func set_world(id: String) -> void:
	var t := Catalog.world(id)
	if t != null:
		_look.set_world(t)
		_hud.show_toast(t.display_name)


## First start: no pickers. The player gets the first free flyer and the
## default world, already in use, and goes straight to Home.
func _first_start() -> void:
	var flyer := Shop.starters(ItemKind.FLYER)[0]
	_profile.grant(ItemKind.FLYER, flyer)
	_profile.equip(ItemKind.FLYER, flyer)
	_profile.grant(ItemKind.WORLD, ThemeCatalog.DEFAULT_ID)
	_profile.equip(ItemKind.WORLD, ThemeCatalog.DEFAULT_ID)
	_profile.onboarded = true
	_save_profile()
	_look.use_equipped()


## Customize previews a world in the room behind it without saving it.
func _preview(kind: String, id: String) -> void:
	if kind == ItemKind.WORLD:
		_look.preview_world(id)


func _on_equipped(_kind: String, _id: String) -> void:
	_save_profile()
	_look.use_equipped()


## Paused: the Music and Sounds circles.
func _on_sound_toggled(which: String, on: bool) -> void:
	if which == "music":
		_profile.settings.music_on = on
	else:
		_profile.settings.sfx_on = on
	_on_settings_changed()


func _on_settings_changed() -> void:
	_save_profile()
	apply_settings()
	_alerts.on_settings_changed()


## Every setting from the save: sound, then Settings > Play.
func apply_settings() -> void:
	var s := _profile.settings
	_audio.set_volumes(s.music_volume, s.sfx_volume, s.music_on, s.sfx_on)
	_look.choose_music()
	# Reduced flashing: no room flash or shake.
	_room.flash_enabled = not s.reduced_flashing
	# Color-blind spikes: ink spikes with white edges, in the room and its hazards.
	_room.color_blind_spikes = s.color_blind_spikes
	_hazards.color_blind_spikes = s.color_blind_spikes
	UiKit.large_buttons = s.large_buttons
	_hud.reduced_motion = s.reduced_flashing
	_hud.refresh_button_size()


## A short vibration on phones, when Settings > Haptics is on.
func _buzz(ms: int) -> void:
	if _profile != null and _profile.settings.haptics and _in_play():
		Input.vibrate_handheld(ms)


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
		var variant := _practice_variant if practice >= 0 else ""
		var seed_value := randi()
		if mode == Mode.PRACTICE and _practice_seed >= 0:
			seed_value = _practice_seed
			run_season = _practice_season
		_run.new_run(seed_value, run_season, practice, variant)
	_room_id = RoomCatalog.all()[_run.sim.state.room_kind].id
	_room.bind(_run, _look.theme)
	_hazards.bind(_run, _look.theme)
	_bird.bind(_run, _look.character)
	_night.bind(_run, _room, _bird)
	_crash.clear()
	_coin.bind(_run)
	_hud.set_run_coins(0)
	_trail.bind(_bird, _look.trail_style, _look.theme)
	# The HUD shows the score at the top now; the ghost score stays off.
	_room.show_score = false
	_rooms_cleared = 0
	_game_over_at_ms = -1
	_revive.reset()
	_revive_count = false
	_countdown = 0.0


func _in_play() -> bool:
	return mode == Mode.RUN or mode == Mode.PRACTICE


func _try_restart() -> void:
	if mode == Mode.PRACTICE:
		_restart_practice()
		return
	# The revive offer has its own buttons: a tap beside them does nothing.
	if _revive.is_offering():
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
	elif _revive_count:
		# The end of the revive countdown: not a flap either.
		pass
	elif _run.sim.is_over():
		_try_restart()
	else:
		_run.request_tap()


## Lets go of the shared caches so Godot can free them when the game closes
## (otherwise it reports leaked resources on exit).
func _exit_tree() -> void:
	AudioServer.set_bus_mute(0, false)
	UiTheme.release()
	GameFonts.release()
	Catalog.release()
	HazardLayer.release()
	WorldScenes.release()
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
## the frozen room, so the player can find the bird before it moves.
func _resume() -> void:
	_hud.show_paused(false, _profile.settings.music_on, _profile.settings.sfx_on)
	_countdown = RESUME_COUNTDOWN
	_hud.countdown.show_count(ceili(_countdown))


func _process(delta: float) -> void:
	_tick_countdown(delta)


func _tick_countdown(delta: float) -> void:
	if _countdown <= 0.0:
		_tick_revive_hold()
		return
	_countdown -= delta
	if _countdown > 0.0:
		_hud.countdown.show_count(ceili(_countdown + _revive_hold_seconds()))
	elif _revive_count:
		# The sim's frozen wait counts the rest down.
		_set_paused(false)
		_revive_count = true
		_tick_revive_hold()
	else:
		_set_paused(false)


## The last part of the revive countdown: the run plays, the sim holds the
## bird (SimState.arrival_hold) and the count follows it down to 0.
func _tick_revive_hold() -> void:
	if not _revive_count:
		return
	var hold := _run.sim.state.arrival_hold
	_hud.countdown.show_count(ceili(hold / float(SimConfig.TICKS_PER_SECOND)))
	if hold <= 0:
		_revive_count = false


## Seconds of the revive countdown the sim's own hold takes (0 when not
## counting down after a revive).
func _revive_hold_seconds() -> float:
	if not _revive_count:
		return 0.0
	return SimConfig.ARRIVAL_HOLD / float(SimConfig.TICKS_PER_SECOND)


## Pauses or plays on at once (no countdown).
func _set_paused(value: bool) -> void:
	_countdown = 0.0
	_revive_count = false
	_hud.countdown.show_count(0)
	_run.set_paused(value)
	_hud.show_paused(value, _profile.settings.music_on, _profile.settings.sfx_on)


## The coin flies from where it was in the room into the counter.
func _on_coin_collected(total: int) -> void:
	var s := _run.sim.state
	_hud.fly_coin(Vector2(s.pickup_x, s.pickup_y) / float(SimConfig.SUB), total)


## A real run reached its first room (the first tap; a revive is not a start).
func _on_run_started() -> void:
	if mode == Mode.RUN:
		_profile.record_room_reached(_room_id)


## A real run survived all of a room's points: count it, and reach the next.
func _on_room_changed(_room_index: int) -> void:
	if mode != Mode.RUN or _run.sim == null:
		return
	_profile.record_room_cleared(_room_id)
	_rooms_cleared += 1
	_room_id = RoomCatalog.all()[_run.sim.state.room_kind].id
	_profile.record_room_reached(_room_id)


func _on_died(replay: Replay) -> void:
	_buzz(HAPTIC_CRASH_MS)
	_bird.on_death()
	_look.play_crash(_run.sim)
	_room.show_score = false
	_trail.stop()
	if mode == Mode.PRACTICE:
		_hud.show_practice_over(_run.sim.shown_score())
		return
	if mode == Mode.REPLAY:
		# Someone else's run: no coins, best score or leaderboard.
		_hud.replay_hud().show_over()
		return
	# Only a real run counts: nothing that ends behind a menu is the player's.
	if mode == Mode.RUN:
		# Every crash is a death in its room, also one the player then revives
		# from; the revived run can still clear the room.
		_profile.record_room_death(_room_id)
		_revive.on_crash(replay)


## Revived from the offer: the bird is back and a 5, 4, 3, 2, 1 counts down
## over the frozen room (the player may have looked away for an ad); at 0 it
## flies on by itself.
func _on_revive() -> void:
	_hud.show_running()
	_start_revive_countdown()


func _start_revive_countdown() -> void:
	_run.set_paused(true)
	_revive_count = true
	_countdown = REVIVE_COUNTDOWN - _revive_hold_seconds()
	_hud.countdown.show_count(REVIVE_COUNTDOWN)


## The sim revived the bird (also in a replay of a revived run): it comes out
## of the portal it came into the room by, as at a portal arrival.
func _on_revived() -> void:
	_room.on_revived()
	# The crash effect may have turned the flyer into pieces: bring it back.
	_crash.clear()
	_bird.on_revived()
	_trail.start()
	# A replay shows the revive as the run had it: the same 5, 4, 3, 2, 1.
	if mode == Mode.REPLAY:
		_start_revive_countdown()


## A real run is over for good: coins, best score, the boards and Game over.
func _finish_run(replay: Replay) -> void:
	var previous_best := _profile.best_score
	var is_new_best := replay.score > previous_best
	var earned := _profile.record_run(replay.score, replay.coins)
	# Your runs keeps it on the phone, in the look it was played in.
	_runs.add(
		RunRecord.make(
			replay,
			LeaderboardService.loadout_of(_profile),
			int(Time.get_unix_time_from_system()),
			_rooms_cleared + 1,
			_revive.revived_at,
			is_new_best
		)
	)
	# Seed and taps go along, so a verification server can check the run later.
	leaderboard.submit_run(replay.score, replay.to_dict())
	_save_profile()
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
		_revive.revived_at,
		replay.season
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
