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
## Exit portal(s): open on `exit_side` (0 left, 1 right; always
## SimConfig.EXIT_WALL). `exit_a_y` is always used; `exit_b_y` only at a fork.
## Kinds are ExitKind values.
## `exit_preview`: the next exit is already planned (one point early) and
## shown as a ghost on `exit_side`; it opens there, at the same height(s),
## on the next point. Until then it is not a way through.
var exit_open := false
var exit_preview := false
var exit_side := 0
var exit_a_y := 0
var exit_a_kind := 0
var exit_b_y := 0
var exit_b_kind := 0
## The exit kind taken into this room: CALM or WILD in the room behind a fork,
## NORMAL everywhere else.
var route := 0
## Boss rooms met this run: bit i is the i-th boss (RoomCatalog.bosses()).
var bosses_met := 0
## Where the last coin was collected (the view flies it from there).
var pickup_x := 0
var pickup_y := 0
## Ticks the bird still waits in the portal it just came out of (the new
## room is frozen meanwhile, so the player can read it before flying on).
var arrival_hold := 0
## Revives used this run (GameSim.revive), at most SimConfig.MAX_REVIVES.
var revives := 0
## Where generation thinks the bird is: it never reads the bird's real height,
## so every player of a seed gets the same rooms, variants, spikes and hazards
## (GameSim._set_anchor). Out of a portal it is the centre of the exit taken
## (the bird is within EXIT_FIT of it); at a bounce, the point of the free run
## on that wall nearest the last anchor (a bird that follows the anchors
## always has a fair way on).
var anchor_y := SimConfig.BIRD_START_Y
## The room's exits, picked when the room starts (ExitPlanner.plan_room): for
## each wall (0 = left), the first exit's height and kind and, at a fork, the
## second exit's height (its kind is the other one).
var plan_a_y_left := 0
var plan_a_kind_left := 0
var plan_b_y_left := 0
var plan_a_y_right := 0
var plan_a_kind_right := 0
var plan_b_y_right := 0
## The exit score the plan is for.
var plan_at := 0


func copy() -> SimState:
	var s := SimState.new()
	s.assign(self)
	return s


## Sets every field to `o`'s (a revive puts the entry state back in place, so
## whoever holds this state sees it).
func assign(o: SimState) -> void:
	tick = o.tick
	started = o.started
	alive = o.alive
	death_cause = o.death_cause
	x = o.x
	y = o.y
	vx = o.vx
	vy = o.vy
	score = o.score
	room_index = o.room_index
	room_kind = o.room_kind
	left_spikes = o.left_spikes
	right_spikes = o.right_spikes
	coin_active = o.coin_active
	coin_x = o.coin_x
	coin_y = o.coin_y
	coins = o.coins
	flaps = o.flaps
	exit_open = o.exit_open
	exit_preview = o.exit_preview
	exit_side = o.exit_side
	exit_a_y = o.exit_a_y
	exit_a_kind = o.exit_a_kind
	exit_b_y = o.exit_b_y
	exit_b_kind = o.exit_b_kind
	route = o.route
	bosses_met = o.bosses_met
	pickup_x = o.pickup_x
	pickup_y = o.pickup_y
	arrival_hold = o.arrival_hold
	revives = o.revives
	anchor_y = o.anchor_y
	plan_a_y_left = o.plan_a_y_left
	plan_a_kind_left = o.plan_a_kind_left
	plan_b_y_left = o.plan_b_y_left
	plan_a_y_right = o.plan_a_y_right
	plan_a_kind_right = o.plan_a_kind_right
	plan_b_y_right = o.plan_b_y_right
	plan_at = o.plan_at


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
		arrival_hold,
		int(exit_preview),
		revives,
		anchor_y,
		plan_a_y_left,
		plan_a_kind_left,
		plan_b_y_left,
		plan_a_y_right,
		plan_a_kind_right,
		plan_b_y_right,
		plan_at,
		bosses_met,
	]:
		h = SimHash.mix(h, v)
	return h
