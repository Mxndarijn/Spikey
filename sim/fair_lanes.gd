class_name FairLanes
extends RefCounted
## Where a bird that just started, or just came out of a portal, is going to
## fly while the player can't steer yet or is still reading the room. Hazards
## placed at room start ask these so a room never kills on its first, forced
## hop or right out of a portal. Read-only: no RNG draws, no changes to the sim.

## The start lane (see blocks_start_lane): tall enough to hover in (one hop
## is about 60 px plus the bird), reaching most of the way across.
const START_LANE_H := 100 * SimConfig.SUB
const START_LANE_BELOW := 12 * SimConfig.SUB
const START_LANE_W := 150 * SimConfig.SUB
## Steps of the start path (one flap up to its peak and a little after).
const START_PATH := 32
## How high one flap lifts the bird (about 60 px).
const FIRST_HOP := SimConfig.FLAP_VY * SimConfig.FLAP_VY / (2 * SimConfig.GRAVITY)
## The arrival path (see arrival_path): its length, and how far off it
## hazards keep (the bird and the hazard each move a few pixels a step).
const ARRIVAL_PATH_TICKS := SimConfig.ARRIVAL_BLIND + 60
const ARRIVAL_PATH_MARGIN := 10 * SimConfig.SUB
## A hazard on a fixed path times itself so it stays off the arrival path for
## ARRIVAL_PATH_TICKS; if no timing does, the first that does for this long
## (the reading time and a bit). The first one, not the best, so the layouts
## ArrivalCheck tries stay different from each other.
const ARRIVAL_PATH_MIN := SimConfig.ARRIVAL_BLIND + 15
## Generated columns (Shutter Gates, Stalactite Run) keep their arrival opening
## for this many steps of the arrival path: the reading time and ArrivalCheck's
## follow time, so the bird's way back through them is open too.
const OPEN_PATH_TICKS := SimConfig.ARRIVAL_BLIND + SimConfig.ARRIVAL_FOLLOW


## Where the bird will be soon after the room starts: out of a portal the
## exit's height (SimState.anchor_y, the same for every player), or, before
## the first tap (which is a flap), half a hop over the start. Hazards that
## line a gap up with the bird use this.
static func entry_y(sim: GameSim) -> int:
	if sim.state.started:
		return sim.state.anchor_y
	return sim.state.y - FIRST_HOP / 2 * sim.room.gravity


## Out of a portal: where a player still reading the room flies, as x, y
## pairs for ARRIVAL_PATH_TICKS steps. It holds the exit's height
## (SimState.anchor_y), tapping whenever it has sunk under it (as ArrivalCheck
## plays it), and turns at the far wall.
static func arrival_path(sim: GameSim) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g := sim.room.gravity
	var hold := sim.state.anchor_y
	var y := hold
	# It comes out flying level (_arrive).
	var vy := 0
	for k in ARRIVAL_PATH_TICKS:
		if (y - hold) * g > 0 and vy * g >= 0:
			vy = SimConfig.FLAP_VY * g
		vy = clampi(vy + SimConfig.GRAVITY * g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)
		y += vy
		out.append(arrival_x(sim, k + 1))
		out.append(y)
	return out


## Whether a circle at (cx, cy) comes within ARRIVAL_PATH_MARGIN of the bird
## on `path` (arrival_path) at room step `k`.
static func arrival_path_hits(path: PackedInt32Array, k: int, cx: int, cy: int, r: int) -> bool:
	var dx := cx - path[2 * k]
	var dy := cy - path[2 * k + 1]
	var reach := SimConfig.BIRD_RADIUS + r + ARRIVAL_PATH_MARGIN
	return dx * dx + dy * dy < reach * reach


## The bird's x `k` steps after coming out of a portal, flying straight on and
## turning at the far wall.
static func arrival_x(sim: GameSim, k: int) -> int:
	var r := SimConfig.BIRD_RADIUS
	var lo := sim.room.wall_left() + r
	var span := sim.room.wall_right() - r - lo
	var at := posmod(sim.state.x + sim.state.vx * k - lo, 2 * span)
	return lo + (at if at <= span else 2 * span - at)


## Before the first tap: where the bird goes in its first START_PATH steps
## (the first tap is a flap, and the player can't steer until it peaks), as
## x, y pairs. Empty once the bird is flying. Hazards placed at room start
## keep off this path, so a room never kills on its first, forced hop.
static func start_path(sim: GameSim) -> PackedInt32Array:
	var out := PackedInt32Array()
	if sim.state.started:
		return out
	var g := SimConfig.GRAVITY * sim.room.gravity
	var x := sim.state.x
	var y := sim.state.y
	var vy := SimConfig.FLAP_VY * sim.room.gravity
	for i in START_PATH:
		vy = clampi(vy + g, -SimConfig.MAX_FALL_VY, SimConfig.MAX_FALL_VY)
		x += sim.state.vx
		y += vy
		out.append(x)
		out.append(y)
	return out


## Whether a box (corners, sub-units) comes within `margin` of the bird's
## start path.
static func start_path_hits_rect(
	sim: GameSim, x0: int, y0: int, x1: int, y1: int, margin: int
) -> bool:
	var path := start_path(sim)
	var r := SimConfig.BIRD_RADIUS + margin
	for i in range(0, path.size(), 2):
		if path[i] + r > x0 and path[i] - r < x1 and path[i + 1] + r > y0 and path[i + 1] - r < y1:
			return true
	return false


## Before the first tap: whether a box (sub-units) blocks the start lane, a
## strip START_LANE_H tall from the bird's height up, from its wall to
## START_LANE_W into the sim.room. The bird can hover in that strip while it finds
## its way, so rooms keep it clear. False once the bird is flying.
static func blocks_start_lane(sim: GameSim, x0: int, y0: int, x1: int, y1: int) -> bool:
	if sim.state.started:
		return false
	var w := START_LANE_W
	var top := sim.state.y - (START_LANE_H - START_LANE_BELOW) * sim.room.gravity
	var bottom := sim.state.y + START_LANE_BELOW * sim.room.gravity
	var ly0 := mini(top, bottom)
	var ly1 := maxi(top, bottom)
	var lx0 := sim.state.x if sim.state.vx > 0 else sim.state.x - w
	var lx1 := sim.state.x + w if sim.state.vx > 0 else sim.state.x
	return x1 > lx0 and x0 < lx1 and y1 > ly0 and y0 < ly1
