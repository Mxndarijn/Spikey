class_name ReplayScrub
extends Node
## The replay scrubber's side of main: while a replay plays it builds the
## run's ReplayIndex a few ms a frame, and when the scrubber asks for a tick it
## jumps the run there (ReplayIndex.seek, RunController.seek) and snaps the
## views to it, with no sounds, flashes or countdown. Pausing goes through
## main's pause, which also stops a revive countdown.

## The index's share of a frame, and how many ticks it plays between clock checks.
const BUILD_USEC := 3000
const BUILD_CHUNK := 16

var index: ReplayIndex
## The end tick the replay's run file claims (0 = unknown): the timeline's
## length until the index has played the whole run.
var end_tick := 0
## Off for filmed runs (RunRender): the video shows the run, not the controls.
var shown := true

var _run: RunController
var _hud: Hud
var _look: RunLook
var _room: RoomView
var _hazards: HazardLayer
var _bird: BirdView
var _night: NightView
var _coin: CoinView
var _trail: TrailView
var _crash: CrashView
## main._set_paused: pause or play on at once, any countdown stopped.
var _set_paused: Callable


func setup(run: RunController, hud: Hud, look: RunLook, views: Array, set_paused: Callable) -> void:
	_run = run
	_hud = hud
	_look = look
	_room = views[0]
	_hazards = views[1]
	_bird = views[2]
	_night = views[3]
	_coin = views[4]
	_trail = views[5]
	_crash = views[6]
	_set_paused = set_paused
	var scrubber := hud.replay_hud().scrubber()
	scrubber.seek_requested.connect(seek)
	scrubber.paused_changed.connect(func(value: bool) -> void: _set_paused.call(value))


## A replay starts, or starts over (the same run keeps its index).
func start(driver: ReplayDriver) -> void:
	if not shown:
		stop()
		return
	if index == null or index.seed_value != driver.seed_value or index.taps != driver.taps:
		index = ReplayIndex.of_driver(driver, end_tick)
	var scrubber := _hud.replay_hud().scrubber()
	scrubber.reduced_motion = _hud.reduced_motion
	scrubber.bind(index, _run)


func stop() -> void:
	index = null
	_hud.replay_hud().scrubber().unbind()


func _process(_delta: float) -> void:
	if index == null or index.is_done():
		return
	var until := Time.get_ticks_usec() + BUILD_USEC
	while Time.get_ticks_usec() < until and not index.build(BUILD_CHUNK):
		pass


## The run jumps to `tick` and the room shows it as it stands there.
func seek(tick: int) -> void:
	if index == null or _run.driver == null:
		return
	var was_over := _run.sim.is_over()
	_run.seek(index.seek(tick))
	_set_paused.call(_run.paused)
	_crash.clear()
	_room.bind(_run, _look.theme)
	_room.snap()
	_hazards.bind(_run, _look.theme)
	_bird.bind(_run, _look.character)
	_night.bind(_run, _room, _bird)
	_coin.bind(_run)
	_trail.bind(_bird, _look.trail_style, _look.theme)
	_hud.set_run_coins(_run.sim.state.coins, true)
	if was_over:
		# Back from the end screen ("Noor scored 31") into the run.
		_hud.replay_hud().show_playing()
	if _run.sim.state.started:
		_trail.start()
		_hud.show_running()
	else:
		_hud.show_ready()
