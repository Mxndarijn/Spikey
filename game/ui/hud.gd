class_name Hud
extends CanvasLayer
## Overlay UI: pause button, tap hint, world toast, pause overlay and game-over
## panel, styled by UiTheme (the design kit). Taps outside buttons pass through
## to Main as flaps.

signal pause_pressed
signal play_again_pressed

const TOAST_SECONDS := 1.2

var _toast_tween: Tween

@onready var _root: Control = $Root
@onready var _pause_button: Button = %PauseButton
@onready var _hint: Label = %Hint
@onready var _toast: Label = %Toast
@onready var _paused: ColorRect = %PausedOverlay
@onready var _game_over: ColorRect = %GameOver
@onready var _final_score: Label = %FinalScore
@onready var _new_best: Label = %NewBest
@onready var _best_score: Label = %BestScore
@onready var _play_again: Button = %PlayAgain


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	_paused.color = UiTokens.SCRIM
	_game_over.color = UiTokens.SCRIM
	_pause_button.pressed.connect(pause_pressed.emit)
	_play_again.pressed.connect(play_again_pressed.emit)
	show_ready()


func show_ready() -> void:
	_hint.visible = true
	_pause_button.visible = false
	_paused.visible = false
	_game_over.visible = false


func show_running() -> void:
	_hint.visible = false
	_pause_button.visible = true


func show_paused(value: bool) -> void:
	_paused.visible = value
	_pause_button.visible = not value


func show_game_over(score: int, best: int, is_new_best: bool) -> void:
	_pause_button.visible = false
	_final_score.text = str(score)
	_best_score.text = "Best %d" % best
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
