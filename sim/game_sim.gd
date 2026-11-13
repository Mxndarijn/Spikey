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
	REVIVE,
	BOSS_DOWN
}

## How hard a bumper shoves the bird (vertical speed, sub-units per step): a bit
## more than a flap, tied to it so the shove stays survivable if the flap changes.
const BUMP_VY := -SimConfig.FLAP_VY * 6 / 5
## See _keep_hold_band_open: half a second to steer after reading the room.
const ARRIVAL_WALL_SPARE := 30
## Practice starts this far from the left wall.
const PRACTICE_START_GAP := 40 * SimConfig.SUB
## Bounces before an exit when the anchor and the walls steer toward it
## (_anchor_target, _wall_target).
const EXIT_STEER := 3
## New wall spikes slide out over this many room steps (RoomView: 7.5 ticks)
## and kill only once all the way out. A wall never kills a bird flying away
## from it (a wall that moves in, a tide spike that grows, a belt that resets).
const SPIKE_SLIDE := 10
## Bird heights (from the exit's) a portal arrival is checked at: anywhere a
## bird can come through the exit (see _arrival_retries).
const ARRIVAL_HEIGHTS: Array[int] = [
	0, -SimConfig.EXIT_FIT, SimConfig.EXIT_FIT, -SimConfig.EXIT_FIT / 2, SimConfig.EXIT_FIT / 2
]
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
## The free run the last new wall was drawn with, for hazards that change the
## wall (CrowdFill): its first slot and the first and last starts it could
## have had (RoomRules.generate_wall_run). -1s: none.
var wall_run := PackedInt32Array([-1, -1, -1])
var state := SimState.new()
## The room being played: its hazards and wall rules.
var room := RoomRuntime.new()
## Events produced by the last step(). Read them, don't keep the array.
var events: Array[int] = []

## The room's RNG: its layout, walls, coins and exits (GameSim._new_wall
## reseeds it for every wall after the first).
var _rng: SimRng
## Draws only each room's kind and seed, a fixed number per portal, so nothing
## a player does in a room changes the rooms after it: two players of one seed
## who take the same portals get the same rooms, variants, spikes and hazards.
var _spine: SimRng
## True on a copy that ArrivalCheck plays (it skips its own arrival checks).
var _checking := false
## The next portal arrival may draw another variant than a generated one the
## room seed drew (RoomRuntime.start): set by _arrival_retries when none of the
## ARRIVAL_TRIES layouts with that variant is fair, cleared by _arrive_in.
var _arrival_unpin := false
## Tool info, not gameplay (not in the checksum): the last portal arrival had no
## layout fair for a bird anywhere in the exit; the best one was taken.
var _arrival_unfit := false
## While ExitPlanner plans: points_to_exit() as if this many points were left
## (-1 = the real count), and a second count the plan must also be clear for
## (-1 = none; see ExitPlanner.plan_room).
var _points_override := -1
var _points_also := -1
## The free part of the wall just bounced off, top and bottom (-1 = none
## known): set by _anchor_at_wall for the _new_wall right after it.
var _free_lo := -1
var _free_hi := -1
## The room as the bird came into it, the whole state then (bird, score,
## coins, exits) and both RNGs: a revive restarts the run from here. Taken at the run
## start and after each portal arrival (not in practice or checks); never
## changed afterwards.
var _entry_room: RoomRuntime = null
var _entry_state: SimState = null
var _entry_rng: SimRng = null
var _entry_spine: SimRng = null


func _init(
	p_seed: int, p_season: int = Seasons.NONE, p_practice_room: int = -1, p_variant: String = ""
) -> void:
	seed_value = p_seed
	season = p_season
	forced_variant = p_variant
	_spine = SimRng.new(p_seed)
	_rng = SimRng.new(0)
	if p_practice_room == FOR_COPY:
		return
	_seed_room()
	if p_practice_room >= 0 and p_practice_room < RoomCatalog.all().size():
		practice_room = p_practice_room
		state.score = RoomCatalog.all()[practice_room].from_score
		# Start at the left wall facing in, as when arriving through an exit,
		# so the bird never starts inside a hazard in the middle of the room.
		state.x = PRACTICE_START_GAP
		_enter_room(practice_room)
		ExitPlanner.plan_room(self, next_exit_score())
	else:
		_enter_room(RoomCatalog.first_index())
		ExitPlanner.plan_room(self, next_exit_score())
		_keep_entry()


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
		state.vy = SimConfig.FLAP_VY * room.gravity
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


## Brings a dead bird back: the run goes back to the moment the bird came
## into the room (_keep_entry). The room (variant, hazards, wall spikes), the
## bird (wall, height, way, speed), the score, the coins, the room's coin, the
## planned exits and both RNGs are all as they were then, so the rest of the
## run is the one a player who never died there would meet. Only the tick, the
## revive count and the taps (flaps) carry on. The bird waits ARRIVAL_HOLD
## ticks with the room frozen, then flies on by itself. Called between steps,
## like a tap: the tick does not move.
## Returns false, changing nothing, when can_revive() is false.
func revive() -> bool:
	if not can_revive():
		return false
	events.clear()
	var tick := state.tick
	var revives := state.revives + 1
	var flaps := state.flaps
	state.assign(_entry_state)
	state.tick = tick
	state.revives = revives
	state.flaps = flaps
	# At the run start the bird waited for a first tap; after a revive it flies
	# on by itself once the hold is over.
	state.started = true
	state.arrival_hold = SimConfig.ARRIVAL_HOLD
	room = SimCopy.copy_room(_entry_room)
	_rng = SimCopy.copy_rng(_entry_rng)
	_spine = SimCopy.copy_rng(_entry_spine)
	_free_lo = -1
	_free_hi = -1
	events.append(Event.REVIVE)
	return true


## The spikes a wall shows right now. A wall with an open exit is spiked
## everywhere except the opening(s): the exit is the only way through. A
## wall showing a ghost (the next exit) keeps its spikes, but none in the
## ghost's slots, so the ghost never sits on a spike.
func wall_mask(side: int) -> int:
	if state.exit_open and state.exit_side == side:
		var open := ((1 << SimConfig.SLOT_COUNT) - 1) & ~ExitPlanner.slots(state)
		return open
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


## True while a hazard keeps the open exit shut (Locked Out).
func exit_locked() -> bool:
	for h in room.hazards:
		if h.alive and h.locks_exit(self):
			return true
	return false


## Full checksum of state, room and RNG, for golden replays and desync detection.
func checksum() -> int:
	return SimHash.mix(
		SimHash.mix(room.checksum(state.checksum()), _rng.state_checksum()), _spine.state_checksum()
	)


## Every warning (tell) on screen now: Hazard.warnings() of each live hazard,
## Hazard.WARN_SIZE ints per warning. The bots' one shared reading of what is
## announced but not there yet. Reads only; not part of the checksum.
func warnings() -> PackedInt64Array:
	var out := PackedInt64Array()
	for h: Hazard in room.hazards:
		if h.alive:
			h.warnings(self, out)
	return out


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
## it hit the side (then the spikes of the wall it just left go back in).
func bump_bird_from(cx: int, cy: int) -> void:
	state.vy = -BUMP_VY if state.y < cy else BUMP_VY
	if (state.x < cx) == (state.vx > 0):
		state.vx = -state.vx
		if state.vx > 0:
			state.right_spikes = 0
			state.right_new = 0
		else:
			state.left_spikes = 0
			state.left_new = 0


## Adds `amount` coins collected at (x, y); the view flies them from there to the
## counter.
func collect_coin(x: int, y: int, amount: int = 1) -> void:
	state.coins += amount
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
	var g := SimConfig.GRAVITY * room.gravity
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
	if mask == 0 or (state.vx > 0) == (side == 0):
		return false
	var hb := room.spike_half_base()
	var shift := wall_shift(side)
	for slot in SimConfig.SLOT_COUNT:
		if not RoomRules.has_slot(mask, slot):
			continue
		# A new spike kills only once it is all the way out.
		var fresh := state.left_new if side == 0 else state.right_new
		if RoomRules.has_slot(fresh, slot):
			if room.t - (state.left_drawn if side == 0 else state.right_drawn) < SPIKE_SLIDE:
				continue
		var depth := room.slot_depth(side, slot)
		if depth <= 0:
			continue
		var cy := SimConfig.slot_center_y(slot) + shift
		var lo := cy - hb
		var hi := cy + hb
		if state.y < lo - SimConfig.BIRD_RADIUS or state.y > hi + SimConfig.BIRD_RADIUS:
			continue
		var tip_x := base_x + dir * depth
		if SimMath.circle_hits_triangle(
			state.x, state.y, SimConfig.BIRD_RADIUS, base_x, lo, base_x, hi, tip_x, cy
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
		_anchor_at_wall(1)
		state.x = 2 * (right - r) - state.x
		state.vx = -SimConfig.SPEED_X
		room.on_wall_bounce()
		_bounce_score()
		_walls_after_bounce(1)
		_maybe_open_exit()
	elif state.vx < 0 and state.x - r <= left:
		if _take_exit(0):
			return
		_anchor_at_wall(0)
		state.x = 2 * (left + r) - state.x
		state.vx = SimConfig.SPEED_X
		room.on_wall_bounce()
		_bounce_score()
		_walls_after_bounce(0)
		_maybe_open_exit()


## A bounce off wall `side` draws its next spikes (two crossings to see them),
## a room's first bounce the wall ahead too.
func _walls_after_bounce(side: int) -> void:
	if room.walls == 0:
		_new_wall(1 - side, false)
	_new_wall(side)
	room._boss_recheck(self, 1 - side)


## The bird reached wall `side`: if it is inside an open exit there, it goes
## through to the next room. Returns true if it did.
func _take_exit(side: int) -> bool:
	if not state.exit_open or state.exit_side != side:
		return false
	# Locked Out: a locked exit is a bounce.
	if exit_locked():
		return false
	# Anywhere in the spike-free gap counts, so the bird can't bounce in the
	# strip between the portal and the nearest spike. Past this, the bird's
	# center is level with a spike base and _check_spikes has already killed it.
	var fit := SimConfig.EXIT_FIT
	var kind := -1
	var through := 0
	if absi(state.y - state.exit_a_y) <= fit:
		kind = state.exit_a_kind
		through = state.exit_a_y
	elif state.exit_b_kind != SimState.ExitKind.NORMAL and absi(state.y - state.exit_b_y) <= fit:
		kind = state.exit_b_kind
		through = state.exit_b_y
	if kind < 0:
		return false
	_go_through(side, kind, through)
	return true


## Every POINTS_PER_ROOM points an exit opens; one point before, it is planned
## and shown as a ghost. Both are always on the right wall
## (SimConfig.EXIT_WALL), the wall a bird that came out of a portal heads to,
## so a bird the Bumper Cloud turned back still leaves the room the same way
## as every other player of the seed: it may just need one more crossing. At a
## fork (ExitPlanner.is_fork) it is a Calm and a Wild exit, one in each half,
## in a random order. In a boss room the exit opens after SimConfig.BOSS_POINTS
## bounces there instead, with no ghost first (the boss fights on until then),
## and the boss breaks.
func _maybe_open_exit() -> void:
	# Nothing is due before a point is scored in the room (in Buttons a bounce
	# scores nothing, and the room starts at a multiple of POINTS_PER_ROOM).
	if state.exit_open or room.points == 0:
		return
	if state.exit_preview:
		if _exit_due(state.score):
			state.exit_preview = false
			state.exit_open = true
			events.append(Event.EXIT_OPEN)
			_boss_down()
		return
	if _exit_due(state.score + 1) and not room.def.boss:
		state.exit_preview = true
		ExitPlanner.use_plan(self, SimConfig.EXIT_WALL, state.score + 1)
		events.append(Event.EXIT_PREVIEW)
	elif _exit_due(state.score):
		state.exit_open = true
		ExitPlanner.use_plan(self, SimConfig.EXIT_WALL, state.score)
		events.append(Event.EXIT_OPEN)
		_boss_down()


## Whether an exit opens at score `at` in this room: every POINTS_PER_ROOM
## points, or in a boss room BOSS_POINTS after it was entered.
func _exit_due(at: int) -> bool:
	if room.def.boss:
		return at == room.entry_score + SimConfig.BOSS_POINTS
	return at % SimConfig.POINTS_PER_ROOM == 0


## The exit of a boss room just opened: the boss breaks (its hazard stops) and
## pays its coins (none in practice).
func _boss_down() -> void:
	if not room.def.boss:
		return
	events.append(Event.BOSS_DOWN)
	if not is_practice():
		collect_coin(
			state.x, state.y, SimConfig.BOSS_COINS[SimConfig.boss_tier(room.entry_score) - 1]
		)


## The score the next exit opens at: now if one is open, else the next
## multiple of POINTS_PER_ROOM.
func next_exit_score() -> int:
	if state.exit_open:
		return state.score
	if room.def != null and room.def.boss:
		return room.entry_score + SimConfig.BOSS_POINTS
	var every := SimConfig.POINTS_PER_ROOM
	return (state.score / every + 1) * every


## Bounces still to score before the next exit opens.
func points_to_exit() -> int:
	if _points_override >= 0:
		return _points_override
	return next_exit_score() - state.score


## Sim steps until the bird, flying straight on and bouncing, gets to wall
## `side` with the next exit open: the points still to score first, then the
## first time it reaches that wall. One bounce before the exit (a ghost) this
## is steps_to_wall(side). Hazards that move use it to keep the way to an exit
## open (Hazard.blocks_exit), also when the exit is picked at room start.
func steps_to_exit(side: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var left := room.wall_left() + r
	var right := room.wall_right() - r
	var heading := 1 if state.vx > 0 else 0
	var ahead := right - state.x if heading == 1 else state.x - left
	# Wall touches from now: the first is on the wall ahead, then they take
	# turns. The exit can be taken on the touch after its points are in.
	var touch := points_to_exit() + 1
	var on := heading if touch % 2 == 1 else 1 - heading
	if on != side:
		touch += 1
	return maxi(ahead, 0) / SimConfig.SPEED_X + (touch - 1) * ((right - left) / SimConfig.SPEED_X)


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
## scored for this. `through_y` is the height of the exit taken: the room is
## picked and laid out for it, never for the bird's own height. Both exits of a
## fork lead to one door (SimConfig.FORK_DOOR_Y), so the room behind a fork is
## the same for Calm and Wild; the route (`kind`) lasts that one room.
func _go_through(side: int, kind: int, through_y: int) -> void:
	state.exit_open = false
	state.route = kind
	if kind == SimState.ExitKind.WILD:
		for i in SimConfig.WILD_COINS:
			collect_coin(state.x, state.y)
	state.room_index += 1
	var door := through_y
	if kind != SimState.ExitKind.NORMAL:
		state.y += SimConfig.FORK_DOOR_Y - through_y
		door = SimConfig.FORK_DOOR_Y
	# Far enough from the ceiling and floor to hop while reading the room (the
	# bird jumps walls here anyway, so the view shows no slide).
	state.y = _arrival_y(state.y)
	state.anchor_y = _arrival_y(door)
	var next := practice_room
	if is_practice():
		pass
	elif _boss_due():
		next = RoomCatalog.pick_boss(_spine, state.bosses_met)
		state.bosses_met |= RoomCatalog.boss_bit(next)
	else:
		next = RoomCatalog.pick_next(_spine, state, room.index, season)
	_seed_room()
	# Lay the room out so a player who needs a moment to look can live: the
	# check plays it on copies, and each retry skips one RNG draw.
	for i in _arrival_retries(side, next):
		_rng.next_u32()
	_arrive_in(side, next)


## Whether the exit just taken leads into a boss room: the one at every
## BOSS_EVERY points (never out of a boss room itself).
func _boss_due() -> bool:
	return state.score > 0 and state.score % SimConfig.BOSS_EVERY == 0 and not room.def.boss


## Far enough from the ceiling and floor to hop while reading the room.
static func _arrival_y(y: int) -> int:
	return clampi(
		y,
		SimConfig.KILL_TOP + SimConfig.ARRIVAL_EDGE,
		SimConfig.KILL_BOTTOM - SimConfig.ARRIVAL_EDGE
	)


## Draws the next room's seed from the spine and starts the room's RNG on it.
func _seed_room() -> void:
	room.rng_seed = _spine.next_u32()
	_rng.reseed(room.rng_seed)


## How many RNG draws to skip before laying out room `next`: the first layout
## (of ARRIVAL_TRIES) that ArrivalCheck finds fair for a bird anywhere in the
## exit it came through (its height and EXIT_FIT above and below,
## ARRIVAL_HEIGHTS), so the layout never depends on the bird's own height.
## There is no wait out of a portal: if none is fair, and the room has another
## variant to draw than a generated one the seed picked, ARRIVAL_TRIES layouts
## more where any variant may be drawn (_arrival_unpin); failing that, the one
## that lived longest at the exit's height, then at its worst height (the
## simple players only hold heights; a player who has read the room can
## steer), with _arrival_unfit set. 0 inside a check, so checks never nest.
func _arrival_retries(side: int, next: int) -> int:
	_arrival_unpin = false
	_arrival_unfit = false
	if _checking or SimConfig.ARRIVAL_BLIND == 0:
		return 0
	var best := 0
	var best_score := -1
	var best_unpin := false
	var passes: Array[bool] = [false]
	if RoomCatalog.all()[next].has_generated_choice():
		passes.append(true)
	for unpin in passes:
		for k in SimConfig.ARRIVAL_TRIES:
			var score := _arrival_score(side, next, k, unpin)
			if score < 0:
				_arrival_unpin = unpin
				return k
			if score > best_score:
				best_score = score
				best = k
				best_unpin = unpin
	_arrival_unpin = best_unpin
	_arrival_unfit = true
	return best


## How layout `k` (RNG draws skipped) of room `next` does (any variant drawn
## when `unpin`): -1 if fair at every ARRIVAL_HEIGHTS height, else a rank (the
## exit's height first, then the worst one).
func _arrival_score(side: int, next: int, k: int, unpin: bool) -> int:
	var fair := SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW
	var centre := 0
	var worst := fair
	for dy: int in ARRIVAL_HEIGHTS:
		var c := SimCopy.copy(self)
		c._checking = true
		c._arrival_unpin = unpin
		c.state.y = _arrival_y(state.anchor_y + dy)
		for i in k:
			c._rng.next_u32()
		c._arrive_in(side, next)
		# A room checked within a narrower band (RoomVariant.arrival_spread): the
		# bird there. The layout never reads the bird's height.
		if VariantCheck.arrival_dy(c, dy) != dy:
			c.state.y = _arrival_y(state.anchor_y + VariantCheck.arrival_dy(c, dy))
		var lived := mini(ArrivalCheck.score(c), fair)
		if dy == 0:
			centre = lived
		worst = mini(worst, lived)
		# One height that fails is enough: the rest are not played.
		if worst < fair:
			break
	if worst >= fair:
		return -1
	return centre * (fair + 1) + worst


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
	ExitPlanner.plan_room(self, next_exit_score())
	# The bird flies on at once; a boss comes in while the bird waits (its own
	# attacks wait longer still).
	state.arrival_hold = SimConfig.BOSS_HOLD if room.def.boss else 0
	_arrival_unpin = false
	_keep_entry()


## Keeps the room and the bird as they are now, for a revive (_entry_room).
func _keep_entry() -> void:
	if is_practice() or _checking:
		return
	_entry_room = SimCopy.copy_room(room)
	_entry_state = state.copy()
	_entry_rng = SimCopy.copy_rng(_rng)
	_entry_spine = SimCopy.copy_rng(_spine)


## Puts the bird in the room just started, out of a portal in the wall
## opposite `side`, flying toward `side`. It flies straight on.
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
	state.left_spikes = 0
	state.right_spikes = 0
	state.left_new = 0
	state.right_new = 0
	events.append(event)
	_new_wall(side)
	if event == Event.ROOM_CHANGE:
		_keep_hold_band_open(side)
	# The wall behind (the portal's), for the bird's way back: in a narrow room
	# a player still reading the room can get back to it too.
	_new_wall(1 - side, false)
	if event == Event.ROOM_CHANGE:
		_keep_hold_band_open(1 - side)


## Out of a portal, if the bird gets to the wall ahead within the reading
## time and ARRIVAL_WALL_SPARE ticks more (a fast or narrow room), that wall
## has no spikes where a player holding height hops: one hop over its height,
## the bird under it, for a bird anywhere in the exit it came through
## (anchor_y and EXIT_FIT either way).
func _keep_hold_band_open(side: int) -> void:
	var steps := steps_to_wall(side)
	var ticks := 0
	var done := 0
	while done < steps:
		done += room.steps_at(ticks)
		ticks += 1
	if ticks > SimConfig.ARRIVAL_BLIND + ARRIVAL_WALL_SPARE:
		return
	var g := room.gravity
	var edge := SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB
	var spread := SimConfig.EXIT_FIT
	var up := state.anchor_y - (FairLanes.FIRST_HOP + edge + spread) * g
	var down := state.anchor_y + (edge + spread) * g
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


## Spikes for wall `side`, then (with `extras`) the room's per-bounce extras,
## then the coin: this order is part of the rules. Every wall after the
## arrival's reseeds from the room's seed and the wall's number, so nothing a
## player did changes it. Its free run is chained to the other wall's.
func _new_wall(side: int, extras: bool = true) -> void:
	# What the wall shows now: any spike it shows after that is new and slides out.
	var before := wall_mask(side)
	var other_drawn := room.walls > 0
	if room.walls > 0:
		_rng.reseed(SimHash.mix(room.rng_seed, room.walls))
	room.walls += 1
	# Chained to the other wall (met first): its free part and anchor there.
	var anchor := state.anchor_y
	if other_drawn:
		anchor = _free_run_of(1 - side)
	var reach := -1
	var target := _wall_target(anchor)
	if target < 0:
		# Every free spot of the last wall can reach the new free run.
		reach = RoomRules.gap_reach(room.def) - (_free_hi - _free_lo) / 2
		target = (_free_lo + _free_hi) / 2
	_free_lo = -1
	_free_hi = -1
	var bonus := room.spike_bonus(side)
	# Behind a Wild exit: more spikes on every wall after the arrival's two. The
	# arrival check (_checking) lays the room out without them, so the layout
	# is the one a Calm player gets.
	if state.route == SimState.ExitKind.WILD and room.walls > 2 and not _checking:
		bonus += SimConfig.WILD_SPIKES
	# A room whose bounces don't score (Buttons) counts its spikes from the
	# score it was entered at: its presses depend on the player, its walls
	# only on the seed.
	var wall_score := state.score if room.def.bounce_points else room.entry_score
	var drawn := RoomRules.generate_wall_run(_rng, wall_score, room.def, target, bonus, reach)
	var mask: int = drawn[0]
	wall_run = PackedInt32Array([drawn[1], drawn[2], drawn[3]])
	for h in room.hazards:
		if h.alive:
			mask = h.adjust_wall(self, side, mask)
	if side == 0:
		state.left_spikes = mask
	else:
		state.right_spikes = mask
	room.on_wall_generated(side, mask, self, _rng)
	# Blink Walls: the second pattern is new too.
	var shown := mask
	if room.def.wall_mode == RoomDef.WallMode.BLINK:
		shown |= room.blink_left if side == 0 else room.blink_right
	if side == 0:
		state.left_new = shown & ~before
		state.left_drawn = room.t
	else:
		state.right_new = shown & ~before
		state.right_drawn = room.t
	if not extras:
		return
	for h in room.hazards:
		if h.alive:
			h.on_bounce(self, _rng)
	# Practice runs pay nothing, so no coin appears on a bounce there.
	if room.def.bounce_coin and not is_practice():
		_spawn_coin()


## Where the free run of a new wall stays near (RoomRules.gap_reach):
## the anchor. In a room with a short reach (Narrow), and in any room the last
## EXIT_STEER bounces before an exit, it steps, by half the reach a wall,
## toward the room's planned exit, so the anchor is near the exit when it
## opens. Otherwise, when every free spot of the wall just bounced off is
## close enough together, -1: the new run is then kept within reach of all of
## them (_new_wall), so a bird that came through any of them has a way on.
func _wall_target(anchor: int) -> int:
	var reach := RoomRules.gap_reach(room.def)
	if reach <= 0 or state.exit_open:
		return anchor
	# The wall drawn now is met a bounce after the wall ahead.
	if room.def.reach <= 0 and points_to_exit() - 1 > EXIT_STEER:
		if _free_lo >= 0 and reach - (_free_hi - _free_lo) / 2 >= SimConfig.SLOT_SIZE:
			return -1
		return anchor
	var to := ExitPlanner.planned_y(self, SimConfig.EXIT_WALL, anchor)
	return anchor + clampi(to - anchor, -reach / 2, reach / 2)


## Wall `side`'s spikes as drawn, with the exit's openings: what the anchor
## follows (not wall_mask(), whose tide, blink and belt change with time).
func _drawn_mask(side: int) -> int:
	if state.exit_open and state.exit_side == side:
		return ((1 << SimConfig.SLOT_COUNT) - 1) & ~ExitPlanner.slots(state)
	var mask := state.left_spikes if side == 0 else state.right_spikes
	if state.exit_preview and state.exit_side == side:
		mask &= ~ExitPlanner.slots(state)
	return mask


## The last EXIT_STEER bounces before an exit: the room's planned exit on
## the exit wall (SimConfig.EXIT_WALL); before that, the anchor.
func _anchor_target() -> int:
	if state.exit_open or points_to_exit() > EXIT_STEER:
		return state.anchor_y
	return ExitPlanner.planned_y(self, SimConfig.EXIT_WALL, state.anchor_y)


## At a bounce on wall `side` (before its spikes go): the anchor moves to the
## point of that wall's free run nearest it (near an exit, nearest the exit,
## _anchor_target). The bird got through a free run, and each new wall keeps
## its run near the anchor, so a bird that follows the anchors always has a
## fair way on. A wall with no free slot keeps it. Also keeps the wall's free
## part, top and bottom, for the next wall (_free_lo, _free_hi).
func _anchor_at_wall(side: int) -> void:
	state.anchor_y = _free_run_of(side)


## Wall `side`'s free part, top and bottom (_free_lo, _free_hi), and the
## point of its free runs _anchor_at_wall moves the anchor to, without moving
## it.
func _free_run_of(side: int) -> int:
	var mask := _drawn_mask(side)
	var target := _anchor_target()
	var best := state.anchor_y
	var best_d := -1
	_free_lo = -1
	_free_hi = -1
	var slot := 0
	while slot < SimConfig.SLOT_COUNT:
		if RoomRules.has_slot(mask, slot):
			slot += 1
			continue
		var lo := slot
		while slot + 1 < SimConfig.SLOT_COUNT and not RoomRules.has_slot(mask, slot + 1):
			slot += 1
		var top := SimConfig.slot_center_y(lo)
		var bottom := SimConfig.slot_center_y(slot)
		if _free_lo < 0:
			_free_lo = top
		_free_hi = bottom
		var y := clampi(target, top, bottom)
		var d := absi(y - target)
		if best_d < 0 or d < best_d:
			best = y
			best_d = d
		slot += 1
	return best


## A wall bounce scores a point, except while an exit is open (turning back,
## say off the Bumper Cloud, and bouncing again can't farm points).
func _bounce_score() -> void:
	if state.exit_open or not room.def.bounce_points:
		events.append(Event.BOUNCE)
		return
	_score()


## A hazard scores a point (a Buttons press, ButtonPair): unless the exit is
## open, or the room's exit is already due and waits for the next wall bounce
## to open (_maybe_open_exit). Returns whether it scored. For hazards only.
func _score_press() -> bool:
	if state.exit_open or (room.points > 0 and _exit_due(state.score)):
		return false
	state.score += 1
	room.points += 1
	events.append(Event.SCORE)
	return true


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
	# Tide Spikes: the coin keeps clear of the sliding spikes' full reach (Tide
	# big reaches past COIN_MIN_X). The same draws.
	var min_x := SimConfig.COIN_MIN_X
	if room.def.wall_mode == RoomDef.WallMode.TIDE:
		min_x = maxi(min_x, room.max_spike_depth() + SimConfig.COIN_RADIUS)
	var max_x := SimConfig.COIN_MAX_X - (min_x - SimConfig.COIN_MIN_X)
	var span_x := max_x - min_x + 1
	var span_y := SimConfig.COIN_MAX_Y - SimConfig.COIN_MIN_Y + 1
	var x := min_x + _rng.next_below(span_x)
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
