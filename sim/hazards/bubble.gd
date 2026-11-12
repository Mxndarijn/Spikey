extends Hazard
## A bubble rising from the floor (Bubble Lift). Fly into it and it carries the
## bird up: the bird rises with it (its own gravity ignored) while x keeps
## moving, until the player taps (pops it) or it pops just below the ceiling.
## Popped bubbles come back from below the floor in a new column. Safe.
##
## Variants: a bubble can be bigger and slower (Giants), carry a coin (Coin
## Bubbles: taken by touching it, back on the next rise) or be spiked (Spiky
## Bubbles: it kills and never carries; before each rise it waits under the
## floor for WARN steps while its column is marked).

const SUB := SimConfig.SUB
const RADIUS := 22 * SUB
const RISE := 96
## Giants: a bigger, slower bubble.
const GIANT_RADIUS := 38 * SUB
const GIANT_RISE := 56
## Spiky Bubbles: a spiked bubble's size (its spike tips; all of it kills).
const SPIKED_RADIUS := 24 * SUB
## Steps a spiked bubble waits under the floor, its column marked, before it
## rises (a second to read it).
const WARN := 60
## Pops when its top reaches this line, so a carried bird stays clear of the
## ceiling.
const POP_TOP := SimConfig.KILL_TOP + 10 * SUB
const MIN_X := 90 * SUB
const MAX_X := 270 * SUB
## Steps after a pop before this bubble can catch the bird again.
const REGRAB := 12

var x := 0
var y := 0
var vy := -RISE
## Column the bubble respawns in (redrawn every wall bounce).
var next_x := 0
var carrying := false
## Which bubble of the room this is (spreads the starting heights).
var lane := 0
var cooldown := 0
## Steps since it last popped (the painter shows a pop ring).
var since_pop := 1000
var radius := RADIUS
## Spiky Bubbles: this one kills and never carries.
var spiked := false
## Spiked: steps it still waits under the floor before rising (0 = rising).
var wait := 0
## Spiked: extra steps it waits before its first rise (spreads them out).
var delay := 0
## Coin Bubbles: this one brings a coin up on every rise.
var coin_bubble := false
## Coin Bubbles: the coin is still inside.
var has_coin := false


func _init(p_lane: int = 0, p_radius: int = RADIUS, p_rise: int = RISE) -> void:
	kind = "bubble"
	lane = p_lane
	radius = p_radius
	vy = -p_rise


## Makes it a spiked bubble that first rises after WARN + `p_delay` steps.
func spiky(p_delay: int) -> Hazard:
	spiked = true
	radius = SPIKED_RADIUS
	delay = p_delay
	return self


## Makes it a coin bubble.
func with_coin() -> Hazard:
	coin_bubble = true
	return self


func setup(_sim: GameSim, rng: SimRng) -> void:
	x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)
	next_x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)
	y = (520 - lane * 170) * SUB
	has_coin = coin_bubble
	if spiked:
		# It starts under the floor, its column marked, so it never surprises
		# a bird that has just started or come out of a portal.
		y = SimConfig.WORLD_H + radius
		wait = WARN + delay


func step(_sim: GameSim) -> void:
	if cooldown > 0:
		cooldown -= 1
	since_pop = mini(since_pop + 1, 1000)
	if wait > 0:
		wait -= 1
		return
	y += vy
	if y - radius <= POP_TOP:
		pop()


## Bursts the bubble (releasing the bird) and sends it back below the floor.
func pop() -> void:
	carrying = false
	since_pop = 0
	cooldown = REGRAB
	x = next_x
	y = SimConfig.WORLD_H + radius
	has_coin = coin_bubble
	if spiked:
		wait = WARN


func kills(sim: GameSim) -> bool:
	return spiked and wait == 0 and sim.bird_touches_circle(x, y, radius)


func touch(sim: GameSim) -> void:
	if spiked:
		return
	if carrying:
		_hold(sim)
	elif cooldown == 0 and sim.bird_touches_circle(x, y, radius - SimConfig.BIRD_RADIUS):
		if not _other_carrying(sim):
			carrying = true
			_hold(sim)
	_take_coin(sim)


func _other_carrying(sim: GameSim) -> bool:
	for h in sim.room.hazards:
		if h != self and h.alive and h.kind == "bubble" and h.carrying:
			return true
	return false


## Coin Bubbles: touching the coin takes it, while it is in the coin band.
func _take_coin(sim: GameSim) -> void:
	if not has_coin or not coin_in_reach():
		return
	if sim.bird_touches_circle(x, y, SimConfig.COIN_RADIUS):
		has_coin = false
		sim.collect_coin(x, y)


## Whether the coin can be taken here: inside the coin band, clear of the
## ceiling and floor.
func coin_in_reach() -> bool:
	return y >= SimConfig.COIN_MIN_Y and y <= SimConfig.COIN_MAX_Y


func _hold(sim: GameSim) -> void:
	x = sim.state.x
	sim.state.y = y
	sim.state.vy = vy


func on_bounce(_sim: GameSim, rng: SimRng) -> void:
	next_x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)


func on_flap(_sim: GameSim) -> void:
	if carrying:
		pop()


func checksum(h: int) -> int:
	return mix_all(
		h,
		[
			x,
			y,
			vy,
			next_x,
			int(carrying),
			lane,
			cooldown,
			since_pop,
			radius,
			int(spiked),
			wait,
			int(has_coin)
		]
	)


## A spiked bubble under the floor (waiting, or rising but not yet over the
## floor line): its column, for the rise. Shown from 3 * WARN steps before it
## rises (before that its glow is too faint to tell the column:
## bubble_painter.gd).
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if not spiked or wait > 3 * WARN or y - radius < SimConfig.KILL_BOTTOM:
		return
	var eta := wait + (y - radius - SimConfig.KILL_BOTTOM) / -vy
	var dur := (SimConfig.KILL_BOTTOM + 2 * radius - POP_TOP) / -vy + 1
	add_warning(
		out, x - radius, POP_TOP - radius, x + radius, SimConfig.WORLD_H, eta, dur, WARN_KILL
	)
