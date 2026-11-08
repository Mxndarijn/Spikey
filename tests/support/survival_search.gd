class_name SurvivalSearch
extends RefCounted
## "Can anyone survive this?" Keeps many copies of the sim side by side and, every
## tick, tries both tap and wait on each one. Copies that die are dropped; the rest
## are thinned out to one per height-and-speed bucket so the search stays wide
## instead of following one lucky line. It knows the future exactly (it steps real
## copies). Thinning can drop a narrow way through, so when every copy dies it
## tries again with finer buckets (LEVELS); only if the finest pass dies too is
## the room or the moment impossible. Test/tool code only (slow).

## Only tap a copy that is not already rising fast (a second tap right after the
## first changes almost nothing and doubles the work).
const TAP_BELOW_VY := SimConfig.FLAP_VY / 2
## Bucket sizes, coarse (fast) to fine (slow): [height, speed step, speed
## buckets]. Speed is counted from a fresh flap toward gravity.
const LEVELS: Array = [
	[5 * SimConfig.SUB, -SimConfig.FLAP_VY / 2, 5],
	[3 * SimConfig.SUB, -SimConfig.FLAP_VY / 4, 16],
	[2 * SimConfig.SUB, -SimConfig.FLAP_VY / 8, 40],
]

## How far the last search got.
var ticks_survived := 0
## Most copies alive at once.
var peak_width := 0
## The best surviving copy (null when all died).
var best: GameSim
## The taps that got `best` there (1 = tap), from the start of the search.
var best_inputs := PackedByteArray()
## Room kinds of the last living copies (where the search died out).
var last_rooms: Array[int] = []
## What killed those last copies: cause name -> how many.
var last_deaths := {}
## The LEVELS index of the last pass run.
var level := 0
## The finest LEVELS index to try (0 = coarse only).
var max_level := LEVELS.size() - 1

var _bucket_h := 0
var _bucket_vy := 0
var _speed_buckets := 0


## Runs `sim` (a copy is made; `sim` is not changed) for `ticks` steps or until
## no copy is alive. Returns true when some copy lived through all of them.
## Starts coarse and retries finer when every copy dies.
func run(sim: GameSim, ticks: int) -> bool:
	for i in max_level + 1:
		level = i
		_bucket_h = LEVELS[i][0]
		_bucket_vy = LEVELS[i][1]
		_speed_buckets = LEVELS[i][2]
		if _run_once(sim, ticks):
			return true
	return false


func _run_once(sim: GameSim, ticks: int) -> bool:
	var frontier: Array = [[SimClone.copy(sim), PackedByteArray()]]
	ticks_survived = 0
	peak_width = 1
	best = null
	best_inputs = PackedByteArray()
	for t in ticks:
		var next := {}
		for e: Array in frontier:
			var s: GameSim = e[0]
			var inputs: PackedByteArray = e[1]
			var grav := s.room.def.gravity_sign
			if s.state.vy * grav > TAP_BELOW_VY or not s.state.started:
				var c := SimClone.copy(s)
				c.step(true)
				var tapped := inputs.duplicate()
				tapped.append(1)
				_keep(next, c, tapped)
			# A bird that has not started just waits and would "survive"
			# forever: every copy starts on its first step.
			if not s.state.started:
				continue
			s.step(false)
			inputs.append(0)
			_keep(next, s, inputs)
		if next.is_empty():
			last_rooms.clear()
			last_deaths.clear()
			for e: Array in frontier:
				var st := (e[0] as GameSim).state
				if st.room_kind not in last_rooms:
					last_rooms.append(st.room_kind)
				var why: String = SimState.DeathCause.keys()[st.death_cause]
				last_deaths[why] = int(last_deaths.get(why, 0)) + 1
			return false
		frontier = next.values()
		peak_width = maxi(peak_width, frontier.size())
		ticks_survived = t + 1
	var top: Array = frontier[0]
	for e: Array in frontier:
		if _better(e[0], top[0]):
			top = e
	best = top[0]
	best_inputs = top[1]
	return true


func _keep(next: Dictionary, s: GameSim, inputs: PackedByteArray) -> void:
	if s.is_over():
		return
	var st := s.state
	# Speed along gravity, so flipped rooms bucket the same way: negative is a
	# fresh flap, then four bands as gravity takes over.
	var along := st.vy * s.room.def.gravity_sign - SimConfig.FLAP_VY
	var speed := clampi(along / _bucket_vy, 0, _speed_buckets - 1)
	var key := (st.y / _bucket_h) * _speed_buckets + speed
	if not next.has(key) or _better(s, next[key][0]):
		next[key] = [s, inputs]


## Further along wins: more rooms, then more points, then more coins.
static func _better(a: GameSim, b: GameSim) -> bool:
	if a.state.room_index != b.state.room_index:
		return a.state.room_index > b.state.room_index
	if a.state.score != b.state.score:
		return a.state.score > b.state.score
	return a.state.coins > b.state.coins
