class_name Hud
extends CanvasLayer
## The overlay UI of a run, in the minimal kit (no boxes):
##   Ready:     "Tap to flap" with the tap icon, on the room, and a bare back
##              arrow top left (where pause goes): Home, or Rooms in practice.
##              The first flap swaps it for the pause button.
##   Running:   a bare pause icon top left, the score big at the top, the run's
##              coins top right.
##   Paused:    PauseScreen (the score, sound circles, Resume, Home).
##   Crashed:   the revive offer (ReviveOffer) on the dimmed room, when the
##              run has its revive left: Revive (free, or for an ad) or Skip.
##   Game over: GameOverScreen (score, best, stats and the Game over dock).
## Practice runs add PracticeHud (banner, restart, crash screen); watching a
## leaderboard run adds ReplayHud (banner, exit, result) and hides the pause
## button and "Tap to flap"; its coins show lower, beside the score.
## Taps outside buttons pass through to Main as flaps.

signal pause_pressed
signal play_again_pressed
signal home_pressed
## Practice: restart the room, or leave for the Rooms screen. Game over's dock
## uses rooms_pressed too.
signal restart_pressed
signal rooms_pressed
## Game over's dock: the leaderboards and Customize.
signal leaderboard_pressed
signal style_pressed
## Paused: a Music or Sounds circle was tapped ("music" or "sfx").
signal sound_toggled(which: String, on: bool)
## Replay: watch the same run again, or leave for the leaderboards
## (replay_hud() sets the run and shows its result).
signal replay_again_pressed
signal replay_back_pressed

const TOAST_SECONDS := 1.2
## The run's coin counter (top right); lower in a replay, under its chip.
const RUN_COINS_TOP := 54.0
const REPLAY_COINS_TOP := 112.0
const COIN_ICON := preload("res://assets/ui/coin.svg")
const PAUSE_ICON := preload("res://assets/ui/icons/pause.svg")
const BACK_ICON := preload("res://assets/ui/icons/back.svg")
const TAP_ICON := preload("res://assets/ui/icons/tap.svg")
## A collected coin flies from the room into the coin counter (top right).
const FLY_TIME := 0.5
const FLY_SIZE := 28.0
## How high the flight curves above the straight line, in px.
const FLY_ARC := 60.0

## Settings > Reduced flashing: the new-best moment stays still.
var reduced_motion := false
## The room on screen (ScreenLayout); the HUD is laid out over it. Main sets
## it when the screen changes shape.
## The revive offer after a crash. Main shows it (show_offer) and listens to
## its Revive and Skip; the HUD clears the running HUD from under it.
var revive_offer: ReviveOffer
## The 3, 2, 1 over the frozen room after Resume.
var countdown: ResumeCountdown
## Paused and Game over.
var pause_screen: PauseScreen
var game_over: GameOverScreen
var room_rect := Rect2(Vector2.ZERO, ScreenLayout.ROOM):
	set(value):
		room_rect = value
		if _root != null:
			_apply_room_rect()

var _run: RunController
var _toast_tween: Tween
var _coin_tween: Tween
## Coins flying into the counter (fly_coin), until they land.
var _flying: Array[Control] = []
var _run_coins: CoinPill
var _practice: PracticeHud
var _practicing := false
var _replay: ReplayHud
var _replaying := false
var _pause_button: Button
var _back_button: Button
var _score: Label
var _hint: VBoxContainer
var _toast: Label

@onready var _root: Control = $Root


func _ready() -> void:
	# Built here, not in the member list, so a screen freed before it is
	# shown leaves nothing behind.
	_run_coins = CoinPill.new()
	_practice = PracticeHud.new()
	_replay = ReplayHud.new()
	revive_offer = ReviveOffer.new()
	_score = Label.new()
	_hint = VBoxContainer.new()
	_toast = Label.new()
	pause_screen = PauseScreen.new()
	countdown = ResumeCountdown.new()
	game_over = GameOverScreen.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_apply_room_rect()
	_build_running()
	_build_hint()
	_root.add_child(pause_screen)
	pause_screen.resume_pressed.connect(pause_pressed.emit)
	pause_screen.home_pressed.connect(home_pressed.emit)
	pause_screen.sound_toggled.connect(sound_toggled.emit)
	UiKit.across(_root, countdown, 300)
	countdown.visible = false
	_root.add_child(game_over)
	game_over.dock_pressed.connect(_on_dock)
	_root.add_child(_practice)
	_practice.restart_pressed.connect(restart_pressed.emit)
	_practice.rooms_pressed.connect(rooms_pressed.emit)
	_root.add_child(_replay)
	_replay.again_pressed.connect(replay_again_pressed.emit)
	_replay.back_pressed.connect(replay_back_pressed.emit)
	_replay.changed.connect(_on_replay_changed)
	_root.add_child(revive_offer)
	revive_offer.shown.connect(_on_revive_offer_shown)
	_toast.theme_type_variation = &"SkyLabel"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_right = 1.0
	_toast.offset_top = 124
	_toast.offset_bottom = 152
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)
	show_ready()


## The run whose score the HUD shows.
func bind_run(run: RunController) -> void:
	_run = run


func _process(_delta: float) -> void:
	if _run != null and _run.sim != null and _score.visible:
		_score.text = str(_run.sim.shown_score())


func _build_running() -> void:
	_pause_button = UiKit.icon_button(PAUSE_ICON, "Pause")
	_pause_button.name = "Pause"
	_pause_button.position = Vector2(10, 42)
	_pause_button.add_theme_constant_override("icon_max_width", 24)
	_pause_button.pressed.connect(pause_pressed.emit)
	_root.add_child(_pause_button)
	# Same spot and size as pause, so the corner stays put after the first flap.
	_back_button = UiKit.icon_button(BACK_ICON, "Home")
	_back_button.name = "Back"
	_back_button.position = _pause_button.position
	_back_button.add_theme_constant_override("icon_max_width", 24)
	_back_button.pressed.connect(_on_back)
	_root.add_child(_back_button)
	_score.theme_type_variation = &"RoomScore"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.anchor_right = 1.0
	_score.offset_top = 34
	_score.offset_bottom = 34 + UiTheme.RUN_SCORE_SIZE + 6
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score.text = "0"
	_root.add_child(_score)
	_root.add_child(_run_coins)
	# Pinned top right, growing leftward as the number gets longer.
	_run_coins.anchor_left = 1.0
	_run_coins.anchor_right = 1.0
	_run_coins.offset_left = -18
	_run_coins.offset_right = -18
	_run_coins.offset_top = RUN_COINS_TOP
	_run_coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_run_coins.set_amount(0)


## Ready's back arrow: Home, or back to Rooms in practice.
func _on_back() -> void:
	if _practicing:
		rooms_pressed.emit()
	else:
		home_pressed.emit()


func _build_hint() -> void:
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint.add_theme_constant_override("separation", 6)
	_hint.anchor_right = 1.0
	_hint.offset_top = 400
	_hint.offset_bottom = 470
	var icon := TextureRect.new()
	icon.texture = TAP_ICON
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.name = "TapIcon"
	_hint.add_child(icon)
	_hint.add_child(UiKit.label("Tap to flap", &"SkyLabel"))
	_root.add_child(_hint)


func _on_dock(id: String) -> void:
	match id:
		"again":
			play_again_pressed.emit()
		"home":
			home_pressed.emit()
		"rooms":
			rooms_pressed.emit()
		"rank":
			leaderboard_pressed.emit()
		"style":
			style_pressed.emit()


## Updates the run's coin counter and gives it a little bump.
func set_run_coins(total: int) -> void:
	_run_coins.set_amount(total)
	_run_coins.pivot_offset = _run_coins.size / 2.0
	if total > 0 and is_inside_tree():
		AudioDirector.sound("coin_counter")
		if _coin_tween != null:
			_coin_tween.kill()
		_run_coins.scale = Vector2(1.25, 1.25)
		_coin_tween = create_tween()
		_coin_tween.tween_property(_run_coins, "scale", Vector2.ONE, 0.2)


## Sends a coin from `from` (room position) into the counter; the counter
## shows `total` when it lands. Looks only: the coin is already counted in sim/.
func fly_coin(from: Vector2, total: int) -> void:
	var coin := TextureRect.new()
	coin.texture = COIN_ICON
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size = Vector2(FLY_SIZE, FLY_SIZE)
	coin.pivot_offset = coin.size / 2.0
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root.add_child(coin)
	_flying.append(coin)
	var start := from - coin.size / 2.0
	var end := _counter_target() - coin.size / 2.0
	var bend := (start + end) / 2.0 + Vector2(0, -FLY_ARC)
	coin.position = start
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_method(_fly_step.bind(coin, start, bend, end), 0.0, 1.0, FLY_TIME)
	t.tween_callback(_land_coin.bind(coin, total))


## Where flying coins land: the coin icon inside the counter, in room px.
func _counter_target() -> Vector2:
	var r := _run_coins.get_global_rect()
	r.position -= _root.get_global_rect().position
	return Vector2(r.position.x + CoinPill.ICON_SIZE / 2.0, r.position.y + r.size.y / 2.0)


func _apply_room_rect() -> void:
	_root.position = room_rect.position
	_root.size = room_rect.size


static func _fly_step(t: float, coin: Control, start: Vector2, bend: Vector2, end: Vector2) -> void:
	# A curve through `bend`, shrinking a little as it reaches the counter.
	coin.position = start.lerp(bend, t).lerp(bend.lerp(end, t), t)
	coin.scale = Vector2.ONE * lerpf(1.0, 0.7, t)


func _land_coin(coin: Control, total: int) -> void:
	_flying.erase(coin)
	coin.queue_free()
	set_run_coins(total)


## Coins still on their way to the counter.
func flying_coins() -> int:
	return _flying.size()


func run_coins_text() -> String:
	return _run_coins.amount_text()


## The world's theme: white room text on night rooms.
func set_room_theme(t: Theme) -> void:
	if _root != null:
		_root.theme = t


## Settings > Large buttons changed: the pause and back buttons take
## UiKit.button_size().
func refresh_button_size() -> void:
	var s := UiKit.button_size()
	for b: Button in [_pause_button, _back_button]:
		if b != null:
			b.custom_minimum_size = Vector2(s, s)
			b.size = Vector2(s, s)
	_practice.refresh_button_size()
	_replay.refresh_button_size()


## Hides everything (a menu screen is showing).
func show_menu() -> void:
	set_practice("")
	_replay.set_run("", 0)
	show_ready()
	_hint.visible = false
	_back_button.visible = false


## Practice mode for this room name; an empty name goes back to real runs.
func set_practice(room_name: String) -> void:
	_practicing = not room_name.is_empty()
	_practice.set_room(room_name)
	_place_score()


## The practice or replay banner sits at the top; the score goes under it.
func _place_score() -> void:
	var banner := _practicing or _replaying
	_score.offset_top = 92 if banner else 34
	_score.offset_bottom = _score.offset_top + UiTheme.RUN_SCORE_SIZE + 6
	_score.add_theme_font_size_override("font_size", 64 if banner else UiTheme.RUN_SCORE_SIZE)
	# The replay chip fills the top middle; the coins drop beside the score.
	_run_coins.offset_top = REPLAY_COINS_TOP if _replaying else RUN_COINS_TOP
	_run_coins.offset_bottom = _run_coins.offset_top


## The replay banner and result. Its set_run() starts or ends replay mode.
func replay_hud() -> ReplayHud:
	return _replay


## Replay mode follows the ReplayHud; its result screen covers the run's HUD.
func _on_replay_changed() -> void:
	_replaying = _replay.visible
	_place_score()
	if _replay.is_over_showing():
		_hint.visible = false
		_pause_button.visible = false
		_back_button.visible = false
		_run_coins.visible = false
		_score.visible = false


func is_practicing() -> bool:
	return _practicing


func practice_hud() -> PracticeHud:
	return _practice


## A practice run crashed: this try's points, Try again and Back to rooms.
func show_practice_over(points: int) -> void:
	_pause_button.visible = false
	_back_button.visible = false
	_run_coins.visible = false
	_score.visible = false
	_practice.show_over(points)


## The revive offer came up: it covers the room, so the running HUD goes.
func _on_revive_offer_shown() -> void:
	_pause_button.visible = false
	_back_button.visible = false
	_run_coins.visible = false
	_score.visible = false
	_hint.visible = false


func show_ready() -> void:
	revive_offer.visible = false
	_hint.visible = true
	_pause_button.visible = false
	_back_button.visible = true
	_back_button.tooltip_text = "Rooms" if _practicing else "Home"
	_run_coins.visible = false
	_score.visible = false
	pause_screen.visible = false
	countdown.visible = false
	game_over.hide_result()
	if _practicing:
		_practice.show_playing(false)
	if _replaying:
		# The replay taps by itself, and its exit sits in that corner.
		_hint.visible = false
		_back_button.visible = false
		_replay.show_playing()


func show_running() -> void:
	revive_offer.visible = false
	_hint.visible = false
	_back_button.visible = false
	# A replay has no pause; its exit sits where pause would be.
	_pause_button.visible = not _replaying
	_score.visible = true
	# Practice never pays coins, so no counter. A replay shows the coins the
	# recorded player picked up (they are not paid to the watcher).
	_run_coins.visible = not _practicing
	if _practicing:
		_practice.show_playing(false)


## Paused: the score, the sound circles, Resume, and Home (or Back to rooms in
## practice).
func show_paused(value: bool, music_on: bool = true, sfx_on: bool = true) -> void:
	pause_screen.visible = value
	_pause_button.visible = not value
	_back_button.visible = false
	_score.visible = not value
	_run_coins.visible = not value and not _practicing
	if value:
		pause_screen.show_state(_score.text, music_on, sfx_on, not _practicing)
	if _practicing:
		_practice.show_playing(value)


## `previous_best` shows as "was 87" on a new best; `rooms` is how many rooms
## this run cleared; `rank` today's place (0 while unknown); `revived_at` the
## score the run was revived at (-1: it wasn't); `season` the run's season
## (the seed code holds it).
func show_game_over(
	score: int,
	best: int,
	is_new_best: bool,
	coins_earned: int,
	previous_best: int = 0,
	rooms: int = 0,
	rank: int = 0,
	seed_value: int = -1,
	revived_at: int = -1,
	season: int = Seasons.NONE
) -> void:
	revive_offer.visible = false
	_pause_button.visible = false
	_back_button.visible = false
	_run_coins.visible = false
	_score.visible = false
	game_over.show_result(
		score,
		best,
		is_new_best,
		coins_earned,
		previous_best,
		rooms,
		rank,
		GameOverScreen.seed_text(seed_value, season) if seed_value >= 0 else "",
		revived_at,
		reduced_motion
	)


## Today's rank on the game-over stats and dock ("-" until it arrives).
func set_daily_rank(rank: int) -> void:
	game_over.set_daily_rank(rank)


func is_new_best_showing() -> bool:
	return game_over.is_new_best_showing()


## A short message on the room, e.g. the world's name after switching.
func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(_toast.hide)
