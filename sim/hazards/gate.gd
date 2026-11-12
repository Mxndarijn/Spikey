extends Hazard
## One shutter column (Shutter Gates): a full-height bar with a gap that slides
## up and down. Both parts of the bar kill; the gap is the way through.

const HALF_W := 8 * SimConfig.SUB
## The gap is this tall (the bird is 28 px), or SMALL_GAP (single small gate).
const GAP := 176 * SimConfig.SUB
const SMALL_GAP := 90 * SimConfig.SUB
## The gap's centre ping-pongs between these heights (the gap's edges stay
## 40 px clear of the ceiling and floor lines).
const GAP_MIN_Y := 162 * SimConfig.SUB
const GAP_MAX_Y := 478 * SimConfig.SUB
## The bar runs from the ceiling line to the floor line.
const TOP := SimConfig.KILL_TOP
const BOTTOM := SimConfig.KILL_BOTTOM

## The second gate follows the first this many steps behind, so the two gaps
## stay close (about 35 px apart at most) and form one moving tunnel.
const LAG := 40
## No spike on the wall ahead within this of where the gap next to it will be.
const WALL_CLEAR := 80 * SimConfig.SUB
## A player holding height hops about 60 px over the line they hold: aim the
## gap at the middle of that.
const ARRIVAL_HOVER := 30 * SimConfig.SUB
## An exit is only planned within this of where the gap of the last gate before
## its wall will be when the bird comes through it (about 27 steps from the
## wall: one hop up, or a short drop).
const EXIT_REACH := 80 * SimConfig.SUB
## A small gate plans no exit below this: a revived bird (at BIRD_START_Y)
## can't drop through its window to an open exit lower down in one crossing.
const SMALL_EXIT_MAX_Y := 490 * SimConfig.SUB
## Generated gates (wide()): slack on each side of the band a bird holding its
## height anywhere in the exit sweeps, for the window's own motion while the
## bird passes; the window is that band plus the slack, for the whole room.
const GEN_SLACK := 8 * SimConfig.SUB
const GEN_GAP := (
	2 * SimConfig.EXIT_FIT
	+ FairLanes.FIRST_HOP
	+ 2 * (SimConfig.BIRD_RADIUS + VariantParams.MARGIN)
	+ 2 * GEN_SLACK
)
## A generated gate's window centre ranges this far past the ceiling and floor
## lines' reach (its edge may pass behind them), so it can sit on the band of
## the highest and lowest planned heights.
const GEN_LO_Y := 96 * SimConfig.SUB
const GEN_HI_Y := 500 * SimConfig.SUB
## A generated pair's follower is this many steps behind: as long as the bird
## takes from one gate to the next (100 px), so both windows are where the
## leader's was when the bird passes them.
const GEN_LAG := 25

## Column centre x.
var x := 0
## Follows the gate before it in the room (same period, LAG behind).
var follows := false
## The leader's partner gate (found at setup), or null.
var partner: Hazard = null
## Steps per up-and-down cycle.
var period := 400
## Offset into the cycle, drawn at setup.
var phase := 0
## Gap centre right now.
var gap_y := 0
## How tall the gap is.
var gap_size := GAP
## The gap centre's range (GAP_MIN_Y..GAP_MAX_Y, wider for a generated gate).
var lo_y := GAP_MIN_Y
var hi_y := GAP_MAX_Y
## Steps the follower runs behind its leader.
var lag := LAG


func _init(p_x: int = 0, p_period: int = 400, p_follows: bool = false, p_gap: int = GAP) -> void:
	kind = "gate"
	x = p_x
	period = p_period
	follows = p_follows
	gap_size = p_gap


## The gap starts at the bird's height (it just came in at a wall and can't
## slow down), moving up or down at random.
func setup(sim: GameSim, rng: SimRng) -> void:
	partner = null
	# Hazards are set up in order, so the follower finds the leader (already
	# set up) and links both ways.
	for h in sim.room.hazards:
		if follows and h != self and h.kind == kind:
			partner = h
			h.partner = self
	if follows and partner != null:
		period = partner.period
		# Out of a portal the leader timed its own gap for the bird; when this
		# gate is the nearer one, shift the pair so this gap is the one there.
		if sim.state.started and absi(x - sim.state.x) < absi(partner.x - sim.state.x):
			var shift: int = _lead(sim, partner.x) - (_lead(sim, x) - partner.lag)
			partner.phase = posmod(partner.phase + shift, period)
			partner._place()
		lag = partner.lag
		phase = posmod(partner.phase - lag, period)
		_place()
		return
	# Out of a portal: the gap reaches the bird's height (the middle of the
	# hops a player holding height makes) when the bird gets to this gate
	# (the follower shifts it if it is the nearer one), so a player still
	# reading the room flies straight through.
	var aim := FairLanes.entry_y(sim)
	var lead := 0
	if sim.state.started:
		aim -= ARRIVAL_HOVER * sim.room.gravity
		lead = _lead(sim, x)
	var down := rng.next_below(2) == 0
	# A small gate the bird starts in front of or inside (the single small gate
	# stands where a practice run starts): the window is centred on the first
	# hop while the bird passes through the column.
	if not sim.state.started and gap_size < GAP:
		var through := _start_crossing(sim)
		if not through.is_empty():
			aim = through[0]
			lead = through[1]
	phase = _phase_for(aim, lead, down)
	_place()


## Before the first tap: the middle of the bird's heights while its first hop
## (FairLanes.start_path) overlaps this column, and the room step at the middle
## of that stretch, as [y, step]; empty if the hop does not reach the column.
func _start_crossing(sim: GameSim) -> PackedInt32Array:
	var path := FairLanes.start_path(sim)
	var reach := HALF_W + SimConfig.BIRD_RADIUS
	var first := -1
	var last := -1
	var low := 0
	var high := 0
	for k in path.size() / 2:
		if absi(path[2 * k] - x) >= reach:
			if first >= 0:
				break
			continue
		var y := path[2 * k + 1]
		if first < 0:
			first = k
			low = y
			high = y
		last = k
		low = mini(low, y)
		high = maxi(high, y)
	if first < 0:
		return PackedInt32Array()
	# Path step k is room step k + 1.
	return PackedInt32Array([(low + high) / 2, (first + last) / 2 + 1])


## Steps until the bird reaches a gate at `gate_x`.
static func _lead(sim: GameSim, gate_x: int) -> int:
	return absi(gate_x - sim.state.x) / SimConfig.SPEED_X


func step(_sim: GameSim) -> void:
	_place()


## Makes this a generated gate: the window is GEN_GAP for the whole room, its
## centre ranges over GEN_LO_Y..GEN_HI_Y, and a follower runs GEN_LAG behind.
## Before setup.
func wide() -> Hazard:
	gap_size = GEN_GAP
	lo_y = GEN_LO_Y
	hi_y = GEN_HI_Y
	lag = GEN_LAG
	return self


## Generated gates, out of a portal (`gates` set up, the leader first): moves
## the pair's timing, from the leader's drawn phase on, one step at a time, to
## the first phase where every window holds the band a bird holding its height
## anywhere in the exit sweeps (VariantParams.hold_top / hold_bottom) at every
## step of the hold (VariantCheck.HOLD_STEPS) it flies past that gate. The
## windows never change size: only their timing is chosen, once. No RNG.
## False if no phase does (VariantCheck then throws the layout away).
static func fit_arrival(sim: GameSim, p: VariantParams, gates: Array[Hazard]) -> bool:
	if not p.arriving:
		return true
	var lead: Hazard = gates[0]
	for d in lead.period:
		var ph := posmod(lead.phase + d, lead.period)
		if _fits(sim, p, gates, ph):
			for g in gates:
				g.phase = posmod(ph - (g.lag if g.follows else 0), g.period)
				g._place()
			return true
	return false


## Whether leader phase `ph` keeps every window round the hold band (fit_arrival).
static func _fits(sim: GameSim, p: VariantParams, gates: Array[Hazard], ph: int) -> bool:
	var reach := HALF_W + SimConfig.BIRD_RADIUS
	for g in gates:
		var gph := posmod(ph - (g.lag if g.follows else 0), g.period)
		for k in range(1, VariantCheck.HOLD_STEPS + 1):
			if absi(FairLanes.arrival_x(sim, k) - g.x) >= reach:
				continue
			var mid: int = g.lo_y + SimTrig.ping_pong(k + gph, g.period, g.hi_y - g.lo_y)
			if mid - g.gap_size / 2 > p.hold_top() or mid + g.gap_size / 2 < p.hold_bottom():
				return false
	return true


func _place() -> void:
	gap_y = gap_at(t)


## Gap centre at room step `tick`.
func gap_at(tick: int) -> int:
	return lo_y + SimTrig.ping_pong(tick + phase, period, hi_y - lo_y)


## The phase that puts this gate's gap centre at `y` (kept inside its range) at
## room step `tick`, moving down the screen then (`down`) or up.
func _phase_for(y: int, tick: int, down: bool) -> int:
	var span := hi_y - lo_y
	var at := clampi(y - lo_y, 0, span)
	var half := period / 2
	var rising_phase := at * half / span
	return posmod((rising_phase if down else period - rising_phase) - tick, period)


## The gate (this one or its partner) the bird passes last before wall `side`.
func _last_before(side: int) -> Hazard:
	if partner != null and (partner.x > x) == (side == 1):
		return partner
	return self


## Room steps from now until the bird, flying straight on, is level with `gate`
## on its way into wall `side`.
func _steps_to_pass(sim: GameSim, gate: Hazard, side: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var wall_x := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	return maxi(sim.steps_to_exit(side) - absi(wall_x - gate.x) / SimConfig.SPEED_X, 0)


## The leader keeps the wall ahead open where the gate next to it will have
## its gap when the bird gets there.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	if follows:
		return mask
	var s := sim.state
	var near := _last_before(side)
	var steps := absi(near.x - s.x) / SimConfig.SPEED_X
	var gap: int = near.gap_at(t + steps)
	var out := mask
	for slot in SimConfig.SLOT_COUNT:
		if absi(SimConfig.slot_center_y(slot) - gap) < WALL_CLEAR:
			out &= ~(1 << slot)
	return out


## An exit goes only where the bird can get to from the gap of the last gate
## before its wall: within EXIT_REACH of where that gap will be when the bird
## comes through it on its way to the exit. A small gate also keeps exits
## above SMALL_EXIT_MAX_Y.
func blocks_exit(sim: GameSim, side: int, y: int) -> bool:
	if gap_size < GAP and y > SMALL_EXIT_MAX_Y:
		return true
	# The leader answers for the pair.
	if follows and partner != null:
		return false
	var last := _last_before(side)
	var gap: int = last.gap_at(t + _steps_to_pass(sim, last, side))
	return absi(y - gap) > EXIT_REACH


func gap_top() -> int:
	return gap_y - gap_size / 2


func gap_bottom() -> int:
	return gap_y + gap_size / 2


func kills(sim: GameSim) -> bool:
	if sim.bird_touches_rect(x - HALF_W, TOP, x + HALF_W, gap_top()):
		return true
	return sim.bird_touches_rect(x - HALF_W, gap_bottom(), x + HALF_W, BOTTOM)


func checksum(h: int) -> int:
	var out := mix_all(h, [x, period, phase, gap_y, int(follows), gap_size])
	if lo_y != GAP_MIN_Y or hi_y != GAP_MAX_Y or lag != LAG:
		out = mix_all(out, [lo_y, hi_y, lag])
	return out
