extends Hazard
## A piston in a side wall (Piston Press). It waits, glows as a warning, slams
## across part of the room, holds, then pulls back. Deadly only while out.
## After each wall bounce an idle piston may move to a new height.
##
## In Double Trouble it glows for 1 s (glow_ticks) and keeps its height inside
## the other hazard's band (share_band), so the lanes that hazard leaves free
## stay free.
##
## Variants (Piston Press): a shorter ram (reach), the whole room to pick from
## (HALF_ALL), a ram that copies the height of the piston before it so both
## slam as one (follows), or a fixed height that never moves (fixed_y).
##
## A piston whose ram would reach into an open or ghost exit's mouth
## (ExitZone) sits that cycle out.

enum State { IDLE, GLOW, EXTEND, HOLD, RETRACT }

const IDLE_TICKS := 70
const GLOW_TICKS := 32
const EXTEND_TICKS := 8
const HOLD_TICKS := 34
const RETRACT_TICKS := 30
const PERIOD := IDLE_TICKS + GLOW_TICKS + EXTEND_TICKS + HOLD_TICKS + RETRACT_TICKS

## How far the ram reaches into the room when fully out (nose included).
const REACH := 200 * SimConfig.SUB
## Half the height of the ram's body.
const HALF_H := 18 * SimConfig.SUB
## Where the piston can sit (centre heights), clear of the ceiling and floor.
const Y_MIN := 110 * SimConfig.SUB
const Y_MAX := 530 * SimConfig.SUB
## Pistons in one room stay in their own half (upper / lower).
const Y_MID := 320 * SimConfig.SUB
## `half` for a piston that picks from the whole room.
const HALF_ALL := 2

## 0 = left wall, 1 = right wall.
var side := 0
## Centre height of the ram, sub-units.
var y := 0
## Steps before the first cycle starts (staggers pistons in one room).
var delay := 0
## 0 = upper half of the room, 1 = lower half, HALF_ALL = anywhere.
var half := 0
## Steps of warning glow before each slam.
var glow_ticks := GLOW_TICKS
## Keep the ram inside another hazard's band (Hazard.band_top()).
var share_band := false
## The centre heights it picks from (set in setup()).
var y_lo := Y_MIN
var y_hi := Y_MAX
## How far the ram reaches into the room when fully out.
var reach := REACH
## Copies the height of the piston before it in the room (found at setup).
var follows := false
var leader: Hazard = null
## A fixed centre height (sub-units), or -1 to pick one after each bounce.
var fixed_y := -1
## Sits out the rest of this cycle: fully out, the ram would reach into an
## open or ghost exit's mouth (ExitZone).
var skip := false


func _init(
	p_side: int = 0,
	p_half: int = 0,
	p_delay: int = 0,
	p_glow: int = GLOW_TICKS,
	p_share_band: bool = false
) -> void:
	kind = "piston"
	side = p_side
	half = p_half
	delay = p_delay
	glow_ticks = p_glow
	share_band = p_share_band


func setup(sim: GameSim, rng: SimRng) -> void:
	if fixed_y >= 0:
		y = fixed_y
		return
	if follows:
		leader = null
		for h: Hazard in sim.room.hazards:
			if h == self:
				break
			if h.kind == kind:
				leader = h
		if leader != null:
			y = leader.y
			return
	y_lo = Y_MIN if half != 1 else Y_MID + HALF_H
	y_hi = Y_MID - HALF_H if half == 0 else Y_MAX
	if share_band:
		for h: Hazard in sim.room.hazards:
			if h == self or h.band_top() < 0:
				continue
			var lo := maxi(Y_MIN, h.band_top() + HALF_H)
			var hi := mini(Y_MAX, h.band_bottom() - HALF_H)
			if lo <= hi:
				y_lo = lo
				y_hi = hi
	_pick_y(rng)


func on_bounce(_sim: GameSim, rng: SimRng) -> void:
	if fixed_y >= 0:
		return
	if leader != null:
		# The leader has already moved (or kept still): stay level with it.
		y = leader.y
		return
	# Always draw so the RNG order does not depend on the piston's state.
	var old := y
	_pick_y(rng)
	if _cycle_state() != State.IDLE:
		y = old


func _pick_y(rng: SimRng) -> void:
	y = y_lo + rng.next_below(y_hi - y_lo + 1)


## Steps in one cycle (idle, glow, slam, hold, pull back).
func period() -> int:
	return IDLE_TICKS + glow_ticks + EXTEND_TICKS + HOLD_TICKS + RETRACT_TICKS


## Steps into the current cycle, or -1 before the first one.
func cycle_pos() -> int:
	if t < delay:
		return -1
	return posmod(t - delay, period())


## Each step: a ram that would reach into an exit's mouth (ExitZone) stays in
## the wall, glow and all, until its next cycle.
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


## A ram already in its cycle would have to vanish at an exit planned in its
## way, so the exit goes elsewhere.
func blocks_exit(sim: GameSim, p_side: int, p_y: int) -> bool:
	if skip or _cycle_state() == State.IDLE:
		return false
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


## 0..1024 how far into the warning glow (0 outside it).
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
	return mix_all(h, [side, y, delay, half, int(skip)])
