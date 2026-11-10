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
## See _keep_hold_band_open: half a second to steer after reading the room.
const ARRIVAL_WALL_SPARE := 30
## Practice starts this far from the left wall.
const PRACTICE_START_GAP := 40 * SimConfig.SUB
## As the practice room: a blank sim with no room built yet, for SimCopy to fill.
const FOR_COPY := -2

var seed_value: int
var season: int
## Practice: the room kind (RoomCatalog index) this run repeats, or -1 for a
## real run. Practice starts at the room's from_score, so its walls are as
## busy as in a real run, and it never picks another room. Real runs are
## unchanged by this (no extra RNG draws), so replays and goldens stay valid.
var practice_room := -1
## Bots and tests only: the room variant id to play in place of the drawn one,
## in any room that has a variant with this id. The variant is still drawn, so
## the RNG goes on exactly as in a normal run. "" (always in real play) plays
## the drawn variant.
var forced_variant := ""
var state := SimState.new()
## The room being played: its hazards and wall rules.
var room := RoomRuntime.new()
## Events produced by the last step(). Read them, don't keep the array.
var events: Array[int] = []

var _rng: SimRng
## True on a copy that ArrivalCheck plays (it skips its own arrival checks).
var _checking := false


func _init(
	p_seed: int, p_season: int = Seasons.NONE, p_practice_room: int = -1, p_variant: String = ""
) -> void:
	seed_value = p_seed
	season = p_season
	forced_variant = p_variant
	_rng = SimRng.new(p_seed)
	if p_practice_room == FOR_COPY:
		return
	if p_practice_room >= 0 and p_practice_room < RoomCatalog.all().size():
		practice_room = p_practice_room
		state.score = RoomCatalog.all()[practice_room].from_score
		# Start at the left wall facing in, as when arriving through an exit,
		# so the bird never starts inside a hazard in the middle of the room.
		state.x = PRACTICE_START_GAP
		_enter_room(practice_room)
	else:
		_enter_room(RoomCatalog.first_index())


func is_practice() -> bool:
	return practice_room >= 0


## The score to show: the run's score, or in practice the points scored since
## the practice started (it starts at the room's from_score).
func shown_score() -> int:
	if is_practice():
		return state.score - RoomCatalog.all()[practice_room].from_score
	return state.score


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
		return ((1 << SimConfig.SLOT_COUNT) - 1) & ~ExitPlanner.slots(state)
	var mask := room.wall_mask(side, state.left_spikes if side == 0 else state.right_spikes)
	if state.exit_preview and state.exit_side == side:
		mask &= ~ExitPlanner.slots(state)
	return mask


## How far wall `side`'s spikes are slid along the wall (Spike Belt),
## sub-units, down is +. 0 in other rooms.
func wall_shift(side: int) -> int:
	var out := 0
	for h in room.hazards:
		if h.alive:
			out += h.wall_shift(self, side)
	return out


## True while a hazard keeps the open exit shut (Locked Exit).
func exit_locked() -> bool:
	for h in room.hazards:
		if h.alive and h.locks_exit(self):
			return true
	return false


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
	var shift := wall_shift(side)
	for slot in SimConfig.SLOT_COUNT:
		if not RoomRules.has_slot(mask, slot):
			continue
		var depth := room.slot_depth(side, slot)
		if depth <= 0:
			continue
		var cy := SimConfig.slot_center_y(slot) + shift
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
	# Locked Exit: a locked exit is a bounce.
	if exit_locked():
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
		ExitPlanner.plan(self, _rng, 1 - side, state.score + 1)
		state.exit_preview = true
		events.append(Event.EXIT_PREVIEW)
	elif state.score % every == 0:
		ExitPlanner.plan(self, _rng, side, state.score)
		state.exit_open = true
		events.append(Event.EXIT_OPEN)


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
## way, so it never stops or turns. The room is laid out so a player who is
## slow to react still lives (ArrivalCheck). The
## wall it now faces (`side` again) gets spikes as after a bounce. No point is
## scored for this.
func _go_through(side: int, kind: int) -> void:
	state.exit_open = false
	if kind != SimState.ExitKind.NORMAL:
		state.route = kind
	if kind == SimState.ExitKind.WILD:
		for i in SimConfig.WILD_COINS:
			collect_coin(state.x, state.y)
	state.room_index += 1
	# Far enough from the ceiling and floor to hop while reading the room (the
	# bird jumps walls here anyway, so the view shows no slide).
	state.y = clampi(
		state.y,
		SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE,
		SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE
	)
	var next := practice_room
	if not is_practice():
		next = RoomCatalog.pick_next(_rng, room.index, state.score, season, state.route, state.y)
	# Lay the room out so a player who needs a moment to look can live: the
	# check plays it on copies, and each retry skips one RNG draw.
	for i in _arrival_retries(side, next):
		_rng.next_u32()
	_arrive_in(side, next)


## How many RNG draws to skip before laying out room `next`: the first layout
## (of ARRIVAL_TRIES) that ArrivalCheck finds fair, else the one that lived
## longest. 0 inside a check, so checks never nest.
func _arrival_retries(side: int, next: int) -> int:
	if _checking or SimConfig.ARRIVAL_BLIND == 0:
		return 0
	var fair := SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW
	var best := 0
	var best_score := -1
	for k in SimConfig.ARRIVAL_TRIES:
		var c := SimCopy.copy(self)
		c._checking = true
		for i in k:
			c._rng.next_u32()
		c._arrive_in(side, next)
		var lived := ArrivalCheck.score(c)
		if lived >= fair:
			return k
		if lived > best_score:
			best_score = lived
			best = k
	return best


## Starts room `next` with the bird out of a portal in the wall opposite
## `side`, flying toward `side`.
func _arrive_in(side: int, next: int) -> void:
	# The bird is put at the portal first, so hazards see where it comes in. A
	# fresh room has no inset.
	var r := SimConfig.BIRD_RADIUS
	state.vx = SimConfig.SPEED_X if side == 1 else -SimConfig.SPEED_X
	state.x = r if side == 1 else SimConfig.WORLD_W - r
	_enter_room(next)
	_arrive(side, Event.ROOM_CHANGE)


## Puts the bird in the room just started, out of a portal in the wall
## opposite `side`, flying toward `side`. `event` tells the view why. A
## revived bird waits ARRIVAL_HOLD ticks first (it has just died, the player
## needs a moment); out of a portal it flies straight on.
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
	if event == Event.REVIVE:
		state.arrival_hold = SimConfig.ARRIVAL_HOLD
	state.left_spikes = 0
	state.right_spikes = 0
	events.append(event)
	_new_wall(side)
	if event == Event.ROOM_CHANGE:
		_keep_hold_band_open(side)


## Out of a portal, if the bird gets to the wall ahead within the reading
## time and ARRIVAL_WALL_SPARE ticks more (a fast or narrow room), that wall
## has no spikes where a player holding height hops: one hop over its height,
## the bird under it.
func _keep_hold_band_open(side: int) -> void:
	var steps := steps_to_wall(side)
	var ticks := 0
	var done := 0
	while done < steps:
		done += room.steps_at(ticks)
		ticks += 1
	if ticks > SimConfig.ARRIVAL_BLIND + ARRIVAL_WALL_SPARE:
		return
	var g := room.def.gravity_sign
	var edge := SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB
	var up := state.y - (FairLanes.FIRST_HOP + edge) * g
	var down := state.y + edge * g
	var top := mini(up, down)
	var bottom := maxi(up, down)
	var mask := state.right_spikes if side == 1 else state.left_spikes
	for slot in SimConfig.SLOT_COUNT:
		var cy := SimConfig.slot_center_y(slot)
		if cy + SimConfig.SPIKE_HALF_BASE > top and cy - SimConfig.SPIKE_HALF_BASE < bottom:
			mask &= ~(1 << slot)
	if side == 1:
		state.right_spikes = mask
	else:
		state.left_spikes = mask


## Spikes for the wall the bird is now heading to, then the room's per-bounce
## extras, then the coin. This order is part of the rules.
func _new_wall(side: int) -> void:
	var mask := RoomRules.generate_wall(_rng, state.score, room.def, state.y, room.spike_bonus())
	for h in room.hazards:
		if h.alive:
			mask = h.adjust_wall(self, side, mask)
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
