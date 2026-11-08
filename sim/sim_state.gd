class_name SimState
extends RefCounted
## Complete state of one run. Plain integers only, so it can be hashed and copied.

enum DeathCause { NONE, CEILING, FLOOR, SPIKE_LEFT, SPIKE_RIGHT, HAZARD }
## A normal exit, or one of the two at a fork.
enum ExitKind { NORMAL, CALM, WILD }

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
## Index of the current room in RoomCatalog.all().
var room_kind := 0

## Bitmasks of spiked slots on each side wall.
var left_spikes := 0
var right_spikes := 0

## The one coin in the room, if any, and how many this run collected.
var coin_active := false
var coin_x := 0
var coin_y := 0
var coins := 0
## Taps this run (for achievements).
var flaps := 0
## Exit portal(s): open on `exit_side` (0 left, 1 right). `exit_a_y` is always
## used; `exit_b_y` only at a fork. Kinds are ExitKind values.
var exit_open := false
var exit_side := 0
var exit_a_y := 0
var exit_a_kind := 0
var exit_b_y := 0
var exit_b_kind := 0
## The route picked at the last fork (ExitKind.CALM or WILD), NORMAL before one.
var route := 0
## Where the last coin was collected (the view flies it from there).
var pickup_x := 0
var pickup_y := 0


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
	s.coin_active = coin_active
	s.coin_x = coin_x
	s.coin_y = coin_y
	s.coins = coins
	s.flaps = flaps
	s.exit_open = exit_open
	s.exit_side = exit_side
	s.exit_a_y = exit_a_y
	s.exit_a_kind = exit_a_kind
	s.exit_b_y = exit_b_y
	s.exit_b_kind = exit_b_kind
	s.route = route
	s.pickup_x = pickup_x
	s.pickup_y = pickup_y
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
		int(coin_active),
		coin_x,
		coin_y,
		coins,
		flaps,
		int(exit_open),
		exit_side,
		exit_a_y,
		exit_a_kind,
		exit_b_y,
		exit_b_kind,
		route,
	]:
		h = SimHash.mix(h, v)
	return h
