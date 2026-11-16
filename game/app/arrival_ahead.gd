class_name ArrivalAhead
extends RefCounted
## Works out the next portal arrival's check ahead, on a worker thread, while
## the bird flies to the open exit, and hands it to the sim before the portal
## (ArrivalPlan). Without it the portal tick
## plays up to hundreds of room layouts on the main thread (ArrivalCheck):
## 30 ms to 2 s on a desktop, seconds on a phone, a frozen frame. Speed only:
## the sim takes a plan only when its key is the arrival's exact inputs, and
## checks as before when not, so nothing in the run changes either way.
## RunController calls before_step and after_step around every sim step.

## Wait for a job still running when the bird is this many sim steps from the
## exit wall (times the room's steps per tick): the wait is the job's rest,
## shorter than the whole check the portal tick would play itself.
const WAIT_STEPS := 3

static var _warmed := false

## The worker task, or -1.
var _task := -1
## The sim the running or last job was for (its instance id).
var _for := 0
## What the last job was started from (_trigger), so a job starts again only
## when something the arrival reads may have changed.
var _started_from: Array = []
## The running job's plans: the worker fills it, the main thread reads it once
## the task is done (a fresh array per job, held by the task too).
var _result: Array = []


## SimCopy works out each sim class's fields on first use; doing every sim
## script here, on the main thread, means worker threads only ever read that
## table.
static func warm() -> void:
	if _warmed:
		return
	_warmed = true
	_warm_dir("res://sim")


static func _warm_dir(dir: String) -> void:
	for name in ResourceLoader.list_directory(dir):
		if name.ends_with("/"):
			_warm_dir(dir.path_join(name.trim_suffix("/")))
		elif name.ends_with(".gd"):
			var script := load(dir.path_join(name)) as Script
			if script != null:
				SimCopy.warm(script)


## Before sim.step: if the bird is about to reach the open exit while a job
## for it still runs, waits for that job and hands its plan over.
func before_step(sim: GameSim) -> void:
	if _task < 0 or not sim.state.exit_open:
		return
	var near := WAIT_STEPS * maxi(1, sim.room.steps_this_tick())
	if sim.steps_to_wall(sim.state.exit_side) <= near:
		_finish(sim)


## After sim.step: hands over a finished job's plan, and starts a job when an
## exit is open and the state changed since the last one.
func after_step(sim: GameSim) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish(sim)
	if _task >= 0 or sim.is_over() or not sim.state.exit_open:
		return
	var from := _trigger(sim)
	if sim.get_instance_id() == _for and from == _started_from:
		return
	warm()
	_for = sim.get_instance_id()
	_started_from = from
	var s := sim.state
	var exits: Array = [[s.exit_a_kind, s.exit_a_y]]
	if s.exit_b_kind != SimState.ExitKind.NORMAL:
		exits.append([s.exit_b_kind, s.exit_b_y])
	_result = []
	_task = WorkerThreadPool.add_task(
		ArrivalAhead._work.bind(SimCopy.copy(sim), s.exit_side, exits, _result)
	)


## Waits for a running job (a run that ends, a scene that closes).
func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_result = []


## Whether a job is running (tests).
func busy() -> bool:
	return _task >= 0


## Waits for a running job and hands its plan to `sim` (tools).
func finish(sim: GameSim) -> void:
	if _task >= 0:
		_finish(sim)


func _finish(sim: GameSim) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if sim.get_instance_id() == _for and not _result.is_empty():
		ArrivalPlan.offer(sim, _result)
	_result = []


## Worker thread: one plan per open exit (a fork has two), each on its own
## copy, into `out`. Static and on its own data: it never touches the real sim.
static func _work(copy: GameSim, side: int, exits: Array, out: Array) -> void:
	for i in exits.size():
		var c := copy if i == exits.size() - 1 else SimCopy.copy(copy)
		out.append(ArrivalPlan.plan(c, side, exits[i][0], exits[i][1]))


## What a job starts from: the state the arrival key reads, and the room
## seed. Anything else that changes only makes the sim miss the plan.
static func _trigger(sim: GameSim) -> Array:
	var out := sim.state.arrival_key()
	out.append(sim.room.rng_seed)
	return out
