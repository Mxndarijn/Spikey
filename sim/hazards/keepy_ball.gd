extends Hazard
## Keepy-Uppy's soft ball (Summer's beach ball is a skin). It drops in from
## above the ceiling and falls slowly; every bump from the bird kicks it up
## (sideways by where it was hit) and pays a coin. It bounces off the walls and
## the ceiling; when it reaches the floor it is gone. Safe.
##
## Variants: a heavy ball (stronger pull, softer kicks: low, short bounces), and
## two balls (the second drops a while after the first; a ball that reaches
## the floor is gone until it drops in again a moment later).

const SUB := SimConfig.SUB
const RADIUS := 22 * SUB
const GRAVITY := 18
const MAX_VY := 7 * SUB
const KICK_VY := 9 * SUB
const KICK_VX := 3 * SUB
## Steps after a bump before the next one counts (one coin per bump).
const COOLDOWN := 15
const MIN_X := 120 * SUB
const MAX_X := 240 * SUB
## Heavy ball: about 60 px bounces, half a second in the air.
const HEAVY_GRAVITY := 27
const HEAVY_KICK_VY := 7 * SUB
## Two balls: the second drops this many steps after the first, and a ball
## that reaches the floor drops in again this many steps later.
const SECOND_DROP := 120
const REDROP := 90

var gravity := GRAVITY
var kick_vy := KICK_VY
## Steps left before it drops in (0: in play).
var waiting := 0
## Steps after reaching the floor before it drops in again; 0: gone for good.
var redrop := 0

var x := 0
var y := -RADIUS
var vx := 0
var vy := 0
var cooldown := 0
var bumps := 0


func _init() -> void:
	kind = "keepy_ball"


## Makes this a heavy ball.
func heavy() -> Hazard:
	gravity = HEAVY_GRAVITY
	kick_vy = HEAVY_KICK_VY
	return self


## Makes this one of several balls: it drops in after `delay` steps, and
## again REDROP steps after it reaches the floor.
func dropping(delay: int) -> Hazard:
	waiting = delay
	redrop = REDROP
	return self


func setup(_sim: GameSim, rng: SimRng) -> void:
	x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)
	y = -RADIUS


func step(sim: GameSim) -> void:
	if waiting > 0:
		waiting -= 1
		return
	if cooldown > 0:
		cooldown -= 1
	vy = mini(vy + gravity, MAX_VY)
	x += vx
	y += vy
	var left := sim.room.wall_left() + RADIUS
	var right := sim.room.wall_right() - RADIUS
	if x < left:
		x = 2 * left - x
		vx = absi(vx)
	elif x > right:
		x = 2 * right - x
		vx = -absi(vx)
	var top := SimConfig.KILL_TOP + RADIUS
	if vy < 0 and y < top:
		y = 2 * top - y
		vy = -vy
	if y + RADIUS >= SimConfig.KILL_BOTTOM:
		if redrop == 0:
			alive = false
			return
		# Off the top again, over the other half of the room.
		waiting = redrop
		x = clampi(SimConfig.WORLD_W - x, MIN_X, MAX_X)
		y = -RADIUS
		vx = 0
		vy = 0
		cooldown = 0


func touch(sim: GameSim) -> void:
	if waiting > 0 or cooldown > 0 or not sim.bird_touches_circle(x, y, RADIUS):
		return
	# Contact normal from the bird to the ball: the side it was hit on sets vx.
	var dx := x - sim.state.x
	var reach := SimConfig.BIRD_RADIUS + RADIUS
	vx = clampi(dx, -reach, reach) * KICK_VX / reach
	vy = -kick_vy
	# Lift it clear above the bird so they do not stay overlapped.
	var above := sim.state.y - reach
	if y > above:
		y = above
	cooldown = COOLDOWN
	bumps += 1
	sim.collect_coin(x, y)


func checksum(h: int) -> int:
	var out := mix_all(h, [x, y, vx, vy, cooldown, bumps])
	if gravity != GRAVITY or kick_vy != KICK_VY or redrop != 0:
		out = mix_all(out, [gravity, kick_vy, waiting, redrop])
	return out
