extends Hazard
## A spiked ball that flies in straight lines and bounces off the walls,
## ceiling and floor (Bramble Ball; Pumpkin Bounce is the same with a skin).
## It never reads the bird, so its path is fixed once it starts. It bounces
## off an open or ghost exit's mouth (ExitZone) as off the wall.
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
## adjust_wall: the ball escorts the bird when it stays within this of it in x
## (beyond both sizes) all the way to the wall; when that began no more than
## ESCORT_REACT steps after the bounce, the bird is held on its side of the
## ball (the anchor's) and the free run stays there.
const ESCORT_MARGIN := 4 * SimConfig.SUB
const ESCORT_REACT := SimConfig.ARRIVAL_BLIND
## adjust_wall: heights the ball crosses near the bird from ARRIVE_BEFORE steps
## before it reaches the wall to ARRIVE_AFTER after (turning back) are not a
## way through.
const ARRIVE_BEFORE := 24
const ARRIVE_AFTER := 6

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


## Generated Bramble Ball's fallback: the start heights it can take in its
## lane, [lowest y, highest y] (as setup draws them).
func y_range() -> PackedInt32Array:
	var top := MARGIN + radius
	var span := SimConfig.WORLD_H - 2 * top
	match lane:
		Lane.UPPER:
			return PackedInt32Array([top, top + span / 2 - 1])
		Lane.LOWER:
			return PackedInt32Array([top + span / 2, top + span - 1])
	return PackedInt32Array([top, top + span - 1])


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
	var out := false
	if x < left:
		x = 2 * left - x
		vx = absi(vx)
		out = true
	elif x > right:
		x = 2 * right - x
		vx = -absi(vx)
		out = true
	# An open or ghost exit's mouth is part of the wall (ExitZone).
	var b := ExitZone.bounce(sim, x, y, vx, vy, radius)
	if not b.is_empty():
		x = b[0]
		y = b[1]
		vx = b[2]
		vy = b[3]
		out = true
	return out


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


## True if the ball's path doesn't depend on the bird, so adjust_wall can play
## it forward (path_step on saved fields). The straight ones; Heavy and Rev-Up
## too (falling, speeding up per bounce); never Curious (it steers to the bird).
func predictable() -> bool:
	return straight_path()


## One step of the path, as step() moves the ball.
func path_step(sim: GameSim) -> void:
	move(sim)


func path_save() -> Array[int]:
	return [x, y, vx, vy]


func path_restore(a: Array[int]) -> void:
	x = a[0]
	y = a[1]
	vx = a[2]
	vy = a[3]


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


## Keeps a way past a ball that escorts the bird to the wall it flies to (its
## path is fixed, the bird's x too): a free run as wide as the room's gap (or
## the widest the ball leaves) clear of the ball as the bird gets there, and on
## the anchor's side of it when the escort began within ESCORT_REACT steps.
## No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	if not predictable():
		return mask
	var at := sim.steps_to_wall(side)
	var dir := 1 if side == 1 else -1
	var near := radius + SimConfig.BIRD_RADIUS + ESCORT_MARGIN
	var keep := path_save()
	var start := -1
	var start_y := 0
	var end_y := 0
	var blocked := 0
	for k in range(1, at + ARRIVE_AFTER + 1):
		path_step(sim)
		var steps := k if k <= at else 2 * at - k
		var by := sim.state.x + dir * steps * SimConfig.SPEED_X
		var close := absi(x - by) < near
		if k <= at:
			if close:
				if start < 0:
					start = k
					start_y = y
			else:
				start = -1
			end_y = y
		# Near the wall the ball crosses heights the bird can't then pass at.
		if close and k >= at - ARRIVE_BEFORE:
			for slot in SimConfig.SLOT_COUNT:
				if absi(SimConfig.slot_center_y(slot) - y) < near:
					blocked |= 1 << slot
	path_restore(keep)
	if start >= 0:
		var above := sim.state.anchor_y < start_y
		for slot in SimConfig.SLOT_COUNT:
			var sy := SimConfig.slot_center_y(slot)
			if absi(sy - end_y) < near:
				blocked |= 1 << slot
			elif start <= ESCORT_REACT and (sy < end_y) != above:
				blocked |= 1 << slot
	if blocked == 0:
		return mask
	var safe := ((1 << SimConfig.SLOT_COUNT) - 1) & ~blocked
	var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
	return RoomRules.keep_run(mask, need, safe)


func checksum(h: int) -> int:
	return mix_all(h, [x, y, vx, vy])
