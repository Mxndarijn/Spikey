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

var mode := Mode.ECHO
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
		y = SimConfig.WORLD_H - sim.state.y
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


func kills(sim: GameSim) -> bool:
	return shown and sim.bird_touches_circle(x, y, RADIUS)


func checksum(h: int) -> int:
	var out := mix_all(h, [mode, x, y, int(shown), facing, head])
	for i in xs.size():
		out = SimHash.mix(SimHash.mix(out, xs[i]), ys[i])
	return out
