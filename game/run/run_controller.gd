class_name RunController
extends Node
## Drives one run: steps the deterministic sim at a fixed 60 Hz, records taps
## for the replay and turns sim events into signals. The only node that
## touches GameSim.

signal run_started
signal flapped
signal bounced
signal scored(score: int)
signal room_changed(room_index: int)
signal died(replay: Replay)
signal coin_spawned
signal coin_collected(total: int)
## An exit portal opened (every 10 points; two at a fork).
signal exit_opened
## The next exit was planned one point early and shows as a ghost.
signal exit_previewed

var sim: GameSim
## State before the last tick, for smooth interpolation in the views.
var prev_state: SimState
var paused := false
## Set while a recorded run plays back: taps come from it, never from input.
var driver: ReplayDriver

var _taps := PackedInt32Array()
var _tap_pending := false


## `season` (Seasons.*) decides which seasonal rooms can appear; it is stored
## in the replay. `practice_room` (a RoomCatalog index) makes a practice run
## that repeats that one room; -1 is a real run.
func new_run(seed_value: int, season: int = Seasons.NONE, practice_room: int = -1) -> void:
	sim = GameSim.new(seed_value, season, practice_room)
	prev_state = sim.state.copy()
	_taps.clear()
	_tap_pending = false
	paused = false
	driver = null


## Plays a recorded run back from its first tick (see ReplayDriver).
func new_replay(p_driver: ReplayDriver) -> void:
	new_run(p_driver.seed_value, p_driver.season)
	p_driver.restart()
	driver = p_driver


func request_tap() -> void:
	if sim != null and not paused and not sim.is_over() and driver == null:
		_tap_pending = true


func set_paused(value: bool) -> void:
	paused = value
	_tap_pending = false


func is_running() -> bool:
	return sim != null and sim.state.started and not sim.is_over()


func _physics_process(_delta: float) -> void:
	if sim == null or paused or sim.is_over():
		return
	advance()


## One sim tick with the pending tap (or the replay's tap for this tick).
func advance() -> void:
	var tap := _tap_pending
	_tap_pending = false
	if driver != null:
		tap = driver.tap_at(sim.state.tick)
	if tap:
		_taps.append(sim.state.tick)
	prev_state = sim.state.copy()
	sim.step(tap)
	_dispatch_events()


func _dispatch_events() -> void:
	for e in sim.events:
		match e:
			GameSim.Event.START:
				run_started.emit()
			GameSim.Event.FLAP:
				flapped.emit()
			GameSim.Event.BOUNCE:
				bounced.emit()
			GameSim.Event.SCORE:
				scored.emit(sim.state.score)
			GameSim.Event.ROOM_CHANGE:
				room_changed.emit(sim.state.room_index)
			GameSim.Event.EXIT_OPEN:
				exit_opened.emit()
			GameSim.Event.EXIT_PREVIEW:
				exit_previewed.emit()
			GameSim.Event.COIN_SPAWN:
				coin_spawned.emit()
			GameSim.Event.COIN:
				coin_collected.emit(sim.state.coins)
			GameSim.Event.DEATH:
				died.emit(Replay.from_sim(sim, _taps.duplicate()))
