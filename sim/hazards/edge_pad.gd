extends Hazard
## A bumper pad sliding along the ceiling or floor (Bumper Court). Where the pad
## is, the edge is safe and bounces the bird back; the rest still kills.

const WIDTH := 96 * SimConfig.SUB
## Pads slide between these x values (left end of the pad).
const X_MIN := 30 * SimConfig.SUB
const X_MAX := SimConfig.WORLD_W - 30 * SimConfig.SUB - WIDTH
## The bird counts as on the pad if its centre is this close past an end.
const GRACE := SimConfig.BIRD_RADIUS / 2
## Speed the bird leaves the ceiling pad with (down) and the floor pad (up).
## Bounce speeds, tied to the flap: the floor pad throws a little harder than a
## flap, the ceiling pad pushes down gently.
const CEILING_VY := -SimConfig.FLAP_VY * 3 / 5
const FLOOR_VY := -SimConfig.FLAP_VY * 6 / 5

## True: on the ceiling, false: on the floor.
var top := true
## Ticks for one slide there and back.
var period := 300
## Phase offset into the slide, drawn at setup.
var phase := 0
## Steps since the pad last bounced the bird (for the painter's squash).
var since_bump := 1000


func _init(p_top: bool = true, p_period: int = 300) -> void:
	kind = "edge_pad"
	top = p_top
	period = p_period


func setup(_sim: GameSim, rng: SimRng) -> void:
	phase = rng.next_below(period)


func step(_sim: GameSim) -> void:
	since_bump += 1


## Left end of the pad, sub-units.
func x0() -> int:
	return X_MIN + SimTrig.ping_pong(t + phase, period, X_MAX - X_MIN)


func x1() -> int:
	return x0() + WIDTH


## The edge line the pad lies on.
func line_y() -> int:
	return SimConfig.KILL_TOP if top else SimConfig.KILL_BOTTOM


func covers(x: int) -> bool:
	return x >= x0() - GRACE and x <= x1() + GRACE


func guards_edge(sim: GameSim, p_top: bool) -> bool:
	if p_top != top or not covers(sim.state.x):
		return false
	var r := SimConfig.BIRD_RADIUS
	if top:
		sim.state.y = maxi(sim.state.y, SimConfig.KILL_TOP + r + 1)
		sim.state.vy = CEILING_VY
	else:
		sim.state.y = mini(sim.state.y, SimConfig.KILL_BOTTOM - r - 1)
		sim.state.vy = -FLOOR_VY
	since_bump = 0
	return true


func checksum(h: int) -> int:
	return mix_all(h, [int(top), period, phase, since_bump])
