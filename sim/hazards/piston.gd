extends Hazard
## A piston in a side wall (Piston Press). It waits, shows its lane as a
## warning, slams across part of the room, holds, then pulls back. Deadly only
## while out. Its row, wall, reach, warning and rhythm are set when the room is
## built (the generated layout, catalog_machines._gen_press) and never change.
##
## A ram that would reach into an open or ghost exit's mouth (ExitZone) sits
## that cycle out; an exit is never planned where a ram reaches (blocks_exit).

enum State { IDLE, GLOW, EXTEND, HOLD, RETRACT }

const IDLE_TICKS := 70
## Today's shortest warning (0.53 s): no ram warns for less.
const GLOW_TICKS := 32
const EXTEND_TICKS := 8
const HOLD_TICKS := 34
const RETRACT_TICKS := 30

## How far the ram reaches into the room when fully out (nose included).
const REACH := 200 * SimConfig.SUB
## Half the height of the ram's body.
const HALF_H := 18 * SimConfig.SUB
## Where a ram can sit (centre heights), clear of the ceiling and floor.
const Y_MIN := 110 * SimConfig.SUB
const Y_MAX := 530 * SimConfig.SUB

## 0 = left wall, 1 = right wall.
var side := 0
## Centre height of the ram, sub-units.
var y := 0
## Steps before the first cycle starts (its place in the room's rhythm).
var delay := 0
## Steps of warning before each slam.
var glow_ticks := GLOW_TICKS
## How far the ram reaches into the room when fully out.
var reach := REACH
## Sits out the rest of this cycle: fully out, the ram would reach into an
## open or ghost exit's mouth (ExitZone).
var skip := false


func _init(
	p_side: int = 0,
	p_y: int = Y_MIN,
	p_delay: int = 0,
	p_glow: int = GLOW_TICKS,
	p_reach: int = REACH
) -> void:
	kind = "piston"
	side = p_side
	y = p_y
	delay = p_delay
	glow_ticks = p_glow
	reach = p_reach


func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	_clear_spikes(sim)


## No wall spike shares the ram's row on its own wall (it would poke out above
## or below the ram): the slots whose spike would touch the ram's body are
## cleared after each bounce's new wall. No RNG draws.
func _clear_spikes(sim: GameSim) -> void:
	var near := HALF_H + SimConfig.SPIKE_HALF_BASE
	var mask := sim.state.left_spikes if side == 0 else sim.state.right_spikes
	for slot in SimConfig.SLOT_COUNT:
		if absi(SimConfig.slot_center_y(slot) - y) < near:
			mask &= ~(1 << slot)
	if side == 0:
		sim.state.left_spikes = mask
	else:
		sim.state.right_spikes = mask


## Steps in one cycle (idle, warning, slam, hold, pull back).
func period() -> int:
	return IDLE_TICKS + glow_ticks + EXTEND_TICKS + HOLD_TICKS + RETRACT_TICKS


## Steps into the current cycle, or -1 before the first one.
func cycle_pos() -> int:
	if t < delay:
		return -1
	return posmod(t - delay, period())


## Each step: a ram that would reach into an exit's mouth (ExitZone) stays in
## the wall, warning and all, until its next cycle.
func step(sim: GameSim) -> void:
	if _cycle_state() == State.IDLE:
		skip = false
	elif not skip and _reaches_exit(sim):
		skip = true


## True if the ram, fully out at its height, would touch an exit's mouth.
func _reaches_exit(sim: GameSim) -> bool:
	return ExitZone.hits_rect(sim, base_x(), y - HALF_H, _far_x(), y + HALF_H)


## The tip of the ram when fully out.
func _far_x() -> int:
	return base_x() + reach if side == 0 else base_x() - reach


## The ram never moves off its row, so an exit is never planned where it
## reaches (the exit goes elsewhere).
func blocks_exit(sim: GameSim, p_side: int, p_y: int) -> bool:
	return ExitZone.rect_in_box(sim, p_side, p_y, base_x(), y - HALF_H, _far_x(), y + HALF_H)


func state() -> State:
	if skip:
		return State.IDLE
	return _cycle_state()


## Where the cycle is, whether or not this one is sat out.
func _cycle_state() -> State:
	var p := cycle_pos()
	if p < IDLE_TICKS:
		return State.IDLE
	p -= IDLE_TICKS
	if p < glow_ticks:
		return State.GLOW
	p -= glow_ticks
	if p < EXTEND_TICKS:
		return State.EXTEND
	p -= EXTEND_TICKS
	if p < HOLD_TICKS:
		return State.HOLD
	return State.RETRACT


## 0..1024 how far into the warning (0 outside it).
func glow() -> int:
	if state() != State.GLOW:
		return 0
	return SimTrig.ONE * (cycle_pos() - IDLE_TICKS) / glow_ticks


## How far the ram is out of the wall right now, sub-units.
func extent() -> int:
	var p := cycle_pos() - IDLE_TICKS - glow_ticks
	match state():
		State.EXTEND:
			return reach * (p + 1) / EXTEND_TICKS
		State.HOLD:
			return reach
		State.RETRACT:
			p -= EXTEND_TICKS + HOLD_TICKS
			return reach * (RETRACT_TICKS - p - 1) / RETRACT_TICKS
	return 0


## The wall the piston sits in.
func base_x() -> int:
	return 0 if side == 0 else SimConfig.WORLD_W


## The tip of the ram (equals base_x() while retracted).
func tip_x() -> int:
	return base_x() + extent() if side == 0 else base_x() - extent()


func kills(sim: GameSim) -> bool:
	var e := extent()
	if e <= 0:
		return false
	return sim.bird_touches_rect(base_x(), y - HALF_H, tip_x(), y + HALF_H)


func checksum(h: int) -> int:
	return mix_all(h, [side, y, delay, glow_ticks, reach, int(skip)])


## While it warns: the whole reach of the slam, until it is back in the wall.
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if state() != State.GLOW:
		return
	add_warning(
		out,
		base_x(),
		y - HALF_H,
		_far_x(),
		y + HALF_H,
		IDLE_TICKS + glow_ticks - cycle_pos(),
		EXTEND_TICKS + HOLD_TICKS + RETRACT_TICKS,
		WARN_KILL
	)
