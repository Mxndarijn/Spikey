class_name GameSim
extends RefCounted
## The deterministic game. One call to step() is one 1/60 s tick.
## Same seed + same tap ticks = same run, on every device and on the server.

enum Event { START, FLAP, BOUNCE, SCORE, ROOM_CHANGE, DEATH }

var seed_value: int
var state := SimState.new()
## Events produced by the last step(). Read them, don't keep the array.
var events: Array[int] = []

var _rng: SimRng


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_rng = SimRng.new(p_seed)
	state.room_kind = _rng.next_below(RoomRules.kind_count())


func is_over() -> bool:
	return not state.alive


func step(tap: bool) -> void:
	events.clear()
	if not state.alive:
		return

	if tap:
		if not state.started:
			state.started = true
			events.append(Event.START)
		state.vy = SimConfig.FLAP_VY
		events.append(Event.FLAP)

	if state.started:
		_move()
		_check_spikes()
		if state.alive:
			_check_walls()
			_check_ceiling_floor()

	state.tick += 1


## Full checksum of state and RNG, for golden replays and desync detection.
func checksum() -> int:
	return SimHash.mix(state.checksum(), _rng.state_checksum())


func _move() -> void:
	state.vy = mini(state.vy + SimConfig.GRAVITY, SimConfig.MAX_FALL_VY)
	state.x += state.vx
	state.y += state.vy


func _check_spikes() -> void:
	var r := SimConfig.BIRD_RADIUS
	if (
		state.x - r <= SimConfig.SPIKE_DEPTH
		and _hits_wall(state.left_spikes, 0, SimConfig.SPIKE_DEPTH)
	):
		_die(SimState.DeathCause.SPIKE_LEFT)
	elif (
		state.x + r >= SimConfig.WORLD_W - SimConfig.SPIKE_DEPTH
		and _hits_wall(
			state.right_spikes, SimConfig.WORLD_W, SimConfig.WORLD_W - SimConfig.SPIKE_DEPTH
		)
	):
		_die(SimState.DeathCause.SPIKE_RIGHT)


func _hits_wall(mask: int, base_x: int, tip_x: int) -> bool:
	if mask == 0:
		return false
	var hb := SimConfig.SPIKE_HALF_BASE
	for slot in SimConfig.SLOT_COUNT:
		if not RoomRules.has_slot(mask, slot):
			continue
		var cy := SimConfig.slot_center_y(slot)
		if absi(state.y - cy) > hb + SimConfig.BIRD_RADIUS:
			continue
		if SimMath.circle_hits_triangle(
			state.x, state.y, SimConfig.BIRD_RADIUS, base_x, cy - hb, base_x, cy + hb, tip_x, cy
		):
			return true
	return false


func _check_walls() -> void:
	var r := SimConfig.BIRD_RADIUS
	if state.vx > 0 and state.x + r >= SimConfig.WORLD_W:
		state.x = 2 * (SimConfig.WORLD_W - r) - state.x
		state.vx = -SimConfig.SPEED_X
		state.right_spikes = 0
		_score()
		state.left_spikes = RoomRules.generate_wall(_rng, state.score, state.room_kind)
	elif state.vx < 0 and state.x - r <= 0:
		state.x = 2 * r - state.x
		state.vx = SimConfig.SPEED_X
		state.left_spikes = 0
		_score()
		state.right_spikes = RoomRules.generate_wall(_rng, state.score, state.room_kind)


func _score() -> void:
	state.score += 1
	events.append(Event.BOUNCE)
	events.append(Event.SCORE)
	if state.score % SimConfig.POINTS_PER_ROOM == 0:
		state.room_index += 1
		state.room_kind = RoomRules.next_kind(_rng, state.room_kind)
		events.append(Event.ROOM_CHANGE)


func _check_ceiling_floor() -> void:
	var r := SimConfig.BIRD_RADIUS
	if state.y - r <= SimConfig.KILL_TOP:
		_die(SimState.DeathCause.CEILING)
	elif state.y + r >= SimConfig.KILL_BOTTOM:
		_die(SimState.DeathCause.FLOOR)


func _die(cause: SimState.DeathCause) -> void:
	state.alive = false
	state.death_cause = cause
	events.append(Event.DEATH)
