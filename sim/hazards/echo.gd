extends Hazard
## A shadow bird (Echo). The echo flies the bird's own path DELAY steps late;
## the mirror flies opposite the bird through the middle of the room. Either
## kills on touch. Hidden for the room's first DELAY steps, so a bird out of a
## portal always gets its full reading time. The shadow never enters an
## open or ghost exit's mouth (ExitZone): it flies along its edge.

## Variants (the room's variant id picks one).
enum Mode { ECHO, MIRROR }

## One second behind.
const DELAY := SimConfig.TICKS_PER_SECOND
## Smaller than the bird: a shadow 20 px across.
const RADIUS := 10 * SimConfig.SUB
## Generated mirror (Echo room): where the height it turns round can be, and
## how far that height stays from a bird holding its height out of a portal
## (the shadow is 2 x that far from the bird: half the two radii, plus room).
const PIVOT_LO := 200 * SimConfig.SUB
const PIVOT_HI := 440 * SimConfig.SUB
const PIVOT_CLEAR := (SimConfig.BIRD_RADIUS + RADIUS) / 2 + 6 * SimConfig.SUB

var mode := Mode.ECHO
## Mirror: the height it turns the bird's round (the room's middle, or drawn
## by the generated mirror: place_pivot).
var pivot_y := SimConfig.WORLD_H / 2
## Where the shadow is now, and whether it is out yet.
var x := 0
var y := 0
var shown := false
## Which way the shadow faces (1 = right), for the painter.
var facing := 1
## The bird's last DELAY positions, oldest at `head`.
var xs := PackedInt32Array()
var ys := PackedInt32Array()
var head := 0


## `p_mode` -1: take it from the room's variant ("echo" or "mirror").
func _init(p_mode: int = -1) -> void:
	kind = "echo"
	mode = p_mode


func setup(sim: GameSim, _rng: SimRng) -> void:
	if mode < 0:
		mode = Mode.MIRROR if sim.room.variant_id() == "mirror" else Mode.ECHO
	xs.resize(DELAY)
	ys.resize(DELAY)
	xs.fill(sim.state.x)
	ys.fill(sim.state.y)
	head = 0
	x = sim.state.x
	y = sim.state.y


func step(sim: GameSim) -> void:
	shown = t > DELAY
	if mode == Mode.MIRROR:
		x = SimConfig.WORLD_W - sim.state.x
		y = 2 * pivot_y - sim.state.y
		facing = -1 if sim.state.vx > 0 else 1
		x = ExitZone.push_x(sim, x, y, RADIUS)
		return
	var old_x := xs[head]
	facing = 1 if old_x >= x else -1
	x = old_x
	y = ys[head]
	xs[head] = sim.state.x
	ys[head] = sim.state.y
	head = (head + 1) % DELAY
	x = ExitZone.push_x(sim, x, y, RADIUS)


## Generated mirror, out of a portal: draws the height it turns round from
## PIVOT_LO..PIVOT_HI, leaving out the heights within PIVOT_CLEAR of the band a
## bird holding its height anywhere in the exit sweeps (it meets its shadow
## only on that line), so a player still reading the room never meets it.
## One draw; none at the start of a run (the room's middle).
func place_pivot(p: VariantParams) -> void:
	if not p.arriving:
		return
	var sub := SimConfig.SUB
	var g := p.sim.room.gravity
	var hop_top := p.bird_top() - (FairLanes.FIRST_HOP if g > 0 else 0)
	var hop_bottom := p.bird_bottom() + (0 if g > 0 else FairLanes.FIRST_HOP)
	# In whole pixels: [lo, a) and (b, hi] are allowed.
	var lo := PIVOT_LO / sub
	var hi := PIVOT_HI / sub
	var a := mini((hop_top - PIVOT_CLEAR) / sub, hi + 1)
	var b := maxi((hop_bottom + PIVOT_CLEAR) / sub, lo - 1)
	var n1 := maxi(a - lo, 0)
	var n2 := maxi(hi - b, 0)
	if n1 + n2 == 0:
		pivot_y = PIVOT_LO if absi(PIVOT_LO - p.entry_y) > absi(PIVOT_HI - p.entry_y) else PIVOT_HI
		return
	var r := p.rng.next_below(n1 + n2)
	pivot_y = (lo + r if r < n1 else b + 1 + r - n1) * sub


func kills(sim: GameSim) -> bool:
	return shown and sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	var out := mix_all(h, [mode, x, y, int(shown), facing, head])
	if pivot_y != SimConfig.WORLD_H / 2:
		out = mix_all(out, [pivot_y])
	for i in xs.size():
		out = SimHash.mix(SimHash.mix(out, xs[i]), ys[i])
	return out
