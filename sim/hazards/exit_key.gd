extends Hazard
## Locked Exit: the room's exit opens locked. Until the bird touches a key,
## flying into the exit is a bounce (Hazard.locks_exit), and with the exit
## open a bounce scores nothing, so the room waits for the key. The key pays
## COINS. After MAX_LOCKED_BOUNCES bounces with the exit locked it opens
## anyway, so the room is never a trap.

## Variants (the room's variant id picks one): a key that hangs still; one
## that circles the room; two keys (either opens the exit).
enum Mode { STILL, ORBIT, TWO }

const SUB := SimConfig.SUB
const RADIUS := 12 * SUB
const COINS := 3
## Two visits to the locked exit (and two bounces on the far wall).
const MAX_LOCKED_BOUNCES := 4
## Orbit: an oval round the middle, one lap in ORBIT_STEPS.
const ORBIT_CX := 180 * SUB
const ORBIT_CY := 330 * SUB
const ORBIT_RX := 105 * SUB
const ORBIT_RY := 150 * SUB
const ORBIT_STEPS := 540

var mode := Mode.STILL
## Key positions; the second one only in Mode.TWO.
var x0 := 0
var y0 := 0
var x1 := 0
var y1 := 0
var phase := 0
var taken := false
var locked_bounces := 0
## The open exit, copied each step for the painter (it draws the padlock).
var door_open := false
var door_side := 0
var door_a_y := 0
var door_b_y := 0


## `p_mode` -1: take it from the room's variant.
func _init(p_mode: int = -1) -> void:
	kind = "exit_key"
	mode = p_mode


## Draws: the key's place (two draws per key), or the orbit's phase.
func setup(sim: GameSim, rng: SimRng) -> void:
	if mode < 0:
		match sim.room.variant_id():
			"orbit":
				mode = Mode.ORBIT
			"two":
				mode = Mode.TWO
			_:
				mode = Mode.STILL
	match mode:
		Mode.ORBIT:
			phase = rng.next_below(SimTrig.TURN)
			_place_orbit()
		Mode.TWO:
			x0 = (110 + rng.next_below(61)) * SUB
			y0 = (140 + rng.next_below(141)) * SUB
			x1 = (190 + rng.next_below(61)) * SUB
			y1 = (380 + rng.next_below(121)) * SUB
		_:
			x0 = (130 + rng.next_below(101)) * SUB
			y0 = (150 + rng.next_below(341)) * SUB


func step(sim: GameSim) -> void:
	if mode == Mode.ORBIT and not taken:
		_place_orbit()
	var s := sim.state
	door_open = s.exit_open
	door_side = s.exit_side
	door_a_y = s.exit_a_y
	door_b_y = s.exit_b_y if s.exit_b_kind != SimState.ExitKind.NORMAL else 0


func _place_orbit() -> void:
	var a := phase + t * SimTrig.TURN / ORBIT_STEPS
	x0 = ORBIT_CX + ORBIT_RX * SimTrig.cos_t(a) / SimTrig.ONE
	y0 = ORBIT_CY + ORBIT_RY * SimTrig.sin_t(a) / SimTrig.ONE


func touch(sim: GameSim) -> void:
	if taken:
		return
	var hit := sim.bird_touches_circle(x0, y0, RADIUS)
	var at_x := x0
	var at_y := y0
	if not hit and mode == Mode.TWO and sim.bird_touches_circle(x1, y1, RADIUS):
		hit = true
		at_x = x1
		at_y = y1
	if not hit:
		return
	taken = true
	for i in COINS:
		sim.collect_coin(at_x, at_y)


func locks_exit(_sim: GameSim) -> bool:
	return not taken and locked_bounces < MAX_LOCKED_BOUNCES


## Whether the open exit is locked right now (for the view).
func locked() -> bool:
	return not taken and locked_bounces < MAX_LOCKED_BOUNCES


func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	if sim.state.exit_open and not taken:
		locked_bounces += 1


func checksum(h: int) -> int:
	return mix_all(
		h,
		[
			mode,
			x0,
			y0,
			x1,
			y1,
			phase,
			int(taken),
			locked_bounces,
			int(door_open),
			door_side,
			door_a_y,
			door_b_y
		]
	)
