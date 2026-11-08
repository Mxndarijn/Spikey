class_name Hud
extends CanvasLayer
## Overlay UI in the Sticker Pop style: a white sticker pause button, the tap
## hint, world toast, pause overlay and the game-over screen (a white sticker
## panel with the score, the medal tilted over its corner on a new best),
## styled by UiTheme (the design kit). Taps outside buttons pass through
## to Main as flaps.

signal pause_pressed
signal play_again_pressed
signal home_pressed
## Practice: restart the room, or leave for the Rooms screen.
signal restart_pressed
signal rooms_pressed

const TOAST_SECONDS := 1.2
const COIN_ICON := preload("res://assets/ui/coin.svg")
## A collected coin flies from the room into the coin counter (top right).
const FLY_TIME := 0.5
const FLY_SIZE := 28.0
## How high the flight curves above the straight line, in px.
const FLY_ARC := 60.0

var _toast_tween: Tween
## Coins collected in this run, top right while playing.
var _run_coins := CoinPill.new()
var _coin_tween: Tween
## Banner, restart and crash screen for practice runs (hidden in real runs).
var _practice := PracticeHud.new()
var _practicing := false

@onready var _root: Control = $Root
@onready var _pause_button: Button = %PauseButton
@onready var _hint: Control = %Hint
@onready var _toast: Label = %Toast
@onready var _paused: ColorRect = %PausedOverlay
@onready var _game_over: ColorRect = %GameOver
@onready var _final_score: Label = %FinalScore
@onready var _new_best: Control = %NewBest
@onready var _best_score: Label = %BestScore
@onready var _coins_earned: Label = %CoinsEarned
@onready var _play_again: Button = %PlayAgain
@onready var _home: Button = %Home


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	_paused.color = UiTokens.SCRIM
	_game_over.color = UiTokens.SCRIM
	# Play again drops 6px with a bolder outline, like the board's big buttons.
	var gold := UiTheme.sticker(UiTokens.ACTION, UiTokens.RADIUS_PILL, Vector2(0, 6), 8, 4)
	for state in ["normal", "hover"]:
		_play_again.add_theme_stylebox_override(state, gold)
	for state in ["pressed", "hover_pressed"]:
		_play_again.add_theme_stylebox_override(state, gold.pressed())
	_pause_button.pressed.connect(pause_pressed.emit)
	_play_again.pressed.connect(play_again_pressed.emit)
	_home.pressed.connect(home_pressed.emit)
	_root.add_child(_run_coins)
	# Pinned to the top-right corner, growing leftward as the number gets longer.
	_run_coins.anchor_left = 1.0
	_run_coins.anchor_right = 1.0
	_run_coins.offset_left = -UiTokens.SPACE_4
	_run_coins.offset_right = -UiTokens.SPACE_4
	_run_coins.offset_top = UiTokens.SPACE_7
	_run_coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_run_coins.set_amount(0)
	_root.add_child(_practice)
	_practice.restart_pressed.connect(restart_pressed.emit)
	_practice.rooms_pressed.connect(rooms_pressed.emit)
	show_ready()


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
	var start := from - coin.size / 2.0
	var end := _counter_target() - coin.size / 2.0
	var bend := (start + end) / 2.0 + Vector2(0, -FLY_ARC)
	coin.position = start
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_method(_fly_step.bind(coin, start, bend, end), 0.0, 1.0, FLY_TIME)
	t.tween_callback(_land_coin.bind(coin, total))


## Where flying coins land: the coin icon inside the counter.
func _counter_target() -> Vector2:
	var r := _run_coins.get_global_rect()
	return Vector2(r.position.x + 16.0, r.position.y + r.size.y / 2.0)


static func _fly_step(t: float, coin: Control, start: Vector2, bend: Vector2, end: Vector2) -> void:
	# A curve through `bend`, shrinking a little as it reaches the counter.
	coin.position = start.lerp(bend, t).lerp(bend.lerp(end, t), t)
	coin.scale = Vector2.ONE * lerpf(1.0, 0.7, t)


func _land_coin(coin: Control, total: int) -> void:
	coin.queue_free()
	set_run_coins(total)


## Coins still on their way to the counter.
func flying_coins() -> int:
	var n := 0
	for c in _root.get_children():
		if (
			c is TextureRect
			and (c as TextureRect).texture == COIN_ICON
			and not c.is_queued_for_deletion()
		):
			n += 1
	return n


func run_coins_text() -> String:
	return _run_coins.amount_text()


## Hides everything (a menu screen is showing).
func show_menu() -> void:
	set_practice("")
	show_ready()
	_hint.visible = false


## Practice mode for this room name; an empty name goes back to real runs.
func set_practice(room_name: String) -> void:
	_practicing = not room_name.is_empty()
	_practice.set_room(room_name)


func is_practicing() -> bool:
	return _practicing


func practice_hud() -> PracticeHud:
	return _practice


## A practice run crashed: this try's points, Try again and Back to rooms.
func show_practice_over(points: int) -> void:
	_pause_button.visible = false
	_run_coins.visible = false
	_practice.show_over(points)


func show_ready() -> void:
	_hint.visible = true
	_pause_button.visible = false
	_run_coins.visible = false
	_paused.visible = false
	_game_over.visible = false
	if _practicing:
		_practice.show_playing(false)


func show_running() -> void:
	_hint.visible = false
	_pause_button.visible = true
	# Practice never pays coins, so no counter.
	_run_coins.visible = not _practicing
	if _practicing:
		_practice.show_playing(false)


func show_paused(value: bool) -> void:
	_paused.visible = value
	_pause_button.visible = not value
	if _practicing:
		_practice.show_playing(value)


## `previous_best` shows as "Best 92, was 87" on a new best.
func show_game_over(
	score: int, best: int, is_new_best: bool, coins_earned: int, previous_best: int = 0
) -> void:
	_pause_button.visible = false
	_run_coins.visible = false
	_final_score.text = str(score)
	_best_score.text = best_text(best, is_new_best, previous_best)
	_coins_earned.text = "+%d coins" % coins_earned
	_new_best.visible = is_new_best
	_game_over.visible = true


## A short message on the sky, e.g. the world's name after switching.
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


static func best_text(best: int, is_new_best: bool, previous_best: int) -> String:
	if is_new_best and previous_best > 0:
		return "Best %d, was %d" % [best, previous_best]
	return "Best %d" % best
