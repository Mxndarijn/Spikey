class_name SimState
extends RefCounted
## Complete state of one run. Plain integers only, so it can be hashed and copied.

enum DeathCause { NONE, CEILING, FLOOR, SPIKE_LEFT, SPIKE_RIGHT }

var tick := 0
var started := false
var alive := true
var death_cause: DeathCause = DeathCause.NONE

var x := SimConfig.BIRD_START_X
var y := SimConfig.BIRD_START_Y
var vx := SimConfig.SPEED_X
var vy := 0

var score := 0
var room_index := 0
var room_kind := 0

## Bitmasks of spiked slots on each side wall.
var left_spikes := 0
var right_spikes := 0


func copy() -> SimState:
	var s := SimState.new()
	s.tick = tick
	s.started = started
	s.alive = alive
	s.death_cause = death_cause
	s.x = x
	s.y = y
	s.vx = vx
	s.vy = vy
	s.score = score
	s.room_index = room_index
	s.room_kind = room_kind
	s.left_spikes = left_spikes
	s.right_spikes = right_spikes
	return s


func checksum() -> int:
	var h := SimHash.SEED
	for v: int in [
		tick,
		int(started),
		int(alive),
		death_cause,
		x,
		y,
		vx,
		vy,
		score,
		room_index,
		room_kind,
		left_spikes,
		right_spikes,
	]:
		h = SimHash.mix(h, v)
	return h
