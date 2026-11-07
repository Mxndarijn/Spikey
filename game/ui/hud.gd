class_name Hud
extends CanvasLayer
## Overlay UI: pause button, tap hint, pause overlay and game-over panel.
## Taps outside the pause button pass through to Main as flaps.

signal pause_pressed

@onready var _pause_button: Button = %PauseButton
@onready var _hint: Label = %Hint
@onready var _paused: Control = %PausedOverlay
@onready var _game_over: Control = %GameOverPanel
@onready var _final_score: Label = %FinalScore
@onready var _best_score: Label = %BestScore


func _ready() -> void:
	_pause_button.pressed.connect(pause_pressed.emit)
	show_ready()


func show_ready() -> void:
	_hint.text = "Tap to flap"
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


func show_game_over(score: int, best: int) -> void:
	_pause_button.visible = false
	_final_score.text = str(score)
	_best_score.text = "Best %d" % best
	_game_over.visible = true
