extends Hazard
## A bubble rising from the floor (Bubble Lift). Fly into it and it carries the
## bird up: the bird rises with it (its own gravity ignored) while x keeps
## moving, until the player taps (pops it) or it pops just below the ceiling.
## Popped bubbles come back from below the floor in a new column. Safe.

const SUB := SimConfig.SUB
const RADIUS := 22 * SUB
const RISE := 96
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


func _init(p_lane: int = 0) -> void:
	kind = "bubble"
	lane = p_lane


func setup(_sim: GameSim, rng: SimRng) -> void:
	x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)
	next_x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)
	y = (520 - lane * 170) * SUB


func step(_sim: GameSim) -> void:
	if cooldown > 0:
		cooldown -= 1
	since_pop = mini(since_pop + 1, 1000)
	y += vy
	if y - RADIUS <= POP_TOP:
		pop()


## Bursts the bubble (releasing the bird) and sends it back below the floor.
func pop() -> void:
	carrying = false
	since_pop = 0
	cooldown = REGRAB
	x = next_x
	y = SimConfig.WORLD_H + RADIUS


func touch(sim: GameSim) -> void:
	if carrying:
		_hold(sim)
		return
	if cooldown > 0 or not sim.bird_touches_circle(x, y, RADIUS - SimConfig.BIRD_RADIUS):
		return
	for h in sim.room.hazards:
		if h != self and h.alive and h.kind == "bubble" and h.carrying:
			return
	carrying = true
	_hold(sim)


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
	return mix_all(h, [x, y, vy, next_x, int(carrying), lane, cooldown, since_pop])
