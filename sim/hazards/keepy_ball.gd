extends Hazard
## Keepy-Uppy's soft ball (Summer's beach ball is a skin). It drops in from
## above the ceiling and falls slowly; every bump from the bird kicks it up
## (sideways by where it was hit) and pays a coin. It bounces off the walls and
## the ceiling; when it reaches the floor it is gone. Safe.

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

var x := 0
var y := -RADIUS
var vx := 0
var vy := 0
var cooldown := 0
var bumps := 0


func _init() -> void:
	kind = "keepy_ball"


func setup(_sim: GameSim, rng: SimRng) -> void:
	x = MIN_X + rng.next_below(MAX_X - MIN_X + 1)
	y = -RADIUS


func step(sim: GameSim) -> void:
	if cooldown > 0:
		cooldown -= 1
	vy = mini(vy + GRAVITY, MAX_VY)
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
		alive = false


func touch(sim: GameSim) -> void:
	if cooldown > 0 or not sim.bird_touches_circle(x, y, RADIUS):
		return
	# Contact normal from the bird to the ball: the side it was hit on sets vx.
	var dx := x - sim.state.x
	var reach := SimConfig.BIRD_RADIUS + RADIUS
	vx = clampi(dx, -reach, reach) * KICK_VX / reach
	vy = -KICK_VY
	# Lift it clear above the bird so they do not stay overlapped.
	var above := sim.state.y - reach
	if y > above:
		y = above
	cooldown = COOLDOWN
	bumps += 1
	sim.collect_coin(x, y)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, vx, vy, cooldown, bumps])
