extends Hazard
## A spiked drop that falls straight down a column (Spike Rain; Orchard Drop's
## pinecone and Winter's icicle are skins). First the column is marked on the
## ceiling for `warn` steps, then it falls. Only the falling drop kills.
## Columns come from the drop's own SimRng, seeded once in setup().
##
## Spike Rain's variants tune it (warning time, size, a fixed column) and pick
## a style: SHATTER breaks into two shards that skip along the floor, WOBBLE
## sways from side to side as it falls, STAKE lands on a floor spike's tip and
## makes that spike grow for a while. A falling drop (or its shards) breaks on
## an open or ghost exit's mouth (ExitZone).
##
## Fair: a wall drawn while drops come keeps a way past them (adjust_wall).

enum Phase { WAIT, WARN, FALL, STAKE }
enum Style { PLAIN, SHATTER, WOBBLE, STAKE }

const SUB := SimConfig.SUB
const RADIUS := 10 * SUB
const WARN := 45
const MIN_X := 50 * SUB
const MAX_X := 310 * SUB
const TOP := SimConfig.KILL_TOP

## WOBBLE: the drop swings SWAY either side of its column every SWAY_PERIOD steps.
const SWAY := 22 * SUB
const SWAY_PERIOD := 40

## SHATTER: two shards start this far above the floor line, fly apart at
## SHARD_VX, hop up at SHARD_VY under SHARD_GRAVITY and skip off SHARD_FLOOR.
const SHARD_RADIUS := 6 * SUB
const SHARD_START := 10 * SUB
const SHARD_VX := 5 * SUB
const SHARD_VY := -4 * SUB
const SHARD_GRAVITY := 19
const SHARD_FLOOR := SimConfig.KILL_BOTTOM - 6 * SUB
const SHARD_LIFE := 26

## STAKE: the floor is drawn as a row of FLOOR_SPIKES spikes, each FLOOR_SPIKE_W
## wide, standing on FLOOR_BASE. A stake falls onto one of the middle ones
## (never the two at the walls), which then grows STAKE_HEIGHT taller over
## STAKE_GROW steps, stays, and shrinks back over STAKE_SINK steps.
const FLOOR_SPIKES := 9
const FLOOR_SPIKE_W := SimConfig.WORLD_W / FLOOR_SPIKES
const FLOOR_BASE := SimConfig.WORLD_H - 8 * SUB
const STAKE_HEIGHT := 40 * SUB
const STAKE_GROW := 8
const STAKE_SINK := 15
const STAKE_STEPS := 135

## A wall keeps a free run whose heights no drop passes in front of (by
## MARGIN) from WALL_FROM to WALL_TO steps around the bird's arrival there,
## flying in and back out.
const WALL_FROM := -30
const WALL_TO := 12
const MARGIN := 4 * SUB

var x := 0
var y := TOP
var phase := Phase.WAIT
## Steps left in the current phase (WAIT, WARN and STAKE).
var timer := 0
## Falling speed per step.
var speed := 10 * SUB
## Steps between a drop leaving the room and the next warning.
var gap := 25
## Steps before the first warning (spreads several drops in one room).
var delay := 0
## Steps the column is marked before the drop falls.
var warn := WARN
var radius := RADIUS
var style := Style.PLAIN
## A fixed column (Sweep), or -1 for a random one each time. A fixed column
## swaps to the other side of the room after every fall, so a row of drops
## sweeps one way and then back.
var column := -1
## The column of this fall (WOBBLE sways around it).
var base_x := 0
## Steps since this fall began.
var fall_t := 0
## SHATTER: steps the shards have left, where they broke, how far apart they
## are, their height and their vertical speed.
var shard_t := 0
var shard_x := 0
var shard_dx := 0
var shard_y := 0
var shard_vy := 0

var _rng := SimRng.new()


func _init(
	p_delay: int = 0,
	p_speed: int = 10 * SUB,
	p_gap: int = 25,
	p_warn: int = WARN,
	p_radius: int = RADIUS,
	p_style: Style = Style.PLAIN,
	p_column: int = -1
) -> void:
	kind = "drop"
	delay = p_delay
	speed = p_speed
	gap = p_gap
	warn = p_warn
	radius = p_radius
	style = p_style
	column = p_column


func setup(_sim: GameSim, rng: SimRng) -> void:
	_rng.reseed(rng.next_u32())
	phase = Phase.WAIT
	timer = delay
	y = TOP


func step(sim: GameSim) -> void:
	if shard_t > 0:
		_step_shards()
		# Shards break on an exit's mouth (ExitZone), both at once.
		var sx := shard_x - shard_dx
		var sx2 := shard_x + shard_dx
		if (
			ExitZone.hits_circle(sim, sx, shard_y, SHARD_RADIUS)
			or ExitZone.hits_circle(sim, sx2, shard_y, SHARD_RADIUS)
		):
			shard_t = 0
	_advance(sim)


## The drop's own clock: wait, warn, fall (and land). Its columns come from
## its own RNG, so a copy stepped ahead (_blocked) meets the same drops.
func _advance(sim: GameSim) -> void:
	match phase:
		Phase.WAIT:
			timer -= 1
			if timer <= 0:
				phase = Phase.WARN
				timer = warn
				base_x = _next_column()
				x = base_x
				y = TOP
				fall_t = 0
		Phase.WARN:
			timer -= 1
			if timer <= 0:
				phase = Phase.FALL
				y = TOP
		Phase.FALL:
			y += speed
			fall_t += 1
			if style == Style.WOBBLE:
				x = base_x + SWAY * SimTrig.sin_t(fall_t * SimTrig.TURN / SWAY_PERIOD) / SimTrig.ONE
			if style == Style.SHATTER and y + radius >= SimConfig.KILL_BOTTOM:
				shard_t = SHARD_LIFE
				shard_x = x
				shard_dx = 0
				shard_y = SimConfig.KILL_BOTTOM - SHARD_START
				shard_vy = SHARD_VY
				phase = Phase.WAIT
				timer = gap
			elif style == Style.STAKE and y + radius >= SimConfig.KILL_BOTTOM:
				y = SimConfig.KILL_BOTTOM - radius
				phase = Phase.STAKE
				timer = STAKE_STEPS
			elif y - radius > SimConfig.WORLD_H or ExitZone.hits_circle(sim, x, y, radius):
				# Out of the room, or broken on an exit's mouth (ExitZone).
				phase = Phase.WAIT
				timer = gap
		Phase.STAKE:
			timer -= 1
			if timer <= 0:
				phase = Phase.WAIT
				timer = gap


## Keeps a way past the drops on the wall the bird flies to: a free run as
## wide as the room's gap (or the widest the drops leave) whose heights no
## drop falls past in front of the bird around its arrival there
## (WALL_FROM..WALL_TO). A drop's columns come from its own RNG and its timing
## from the clock, so its path is stepped ahead on a copy; the bird's x is
## fixed by time too, so every player of a seed gets the same wall. The room's
## first drop keeps the way past all of them. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	if _first_drop(sim) != self:
		return mask
	var blocked := 0
	for h in sim.room.hazards:
		if h.alive and h.get_script() == get_script():
			blocked |= h._blocked(sim, side)
	var safe := ((1 << SimConfig.SLOT_COUNT) - 1) & ~blocked
	var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
	return RoomRules.keep_run(mask, need, safe)


func _first_drop(sim: GameSim) -> Hazard:
	for h in sim.room.hazards:
		if h.alive and h.get_script() == get_script():
			return h
	return null


## The slots of wall `side` this drop falls past in front of the bird around
## its arrival there. Steps the drop ahead and puts it back.
func _blocked(sim: GameSim, side: int) -> int:
	var at := sim.steps_to_wall(side)
	var r := SimConfig.BIRD_RADIUS
	var edge := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	var into := -1 if side == 1 else 1
	var reach := radius + r + MARGIN
	var keep := [x, y, phase, timer, base_x, fall_t, column, shard_t, shard_x, shard_dx, shard_y]
	keep.append(shard_vy)
	var keep_rng := SimCopy.copy_rng(_rng)
	var blocked := 0
	for k in range(1, at + WALL_TO + 1):
		_advance(sim)
		var d := k - at
		if d < WALL_FROM or phase != Phase.FALL:
			continue
		var bx := edge + into * absi(d) * SimConfig.SPEED_X
		for slot in SimConfig.SLOT_COUNT:
			var dx := bx - x
			var dy := SimConfig.slot_center_y(slot) - y
			if dx * dx + dy * dy < reach * reach:
				blocked |= 1 << slot
	x = keep[0]
	y = keep[1]
	phase = keep[2]
	timer = keep[3]
	base_x = keep[4]
	fall_t = keep[5]
	column = keep[6]
	shard_t = keep[7]
	shard_x = keep[8]
	shard_dx = keep[9]
	shard_y = keep[10]
	shard_vy = keep[11]
	_rng = keep_rng
	return blocked


func _next_column() -> int:
	if column >= 0:
		var c := column
		column = SimConfig.WORLD_W - column
		return c
	if style == Style.STAKE:
		return FLOOR_SPIKE_W / 2 + FLOOR_SPIKE_W * (1 + _rng.next_below(FLOOR_SPIKES - 2))
	if style == Style.WOBBLE:
		return MIN_X + SWAY + _rng.next_below(MAX_X - MIN_X - 2 * SWAY + 1)
	return MIN_X + _rng.next_below(MAX_X - MIN_X + 1)


func _step_shards() -> void:
	shard_t -= 1
	shard_dx += SHARD_VX
	shard_vy += SHARD_GRAVITY
	shard_y += shard_vy
	if shard_y > SHARD_FLOOR:
		shard_y = SHARD_FLOOR
		shard_vy = -absi(shard_vy) * 45 / 100


func warning() -> bool:
	return phase == Phase.WARN


func falling() -> bool:
	return phase == Phase.FALL


func staked() -> bool:
	return phase == Phase.STAKE


## 0..1024 how far along the warning is (painters grow the mark or shake).
func warn_progress() -> int:
	if phase != Phase.WARN:
		return 0
	return SimTrig.ONE * (warn - timer) / warn


## STAKE: how much taller than the others the hit floor spike is now.
func stake_height() -> int:
	if phase != Phase.STAKE:
		return 0
	var age := STAKE_STEPS - timer
	if age < STAKE_GROW:
		return STAKE_HEIGHT * (age + 1) / STAKE_GROW
	if timer < STAKE_SINK:
		return STAKE_HEIGHT * timer / STAKE_SINK
	return STAKE_HEIGHT


## STAKE: half the base of the grown floor spike (it widens a little as it grows).
func stake_half_base() -> int:
	return FLOOR_SPIKE_W / 2 + stake_height() / 10


func kills(sim: GameSim) -> bool:
	if phase == Phase.FALL and sim.bird_touches_circle(x, y, radius):
		return true
	if shard_t > 0:
		if sim.bird_touches_circle(shard_x - shard_dx, shard_y, SHARD_RADIUS):
			return true
		if sim.bird_touches_circle(shard_x + shard_dx, shard_y, SHARD_RADIUS):
			return true
	return phase == Phase.STAKE and _touches_stake(sim)


## The grown floor spike as a triangle: tip at (base_x, KILL_BOTTOM - height),
## base corners on FLOOR_BASE. Below the floor line the bird is dead anyway.
func _touches_stake(sim: GameSim) -> bool:
	var tip_y := SimConfig.KILL_BOTTOM - stake_height()
	var dx := absi(sim.state.x - base_x)
	var dy := sim.state.y - tip_y
	var ex := stake_half_base()
	var ey := FLOOR_BASE - tip_y
	if dy >= 0 and dy <= ey and dx * ey <= ex * dy:
		return true
	# Distance from the bird's centre to the slanted side from the tip (0, 0)
	# to the base corner (ex, ey).
	var r := SimConfig.BIRD_RADIUS
	var dot := dx * ex + dy * ey
	var len2 := ex * ex + ey * ey
	if dot <= 0:
		return dx * dx + dy * dy <= r * r
	if dot >= len2:
		return false
	var cross := dx * ey - dy * ex
	return cross * cross <= r * r * len2


func checksum(h: int) -> int:
	return mix_all(
		h,
		[
			x,
			y,
			phase,
			timer,
			speed,
			gap,
			delay,
			warn,
			radius,
			style,
			column,
			base_x,
			fall_t,
			shard_t,
			shard_x,
			shard_dx,
			shard_y,
			shard_vy,
			_rng.state_checksum()
		]
	)


## While the column is marked: the column the drop falls down (as wide as its
## sway for WOBBLE), from the ceiling to the floor, for the fall. What comes
## after the landing (shards, a grown floor spike) has no mark of its own.
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if phase != Phase.WARN:
		return
	var half := radius + (SWAY if style == Style.WOBBLE else 0)
	var dur := (SimConfig.WORLD_H + radius - TOP) / speed + 1
	add_warning(out, x - half, TOP - radius, x + half, SimConfig.WORLD_H, timer, dur, WARN_KILL)
