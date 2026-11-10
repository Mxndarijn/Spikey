extends Hazard
## A spiked ball that flies in straight lines and bounces off the walls,
## ceiling and floor (Bramble Ball; Pumpkin Bounce is the same with a skin).
## It never reads the bird, so its path is fixed once it starts.
##
## Bramble's other variants extend it: Twin Brambles uses two smaller ones in
## the upper and lower lanes; Splitting, Rev-Up, Curious and Heavy Bramble are
## subclasses that change how the ball moves.

## Where it starts: anywhere moving up or down (ANY), in the upper half moving
## down (UPPER) or in the lower half moving up (LOWER). The two lanes start at
## different distances from the bird so twins never start on top of each other.
enum Lane { ANY, UPPER, LOWER }

const RADIUS := 20 * SimConfig.SUB
const SPEED_X := 3 * SimConfig.SUB
const SPEED_Y := 2 * SimConfig.SUB + 32
## Keep clear of the edge spikes so it never hides behind them.
const MARGIN := 44 * SimConfig.SUB
## Twin Brambles' ball size.
const TWIN_RADIUS := 15 * SimConfig.SUB

var radius := RADIUS
var lane: int = Lane.ANY
var x := 0
var y := 0
var vx := 0
var vy := 0


func _init(p_radius: int = RADIUS, p_lane: int = Lane.ANY) -> void:
	kind = "bouncer"
	radius = p_radius
	lane = p_lane


func setup(sim: GameSim, rng: SimRng) -> void:
	# Start in the half of the room away from the bird, moving away from it.
	var bird_left := sim.state.x < SimConfig.WORLD_W / 2
	var top := MARGIN + radius
	var span := SimConfig.WORLD_H - 2 * top
	match lane:
		Lane.UPPER:
			x = (SimConfig.WORLD_W * 3 / 4) if bird_left else (SimConfig.WORLD_W / 4)
			y = top + rng.next_below(span / 2)
			vy = SPEED_Y
		Lane.LOWER:
			x = (SimConfig.WORLD_W * 5 / 8) if bird_left else (SimConfig.WORLD_W * 3 / 8)
			y = top + span / 2 + rng.next_below(span / 2)
			vy = -SPEED_Y
		_:
			x = (SimConfig.WORLD_W * 3 / 4) if bird_left else (SimConfig.WORLD_W / 4)
			y = top + rng.next_below(span)
			vy = SPEED_Y if rng.next_below(2) == 0 else -SPEED_Y
	vx = SPEED_X if bird_left else -SPEED_X


func step(sim: GameSim) -> void:
	move(sim)


## Moves one step and bounces off the edges. True if it bounced.
func move(sim: GameSim) -> bool:
	x += vx
	y += vy
	var side := bounce_sides(sim)
	var top := bounce_top()
	var bottom := bounce_bottom()
	return side or top or bottom


func bounce_sides(sim: GameSim) -> bool:
	var left := sim.room.wall_left() + radius
	var right := sim.room.wall_right() - radius
	if x < left:
		x = 2 * left - x
		vx = absi(vx)
		return true
	if x > right:
		x = 2 * right - x
		vx = -absi(vx)
		return true
	return false


func bounce_top() -> bool:
	if y < top_y():
		y = 2 * top_y() - y
		vy = absi(vy)
		return true
	return false


func bounce_bottom() -> bool:
	if y > bottom_y():
		y = 2 * bottom_y() - y
		vy = -absi(vy)
		return true
	return false


func top_y() -> int:
	return MARGIN + radius


func bottom_y() -> int:
	return SimConfig.WORLD_H - MARGIN - radius


func kills(sim: GameSim) -> bool:
	return sim.bird_touches_circle(x, y, radius)


## False for balls that steer, speed up, split or fall (the subclasses):
## near_row() can only follow a straight bouncing path.
func straight_path() -> bool:
	return true


## Plays the straight path forward on copies of the position (the walls as
## they stand now) and checks it against height `y`.
func near_row(sim: GameSim, p_y: int, half: int, from: int, to: int) -> bool:
	if not straight_path():
		return false
	var keep_x := x
	var keep_y := y
	var keep_vx := vx
	var keep_vy := vy
	var out := false
	for k in to:
		move(sim)
		if k + 1 >= from and absi(y - p_y) < radius + half:
			out = true
			break
	x = keep_x
	y = keep_y
	vx = keep_vx
	vy = keep_vy
	return out


func checksum(h: int) -> int:
	return mix_all(h, [x, y, vx, vy])
