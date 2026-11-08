extends Hazard
## A spiked ball that flies in straight lines and bounces off the walls,
## ceiling and floor (Bramble Ball; Pumpkin Bounce is the same with a skin).
## It never reads the bird, so its path is fixed once it starts.

const RADIUS := 20 * SimConfig.SUB
const SPEED_X := 3 * SimConfig.SUB
const SPEED_Y := 2 * SimConfig.SUB + 32
## Keep clear of the edge spikes so it never hides behind them.
const MARGIN := 44 * SimConfig.SUB

var x := 0
var y := 0
var vx := 0
var vy := 0


func _init() -> void:
	kind = "bouncer"


func setup(sim: GameSim, rng: SimRng) -> void:
	# Start in the half of the room away from the bird, moving away from it.
	var bird_left := sim.state.x < SimConfig.WORLD_W / 2
	x = (SimConfig.WORLD_W * 3 / 4) if bird_left else (SimConfig.WORLD_W / 4)
	y = MARGIN + RADIUS + rng.next_below(SimConfig.WORLD_H - 2 * (MARGIN + RADIUS))
	vx = SPEED_X if bird_left else -SPEED_X
	vy = SPEED_Y if rng.next_below(2) == 0 else -SPEED_Y


func step(sim: GameSim) -> void:
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
	var top := MARGIN + RADIUS
	var bottom := SimConfig.WORLD_H - MARGIN - RADIUS
	if y < top:
		y = 2 * top - y
		vy = absi(vy)
	elif y > bottom:
		y = 2 * bottom - y
		vy = -absi(vy)


func kills(sim: GameSim) -> bool:
	return sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, vx, vy])
