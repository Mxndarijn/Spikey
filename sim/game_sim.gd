class_name GameSim
extends RefCounted
## The deterministic game. One call to step() is one 1/60 s tick.
## Same seed + same season + same tap ticks = same run, on every device and on
## the server.

enum Event {
	START,
	FLAP,
	BOUNCE,
	SCORE,
	ROOM_CHANGE,
	DEATH,
	COIN_SPAWN,
	COIN,
	EXIT_OPEN,
	EXIT_PREVIEW,
	REVIVE
}

## How hard a bumper shoves the bird (vertical speed, sub-units per step): a bit
## more than a flap, tied to it so the shove stays survivable if the flap changes.
const BUMP_VY := -SimConfig.FLAP_VY * 6 / 5
## The start lane (see blocks_start_lane): tall enough to hover in (one hop
## is about 60 px plus the bird), reaching most of the way across.
const START_LANE_H := 100 * SimConfig.SUB
const START_LANE_BELOW := 12 * SimConfig.SUB
const START_LANE_W := 150 * SimConfig.SUB
## Steps of the start path (one flap up to its peak and a little after).
const START_PATH := 32
## How high one flap lifts the bird (about 60 px).
const FIRST_HOP := SimConfig.FLAP_VY * SimConfig.FLAP_VY / (2 * SimConfig.GRAVITY)
## Practice starts this far from the left wall.
const PRACTICE_START_GAP := 40 * SimConfig.SUB

var seed_value: int
var season: int
## Practice: the room kind (RoomCatalog index) this run repeats, or -1 for a
## real run. Practice starts at the room's from_score, so its walls are as
## busy as in a real run, and it never picks another room. Real runs are
## unchanged by this (no extra RNG draws), so replays and goldens stay valid.
var practice_room := -1
var state := SimState.new()
## The room being played: its hazards and wall rules.
var room := RoomRuntime.new()
## Events produced by the last step(). Read them, don't keep the array.
var events: Array[int] = []

var _rng: SimRng


func _init(p_seed: int, p_season: int = Seasons.NONE, p_practice_room: int = -1) -> void:
	seed_value = p_seed
	season = p_season
	_rng = SimRng.new(p_seed)
	if p_practice_room >= 0 and p_practice_room < RoomCatalog.all().size():
		practice_room = p_practice_room
		state.score = RoomCatalog.all()[practice_room].from_score
		# Start at the left wall facing in, as when arriving through an exit,
		# so the bird never starts inside a hazard in the middle of the room.
		state.x = PRACTICE_START_GAP
		_enter_room(practice_room)
	else:
		_enter_room(RoomCatalog.first_index())


## Where the bird will be soon after the room starts: its height, or, before
## the first tap (which is a flap), half a hop higher. Hazards that line a
## gap up with the bird use this.
func entry_y() -> int:
	if state.started:
		return state.y
	return state.y - FIRST_HOP / 2 * room.def.gravity_sign


## Before the first tap: where the bird goes in its first START_PATH steps
## (the first tap is a flap, and the player can't steer until it peaks), as
## x, y pairs. Empty once the bird is flying. Hazards placed at room start
## keep off this path, so a room never kills on its first, forced hop.
func start_path() -> PackedInt32Array:
	var out := PackedInt32Array()
	if state.started:
		return out
	var g := SimConfig.GRAVITY * room.def.gravity_sign
	var x := state.x
	var y := state.y
	var vy := SimConfig.FLAP_VY * room.def.gravity_sign
	for i in START_PATH:
		vy = clampi(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)
		x += state.vx
		y += vy
		out.append(x)
		out.append(y)
	return out


## Whether a box (corners, sub-units) comes within `margin` of the bird's
## start path.
func start_path_hits_rect(x0: int, y0: int, x1: int, y1: int, margin: int) -> bool:
	var path := start_path()
	var r := SimConfig.BIRD_RADIUS + margin
	for i in range(0, path.size(), 2):
		if path[i] + r > x0 and path[i] - r < x1 and path[i + 1] + r > y0 and path[i + 1] - r < y1:
			return true
	return false


## Before the first tap: whether a box (sub-units) blocks the start lane, a
## strip START_LANE_H tall from the bird's height up, from its wall to
## START_LANE_W into the room. The bird can hover in that strip while it finds
## its way, so rooms keep it clear. False once the bird is flying.
func blocks_start_lane(x0: int, y0: int, x1: int, y1: int) -> bool:
	if state.started:
		return false
	var top := state.y - (START_LANE_H - START_LANE_BELOW) * room.def.gravity_sign
	var bottom := state.y + START_LANE_BELOW * room.def.gravity_sign
	var ly0 := mini(top, bottom)
	var ly1 := maxi(top, bottom)
	var lx0 := state.x if state.vx > 0 else state.x - START_LANE_W
	var lx1 := state.x + START_LANE_W if state.vx > 0 else state.x
	return x1 > lx0 and x0 < lx1 and y1 > ly0 and y0 < ly1


func is_practice() -> bool:
	return practice_room >= 0


func is_over() -> bool:
	return not state.alive


func step(tap: bool) -> void:
	events.clear()
	if not state.alive:
		return
	# Just out of a portal: the bird and the room wait, whatever the player taps.
	if state.arrival_hold > 0:
		state.arrival_hold -= 1
		state.tick += 1
		return

	if tap:
		if not state.started:
			state.started = true
			events.append(Event.START)
		state.vy = SimConfig.FLAP_VY * room.def.gravity_sign
		state.flaps += 1
		for h in room.hazards:
			if h.alive:
				h.on_flap(self)
		events.append(Event.FLAP)

	if state.started:
		for i in room.steps_this_tick():
			_substep()
			if not state.alive:
				break
		room.ticks += 1

	state.tick += 1


## A dead bird in a real run can be revived SimConfig.MAX_REVIVES times.
func can_revive() -> bool:
	return not state.alive and not is_practice() and state.revives < SimConfig.MAX_REVIVES


## Brings a dead bird back: it arrives in the same room again as if it had
## just come through a portal (the room starts fresh, the bird waits
## ARRIVAL_HOLD ticks at a side wall, at mid height). Score, coins and the RNG
## carry on, and an open or planned exit stays where it was: the bird starts
## facing an open exit, and with its back to a ghost (it still needs the point
## that opens it). Called between steps, like a tap: the tick does not move.
## Returns false, changing nothing, when can_revive() is false.
func revive() -> bool:
	if not can_revive():
		return false
	events.clear()
	state.alive = true
	state.death_cause = SimState.DeathCause.NONE
	state.revives += 1
	# The wall the bird will fly toward.
	var side := 1 if state.vx > 0 else 0
	if state.exit_open:
		side = state.exit_side
	elif state.exit_preview:
		side = 1 - state.exit_side
	# The bird is in place before the room starts, so hazards that keep clear
	# of it (or aim at it) see where it really is. A fresh room has no inset.
	var r := SimConfig.BIRD_RADIUS
	state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	state.x = r if side == 1 else SimConfig.WORLD_W - r
	state.y = SimConfig.BIRD_START_Y
	state.vy = 0
	_enter_room(room.index)
	_arrive(side, Event.REVIVE)
	return true


## The spikes a wall shows right now. A wall with an open exit is spiked
## everywhere except the opening(s): the exit is the only way through. A
## wall showing a ghost (the next exit) keeps its spikes, but none in the
## ghost's slots, so the ghost never sits on a spike.
func wall_mask(side: int) -> int:
	if state.exit_open and state.exit_side == side:
		return ((1 << SimConfig.SLOT_COUNT) - 1) & ~exit_slots()
	var mask := room.wall_mask(side, state.left_spikes if side == 0 else state.right_spikes)
	if state.exit_preview and state.exit_side == side:
		mask &= ~exit_slots()
	return mask


## Wall slots that overlap the open (or ghost) exit(s), so no spike sits in one.
func exit_slots() -> int:
	var out := 0
	var reach := SimConfig.EXIT_HALF + SimConfig.SPIKE_HALF_BASE
	for slot in SimConfig.SLOT_COUNT:
		var cy := SimConfig.slot_center_y(slot)
		if absi(cy - state.exit_a_y) < reach:
			out |= 1 << slot
		if state.exit_b_kind != SimState.ExitKind.NORMAL and absi(cy - state.exit_b_y) < reach:
			out |= 1 << slot
	return out


## Full checksum of state, room and RNG, for golden replays and desync detection.
func checksum() -> int:
	return SimHash.mix(room.checksum(state.checksum()), _rng.state_checksum())


# --- Helpers for hazards ------------------------------------------------------


## True when the bird's circle touches the circle (cx, cy, r).
func bird_touches_circle(cx: int, cy: int, r: int) -> bool:
	var dx := state.x - cx
	var dy := state.y - cy
	var reach := SimConfig.BIRD_RADIUS + r
	return dx * dx + dy * dy <= reach * reach


## True when the bird's circle touches the box from (x0, y0) to (x1, y1).
func bird_touches_rect(x0: int, y0: int, x1: int, y1: int) -> bool:
	var nx := clampi(state.x, mini(x0, x1), maxi(x0, x1))
	var ny := clampi(state.y, mini(y0, y1), maxi(y0, y1))
	var dx := state.x - nx
	var dy := state.y - ny
	var r := SimConfig.BIRD_RADIUS
	return dx * dx + dy * dy <= r * r


## Shoves the bird away from (cx, cy): up or down, and back the way it came if
## it hit the side.
func bump_bird_from(cx: int, cy: int) -> void:
	state.vy = -BUMP_VY if state.y < cy else BUMP_VY
	if (state.x < cx) == (state.vx > 0):
		state.vx = -state.vx


## Adds a coin collected at (x, y); the view flies it from there to the counter.
func collect_coin(x: int, y: int) -> void:
	state.coins += 1
	state.pickup_x = x
	state.pickup_y = y
	events.append(Event.COIN)


func kill(cause: SimState.DeathCause) -> void:
	state.alive = false
	state.death_cause = cause
	events.append(Event.DEATH)


# --- One step ---------------------------------------------------------------


func _substep() -> void:
	room.step(self)
	_move()
	_check_spikes()
	if not state.alive:
		return
	_check_hazards()
	if not state.alive:
		return
	_check_coin()
	_check_walls()
	_check_ceiling_floor()


func _move() -> void:
	var g := SimConfig.GRAVITY * room.def.gravity_sign
	state.vy = clampi(state.vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)
	state.x += state.vx
	state.y += state.vy


func _check_hazards() -> void:
	for h in room.hazards:
		if h.alive and h.kills(self):
			kill(SimState.DeathCause.HAZARD)
			return
	for h in room.hazards:
		if h.alive:
			h.touch(self)


func _check_spikes() -> void:
	var r := SimConfig.BIRD_RADIUS
	var left := room.wall_left()
	var right := room.wall_right()
	var reach := room.max_spike_depth()
	if state.x - r <= left + reach and _hits_wall(0, left, 1):
		kill(SimState.DeathCause.SPIKE_LEFT)
	elif state.x + r >= right - reach and _hits_wall(1, right, -1):
		kill(SimState.DeathCause.SPIKE_RIGHT)


func _hits_wall(side: int, base_x: int, dir: int) -> bool:
	var mask := wall_mask(side)
	if mask == 0:
		return false
	var hb := room.spike_half_base()
	for slot in SimConfig.SLOT_COUNT:
		if not RoomRules.has_slot(mask, slot):
			continue
		var depth := room.slot_depth(side, slot)
		if depth <= 0:
			continue
		var cy := SimConfig.slot_center_y(slot)
		if absi(state.y - cy) > hb + SimConfig.BIRD_RADIUS:
			continue
		var tip_x := base_x + dir * depth
		if SimMath.circle_hits_triangle(
			state.x, state.y, SimConfig.BIRD_RADIUS, base_x, cy - hb, base_x, cy + hb, tip_x, cy
		):
			return true
	return false


func _check_walls() -> void:
	var r := SimConfig.BIRD_RADIUS
	var left := room.wall_left()
	var right := room.wall_right()
	if state.vx > 0 and state.x + r >= right:
		if _take_exit(1):
			return
		state.x = 2 * (right - r) - state.x
		state.vx = -SimConfig.SPEED_X
		state.right_spikes = 0
		_bounce_score()
		_new_wall(0)
		_maybe_open_exit(0)
	elif state.vx < 0 and state.x - r <= left:
		if _take_exit(0):
			return
		state.x = 2 * (left + r) - state.x
		state.vx = SimConfig.SPEED_X
		state.left_spikes = 0
		_bounce_score()
		_new_wall(1)
		_maybe_open_exit(1)


## The bird reached wall `side`: if it is inside an open exit there, it goes
## through to the next room. Returns true if it did.
func _take_exit(side: int) -> bool:
	if not state.exit_open or state.exit_side != side:
		return false
	# Anywhere in the spike-free gap counts, so the bird can't bounce in the
	# strip between the portal and the nearest spike. Past this, the bird's
	# center is level with a spike base and _check_spikes has already killed it.
	var fit := SimConfig.EXIT_FIT
	var kind := -1
	if absi(state.y - state.exit_a_y) <= fit:
		kind = state.exit_a_kind
	elif state.exit_b_kind != SimState.ExitKind.NORMAL and absi(state.y - state.exit_b_y) <= fit:
		kind = state.exit_b_kind
	if kind < 0:
		return false
	_go_through(side, kind)
	return true


## Every POINTS_PER_ROOM points an exit opens; one point before, it is planned
## and shown as a ghost on the wall the bird just bounced off (`1 - side`,
## where `side` is the wall it now flies toward). That is the wall the exit
## opens on: the bird bounces once more, on the far wall, and turns back to
## it. The exit then opens there at the ghost's exact height(s), even if the
## bird got turned back (Bumper Cloud) and bounced on the ghost's wall itself.
## With no ghost (a practice room starting one point short) it opens on
## `side`, as before. Every FORK_EVERY points it is a fork: a Calm and a Wild
## exit, one in each half, in a random order.
func _maybe_open_exit(side: int) -> void:
	if state.exit_open:
		return
	var every := SimConfig.POINTS_PER_ROOM
	if state.exit_preview:
		if state.score % every == 0:
			state.exit_preview = false
			state.exit_open = true
			events.append(Event.EXIT_OPEN)
		return
	if (state.score + 1) % every == 0:
		_plan_exit(1 - side, state.score + 1)
		state.exit_preview = true
		events.append(Event.EXIT_PREVIEW)
	elif state.score % every == 0:
		_plan_exit(side, state.score)
		state.exit_open = true
		events.append(Event.EXIT_OPEN)


## Picks where the exit(s) for score `at` go, on wall `side`.
func _plan_exit(side: int, at: int) -> void:
	state.exit_side = side
	var fork := at % SimConfig.FORK_EVERY == 0 and not is_practice()
	if fork:
		var top := _random_exit_y(
			SimConfig.EXIT_MIN_Y, SimConfig.FORK_SPLIT_Y - SimConfig.EXIT_HALF
		)
		var bottom := _random_exit_y(
			SimConfig.FORK_SPLIT_Y + SimConfig.EXIT_HALF, SimConfig.EXIT_MAX_Y
		)
		var calm_on_top := _rng.next_below(2) == 0
		state.exit_a_y = top
		state.exit_b_y = bottom
		state.exit_a_kind = SimState.ExitKind.CALM if calm_on_top else SimState.ExitKind.WILD
		state.exit_b_kind = SimState.ExitKind.WILD if calm_on_top else SimState.ExitKind.CALM
	else:
		state.exit_a_y = _random_exit_y(SimConfig.EXIT_MIN_Y, SimConfig.EXIT_MAX_Y)
		state.exit_a_kind = SimState.ExitKind.NORMAL
		state.exit_b_y = 0
		state.exit_b_kind = SimState.ExitKind.NORMAL


## A random exit height between lo and hi, on a spike slot's center. The
## opening is then always that slot and one either side, with the portal in
## the middle of it, so the gap is the same everywhere.
func _random_exit_y(lo: int, hi: int) -> int:
	var c0 := SimConfig.slot_center_y(0)
	var first := (lo - c0 + SimConfig.SLOT_SIZE - 1) / SimConfig.SLOT_SIZE
	var last := (hi - c0) / SimConfig.SLOT_SIZE
	# Slots no hazard blocks (Hazard.blocks_exit). One draw either way; if all
	# are blocked, any slot will have to do.
	var open: Array[int] = []
	for slot in range(first, last + 1):
		if not _exit_blocked(SimConfig.slot_center_y(slot)):
			open.append(slot)
	if open.is_empty():
		var any := first + _rng.next_below(last - first + 1)
		# A room with a short reach (Narrow) takes the slot nearest the bird (a
		# fork's far half has none within reach); the draw is still made.
		if room.def.reach > 0:
			any = clampi(
				(state.y - c0 + SimConfig.SLOT_SIZE / 2) / SimConfig.SLOT_SIZE, first, last
			)
		return SimConfig.slot_center_y(any)
	return SimConfig.slot_center_y(open[_rng.next_below(open.size())])


func _exit_blocked(y: int) -> bool:
	# A room with a short reach (Narrow) keeps the exit near the bird's height.
	if room.def.reach > 0 and absi(y - state.y) > room.def.reach:
		return true
	for h in room.hazards:
		if h.alive and h.blocks_exit(self, state.exit_side, y):
			return true
	return false


## Sim steps until the bird, flying straight on, reaches wall `side` (0 = left,
## 1 = right): one crossing if it is heading there, else the rest of this
## crossing and a whole one back. Hazards use it to know where they will be
## when the bird gets to that wall.
func steps_to_wall(side: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var left := room.wall_left() + r
	var right := room.wall_right() - r
	var heading := 1 if state.vx > 0 else 0
	var ahead := right - state.x if heading == 1 else state.x - left
	var steps := maxi(ahead, 0) / SimConfig.SPEED_X
	if heading != side:
		steps += (right - left) / SimConfig.SPEED_X
	return steps


## Flies through an exit on wall `side` into the next room: the bird comes out
## of a portal in the opposite wall at the same height, still flying the same
## way, so it never turns. It waits there ARRIVAL_HOLD ticks first. The wall
## it now faces (`side` again) gets spikes as after a bounce. No point is
## scored for this.
func _go_through(side: int, kind: int) -> void:
	state.exit_open = false
	if kind != SimState.ExitKind.NORMAL:
		state.route = kind
	if kind == SimState.ExitKind.WILD:
		for i in SimConfig.WILD_COINS:
			collect_coin(state.x, state.y)
	state.room_index += 1
	if is_practice():
		_enter_room(practice_room)
	else:
		_enter_room(RoomCatalog.pick_next(_rng, room.index, state.score, season, state.route))
	_arrive(side, Event.ROOM_CHANGE)


## Puts the bird in the room just started, out of a portal in the wall
## opposite `side`, flying toward `side`. `event` tells the view why.
func _arrive(side: int, event: Event) -> void:
	var r := SimConfig.BIRD_RADIUS
	if side == 1:
		state.x = room.wall_left() + r
		state.vx = SimConfig.SPEED_X
	else:
		state.x = room.wall_right() - r
		state.vx = -SimConfig.SPEED_X
	# Come out flying level: no speed up or down, so a bird that fell into the
	# exit doesn't drop straight into the new room's floor (or, rising, into
	# its ceiling).
	state.vy = 0
	state.arrival_hold = SimConfig.ARRIVAL_HOLD
	state.left_spikes = 0
	state.right_spikes = 0
	events.append(event)
	_new_wall(side)


## Spikes for the wall the bird is now heading to, then the room's per-bounce
## extras, then the coin. This order is part of the rules.
func _new_wall(side: int) -> void:
	var mask := RoomRules.generate_wall(_rng, state.score, room.def, state.y, room.spike_bonus())
	if side == 0:
		state.left_spikes = mask
	else:
		state.right_spikes = mask
	room.on_wall_generated(side, mask, self, _rng)
	for h in room.hazards:
		if h.alive:
			h.on_bounce(self, _rng)
	# Practice runs pay nothing, so no coin appears on a bounce there.
	if room.def.bounce_coin and not is_practice():
		_spawn_coin()


## A wall bounce scores a point, except while an exit is open: then the only
## way on is through it, so turning back (say off the Bumper Cloud) and
## bouncing again can't farm points.
func _bounce_score() -> void:
	if state.exit_open:
		events.append(Event.BOUNCE)
		return
	_score()


func _score() -> void:
	state.score += 1
	room.points += 1
	events.append(Event.BOUNCE)
	events.append(Event.SCORE)


func _enter_room(index: int) -> void:
	state.room_kind = index
	room.start(RoomCatalog.all()[index], index, self, _rng)


## Places a coin at a random spot, unless one is already out. In a room with
## `bounce_coin_stacks` (Coin Garden) the extra coin becomes a room coin instead.
func _spawn_coin() -> void:
	var extra := state.coin_active
	if extra and not room.def.bounce_coin_stacks:
		return
	var span_x := SimConfig.COIN_MAX_X - SimConfig.COIN_MIN_X + 1
	var span_y := SimConfig.COIN_MAX_Y - SimConfig.COIN_MIN_Y + 1
	var x := SimConfig.COIN_MIN_X + _rng.next_below(span_x)
	var y := SimConfig.COIN_MIN_Y + _rng.next_below(span_y)
	if extra:
		room.add_coin(x, y)
		return
	state.coin_active = true
	state.coin_x = x
	state.coin_y = y
	events.append(Event.COIN_SPAWN)


func _check_coin() -> void:
	if state.coin_active and bird_touches_circle(state.coin_x, state.coin_y, SimConfig.COIN_RADIUS):
		state.coin_active = false
		collect_coin(state.coin_x, state.coin_y)


func _check_ceiling_floor() -> void:
	var r := SimConfig.BIRD_RADIUS
	if state.y - r <= SimConfig.KILL_TOP:
		if not _edge_guarded(true):
			kill(SimState.DeathCause.CEILING)
	elif state.y + r >= SimConfig.KILL_BOTTOM:
		if not _edge_guarded(false):
			kill(SimState.DeathCause.FLOOR)


func _edge_guarded(top: bool) -> bool:
	for h in room.hazards:
		if h.alive and h.guards_edge(self, top):
			return true
	return false
