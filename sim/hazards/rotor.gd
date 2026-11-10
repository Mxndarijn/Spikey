extends Hazard
## Pinwheel blades turning round a hub (Pinwheel, Double Trouble). The hub and
## every blade kill. Blades are tested as a row of circles.
##
## The room sets the shape when it builds one (sim/rooms/catalog_motion.gd):
## Pinwheel's variants are a smaller wheel, three blades, a twin pair, one that
## rocks back and forth, one off to one side and one whose blades grow and
## shrink. `Rotor.new()` alone is the original big wheel (Double Trouble).

enum Spin { STEADY, ROCK, BREATHE }

const CENTER_X := 180 * SimConfig.SUB
const CENTER_Y := 320 * SimConfig.SUB
## Test circles per blade, spread from the hub to the tip.
const SAMPLES := 5
## Holding height, the bird hops about this far up: more room on that side.
const HOP := 64 * SimConfig.SUB
## Out of a portal the wheel sits at least its reach plus this far off the
## bird (the bird and a margin).
const CLEAR_MARGIN := SimConfig.BIRD_RADIUS + 4 * SimConfig.SUB
## Rock: speed up over ROCK_EASE steps, turn ROCK_RUN steps at full speed, slow
## down over ROCK_EASE, stand still ROCK_PAUSE steps, then the same the other
## way. A reversal shows for over a second before it is back at full speed.
const ROCK_EASE := 24
const ROCK_RUN := 150
const ROCK_PAUSE := 18
const ROCK_HALF := 2 * ROCK_EASE + ROCK_RUN + ROCK_PAUSE
## Breathe: hold short, grow, hold long, shrink (steps each, like Saw Ring).
const BREATHE_HOLD := 60
const BREATHE_MOVE := 60
const BREATHE_CYCLE := 2 * (BREATHE_HOLD + BREATHE_MOVE)

# Shape (set before setup, never changes in a room).
var blades := 4
## Longest blade (the only length unless it breathes).
var blade_max := 80 * SimConfig.SUB
## Shortest blade while breathing.
var blade_min := 80 * SimConfig.SUB
## Half the blade's width, also the radius of each test circle.
var half_w := 8 * SimConfig.SUB
var hub_radius := 16 * SimConfig.SUB
## Steps per full turn at full speed.
var period := 360
var spin := Spin.STEADY
## 1 hub, or 2 (twin): the two sit at the centre minus and plus the spread,
## and the second turns the other way.
var hubs := 1
var spread_x := 0
var spread_y := 0
## Off-centre: the centre sits this far from the middle, toward a wall the
## seed picks (out of a portal: the wall the bird flies to).
var lean := 0

# State.
var center_x := CENTER_X
## Centre height: CENTER_Y, or moved off the bird's height out of a portal.
var center_y := CENTER_Y
var phase := 0
## +1 or -1: which way it turns.
var dir := 1
## Current turn (SimTrig angle of the first hub's blade 0).
var angle := 0
## Current blade length.
var blade_length := 80 * SimConfig.SUB


## Blade length, half width and hub radius in sub-units. The defaults are the
## original big wheel.
func _init(
	p_length: int = 80 * SimConfig.SUB,
	p_half_w: int = 8 * SimConfig.SUB,
	p_hub: int = 16 * SimConfig.SUB
) -> void:
	kind = "rotor"
	blade_max = p_length
	blade_min = p_length
	blade_length = p_length
	half_w = p_half_w
	hub_radius = p_hub


## How far from a hub a blade can reach (tip included).
func reach() -> int:
	return blade_max + half_w


## A bird closer than this to a hub (or this plus HOP below it) could be hit
## while it holds its height out of a portal.
func hub_clear() -> int:
	return reach() + CLEAR_MARGIN


func setup(sim: GameSim, rng: SimRng) -> void:
	center_x = CENTER_X
	center_y = CENTER_Y
	var y := sim.state.y
	var top := -spread_y if hubs == 2 else 0
	var bottom := spread_y if hubs == 2 else 0
	var clear := hub_clear()
	var dy := y - CENTER_Y
	if sim.state.started and dy > top - clear and dy < bottom + clear + HOP:
		# The nearer side first (below a bird above the middle), the other side
		# when a blade would leave the cage there.
		var below := y + clear - top
		var above := y - clear - HOP - bottom
		var first := below if dy < 0 else above
		var second := above if dy < 0 else below
		center_y = first if _fits(first) else second
		if not _fits(center_y):
			center_y = first
	phase = rng.next_below(SimTrig.TURN)
	dir = 1 if rng.next_below(2) == 0 else -1
	if lean != 0:
		var right := rng.next_below(2) == 0
		if sim.state.started:
			right = sim.state.vx > 0
		center_x = CENTER_X + (lean if right else -lean)
	_place()


## True when every blade at centre height `cy` stays between the ceiling and
## floor lines.
func _fits(cy: int) -> bool:
	var top := cy - (spread_y if hubs == 2 else 0) - reach()
	var bottom := cy + (spread_y if hubs == 2 else 0) + reach()
	return top >= SimConfig.KILL_TOP and bottom <= SimConfig.KILL_BOTTOM


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	angle = posmod(phase + dir * _turned(t), SimTrig.TURN)
	blade_length = _length_at(t)


## How far it has turned after `steps` (SimTrig angle, before the direction).
func _turned(steps: int) -> int:
	if spin != Spin.ROCK:
		return steps * SimTrig.TURN / period
	# Distance in 1/(2 * ROCK_EASE) steps at full speed, so easing stays integer.
	var e := ROCK_EASE
	var full := 2 * e * e + 2 * e * ROCK_RUN
	var m := steps % ROCK_HALF
	var x := full
	if m < e:
		x = m * m
	elif m < e + ROCK_RUN:
		x = e * e + 2 * e * (m - e)
	elif m < 2 * e + ROCK_RUN:
		var u := m - e - ROCK_RUN
		x = e * e + 2 * e * ROCK_RUN + 2 * e * u - u * u
	if (steps / ROCK_HALF) % 2 == 1:
		x = full - x
	return x * SimTrig.TURN / (2 * e * period)


func _length_at(steps: int) -> int:
	if spin != Spin.BREATHE:
		return blade_max
	var m := steps % BREATHE_CYCLE
	var grow := blade_max - blade_min
	if m < BREATHE_HOLD:
		return blade_min
	m -= BREATHE_HOLD
	if m < BREATHE_MOVE:
		return blade_min + grow * m / BREATHE_MOVE
	m -= BREATHE_MOVE
	if m < BREATHE_HOLD:
		return blade_max
	m -= BREATHE_HOLD
	return blade_max - grow * m / BREATHE_MOVE


func hub_x(h: int) -> int:
	return center_x + (2 * h - (hubs - 1)) * spread_x


func hub_y(h: int) -> int:
	return center_y + (2 * h - (hubs - 1)) * spread_y


## SimTrig angle of blade `i` on hub `h` (the second hub turns the other way).
func blade_angle(h: int, i: int) -> int:
	var a := angle if h % 2 == 0 else SimTrig.TURN - angle
	return a + i * SimTrig.TURN / blades


## Highest row a blade can reach, over every hub.
func band_top() -> int:
	var out := hub_y(0) - reach()
	for h in hubs:
		out = mini(out, hub_y(h) - reach())
	return out


## Lowest row a blade can reach, over every hub.
func band_bottom() -> int:
	var out := hub_y(0) + reach()
	for h in hubs:
		out = maxi(out, hub_y(h) + reach())
	return out


func kills(sim: GameSim) -> bool:
	for h in hubs:
		var cx := hub_x(h)
		var cy := hub_y(h)
		if sim.bird_touches_circle(cx, cy, hub_radius):
			return true
		for i in blades:
			var a := blade_angle(h, i)
			var c := SimTrig.cos_t(a)
			var s := SimTrig.sin_t(a)
			for k in SAMPLES:
				var d := blade_length * (k + 1) / SAMPLES
				var px := cx + d * c / SimTrig.ONE
				var py := cy + d * s / SimTrig.ONE
				if sim.bird_touches_circle(px, py, half_w):
					return true
	return false


func checksum(h: int) -> int:
	return mix_all(h, [phase, dir, angle, center_x, center_y, blade_length])
