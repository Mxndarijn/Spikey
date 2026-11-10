extends Hazard
## A band of wind across the room (Crosswind). While the bird's centre is in
## a band that is blowing, every step pushes it PUSH along the wind: flying
## with it, it reaches the wall sooner; against it, later. Never pushes up or
## down, never deadly.

## Variants (the room's variant id picks one): one band; two bands blowing
## opposite ways; one band that blows and rests on a cycle.
enum Mode { STEADY, SPLIT, GUSTY }

const SUB := SimConfig.SUB
## A quarter of the bird's own speed: 5 px a step with the wind, 3 against.
const PUSH := SimConfig.SPEED_X / 4
## Gusty: a cycle of calm, then warning (the view shows it coming), then wind.
## It starts calm, so a bird out of a portal reads the room in still air.
const GUST_PERIOD := 320
const GUST_CALM := 110
const GUST_WARN := 60

var mode := Mode.STEADY
## Band a, and band b (b_dir 0 = no second band). dir 1 blows right.
var a_y0 := 250 * SUB
var a_y1 := 370 * SUB
var a_dir := 1
var b_y0 := 0
var b_y1 := 0
var b_dir := 0


## `p_mode` -1: take it from the room's variant.
func _init(p_mode: int = -1) -> void:
	kind = "wind"
	mode = p_mode


## One draw: which way band a blows.
func setup(sim: GameSim, rng: SimRng) -> void:
	if mode < 0:
		match sim.room.variant_id():
			"split":
				mode = Mode.SPLIT
			"gusty":
				mode = Mode.GUSTY
			_:
				mode = Mode.STEADY
	a_dir = 1 if rng.next_below(2) == 0 else -1
	if mode == Mode.SPLIT:
		a_y0 = 180 * SUB
		a_y1 = 280 * SUB
		b_y0 = 400 * SUB
		b_y1 = 500 * SUB
		b_dir = -a_dir


## Whether the wind blows this step.
func blowing() -> bool:
	if mode != Mode.GUSTY:
		return true
	return posmod(t, GUST_PERIOD) >= GUST_CALM + GUST_WARN


## Gusty: the wind is about to start (for the view).
func warning() -> bool:
	if mode != Mode.GUSTY:
		return false
	var p := posmod(t, GUST_PERIOD)
	return p >= GUST_CALM and p < GUST_CALM + GUST_WARN


func touch(sim: GameSim) -> void:
	if not blowing():
		return
	var y := sim.state.y
	if y >= a_y0 and y <= a_y1:
		sim.state.x += a_dir * PUSH
	elif b_dir != 0 and y >= b_y0 and y <= b_y1:
		sim.state.x += b_dir * PUSH


func checksum(h: int) -> int:
	return mix_all(h, [mode, a_y0, a_y1, a_dir, b_y0, b_y1, b_dir])
