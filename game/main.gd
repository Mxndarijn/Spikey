extends Node2D
## Phase 1 run screen: wires input, RunController, views and HUD together.

const RESTART_DELAY_MS := 450

var _best := 0
var _game_over_at_ms := -1

@onready var _run: RunController = $RunController
@onready var _room: RoomView = $RoomView
@onready var _trail: TrailView = $TrailView
@onready var _bird: BirdView = $BirdView
@onready var _hud: Hud = $Hud


func _ready() -> void:
	_run.run_started.connect(_hud.show_running)
	_run.run_started.connect(_trail.start)
	_run.flapped.connect(_bird.on_flap)
	_run.bounced.connect(_bird.on_bounce)
	_run.room_changed.connect(_room.on_room_changed)
	_run.died.connect(_on_died)
	_hud.pause_pressed.connect(_toggle_pause)
	_new_run()


func _new_run() -> void:
	# Local seed for now; Phase 3 asks the server for a one-time seed.
	_run.new_run(randi())
	_room.bind(_run)
	_bird.bind(_run)
	# Later: the trail the player equipped in the shop.
	_trail.bind(_bird, TrailStyle.sunset_ribbon())
	_hud.show_ready()
	_game_over_at_ms = -1


func _unhandled_input(event: InputEvent) -> void:
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
		if Time.get_ticks_msec() - _game_over_at_ms >= RESTART_DELAY_MS:
			_new_run()
	else:
		_run.request_tap()


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


func _on_died(replay: Replay) -> void:
	_bird.on_death()
	_trail.stop()
	_best = maxi(_best, replay.score)
	_game_over_at_ms = Time.get_ticks_msec()
	_hud.show_game_over(replay.score, _best)


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
