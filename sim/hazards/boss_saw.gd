extends "res://sim/hazards/boss.gd"
## Saw King (boss): a huge saw in the middle column. Phase 1, the hop: it jumps
## between HEIGHTS, always to or from the middle one, after a TELL-step warning
## ring where it lands, so the height it neither leaves nor lands on stays
## clear. Phase 2, the ring: it drifts to RING_YS[0] or [1] and swings its
## blades out to RING_MAX, then back in; the far band (top when it sinks,
## bottom when it rises) stays clear. Phase 3: the hops with a smaller blade
## ring. Tier 2 hops faster in phase 3; tier 3 has more blades and a wider ring.
## Out of a portal it starts at the height furthest from the bird's.

const KING_X := 180 * SimConfig.SUB
## Kill radius of the saw (teeth included).
const KING_R := 46 * SimConfig.SUB
const BLADE_R := 12 * SimConfig.SUB
const HEIGHTS: Array[int] = [180 * SimConfig.SUB, 320 * SimConfig.SUB, 460 * SimConfig.SUB]
const RING_YS: Array[int] = [260 * SimConfig.SUB, 380 * SimConfig.SUB]
const CYCLE := 240
## Phase 3's cycle from tier 2.
const CYCLE_FAST := 180
## Phase 2's cycle (the ring).
const RING_CYCLE := 300
const TELL := SimConfig.WARN_TICKS
const JUMP := 30
## Phase 2: blades swing out after the drift, hold, swing back in.
const RING_OUT := TELL + JUMP
const RING_HOLD := 120
const RING_IN := RING_OUT + 90
const RING_MAX := 115 * SimConfig.SUB
const RING_MAX_TIER3 := 130 * SimConfig.SUB
const RING_HOP := 72 * SimConfig.SUB
## Blades show (and kill) once the ring is this wide.
const RING_SHOW := 50 * SimConfig.SUB
const RING_SPEED := 4 * SimConfig.SUB
## While it waits between phases it slides to the nearest height this fast.
const SLIDE := 3 * SimConfig.SUB
## Turn per step (SimTrig angle units).
const SPIN := 6

var king_y := 0
## This cycle's jump: from where to where (heights, sub-units).
var from_y := 0
var to_y := 0
## Ring radius now, and the blades (filled every step for the painter).
var ring := 0
var angle := 0
var blades := 6
var blade_x: Array[int] = []
var blade_y: Array[int] = []
## True while the warning ring shows where it lands (or the ring's reach).
var telling := false
var _k := -1


func _init() -> void:
	kind = "boss_saw"


func boss_setup(sim: GameSim) -> void:
	blades = 8 if tier >= 3 else 6
	blade_x.resize(blades)
	blade_y.resize(blades)
	var far := 0
	if absi(HEIGHTS[2] - sim.state.anchor_y) > absi(HEIGHTS[0] - sim.state.anchor_y):
		far = 2
	elif absi(HEIGHTS[2] - sim.state.anchor_y) == absi(HEIGHTS[0] - sim.state.anchor_y):
		far = 2 * (seed % 2)
	king_y = HEIGHTS[far]
	from_y = king_y
	to_y = king_y
	_place_blades()


func cycle() -> int:
	if phase == 2:
		return RING_CYCLE
	return CYCLE_FAST if phase == 3 and tier >= 2 else CYCLE


func ring_max() -> int:
	return RING_MAX_TIER3 if tier >= 3 else RING_MAX


static func nearest(y: int) -> int:
	var best := 0
	for i in HEIGHTS.size():
		if absi(HEIGHTS[i] - y) < absi(HEIGHTS[best] - y):
			best = i
	return best


## Phase 1 and 3: where cycle `k`'s jump from height `from` lands.
func hop_to(from: int, k: int) -> int:
	if nearest(from) != 1:
		return HEIGHTS[1]
	return HEIGHTS[0 if draw(k, phase) % 2 == 0 else 2]


func on_phase() -> void:
	_k = -1


func boss_step(_sim: GameSim) -> void:
	angle = posmod(angle + SPIN, SimTrig.TURN)
	telling = false
	var c := clock()
	var ring_to := ring
	if c < 0:
		ring_to = RING_HOP if phase == 3 else 0
		if phase != 2:
			king_y = _toward(king_y, HEIGHTS[nearest(king_y)], SLIDE)
	elif phase == 2:
		var k := c / RING_CYCLE
		var lt := c % RING_CYCLE
		if _k != k:
			_k = k
			from_y = king_y
			to_y = RING_YS[draw(k, 2) % 2]
		telling = lt < RING_OUT
		king_y = _jump(lt)
		ring_to = ring_max() if lt >= RING_OUT and lt < RING_IN else 0
	else:
		var k := c / cycle()
		var lt := c % cycle()
		if _k != k:
			_k = k
			from_y = king_y
			to_y = hop_to(from_y, k)
		telling = lt < TELL
		king_y = _jump(lt)
		ring_to = RING_HOP if phase == 3 else 0
	ring = _toward(ring, ring_to, RING_SPEED)
	_place_blades()


## The king's height `lt` steps into a cycle: still, then the jump.
func _jump(lt: int) -> int:
	if lt < TELL:
		return from_y
	if lt < TELL + JUMP:
		return from_y + (to_y - from_y) * (lt - TELL) / JUMP
	return to_y


static func _toward(from: int, to: int, speed: int) -> int:
	if to > from:
		return mini(from + speed, to)
	return maxi(from - speed, to)


func _place_blades() -> void:
	for i in blades:
		var a := angle + i * SimTrig.TURN / blades
		blade_x[i] = KING_X + ring * SimTrig.cos_t(a) / SimTrig.ONE
		blade_y[i] = king_y + ring * SimTrig.sin_t(a) / SimTrig.ONE


func boss_down_step(_sim: GameSim) -> void:
	telling = false
	ring = _toward(ring, 0, RING_SPEED)
	_place_blades()


func boss_kills(sim: GameSim) -> bool:
	if sim.bird_touches_circle(KING_X, king_y, KING_R):
		return true
	if ring >= RING_SHOW:
		for i in blades:
			if sim.bird_touches_circle(blade_x[i], blade_y[i], BLADE_R):
				return true
	return false


## Only the wide ring of phase 2 reaches near the walls: a bird by the wall
## must already be in the clear band then.
func safe_y(y: int, steps: int) -> bool:
	if phase != 2:
		return true
	var c := clock_in(steps)
	if c < 0:
		return true
	var lt := c % RING_CYCLE
	if lt < RING_OUT or lt >= RING_IN:
		return true
	var k := c / RING_CYCLE
	var at := to_y if k == _k else RING_YS[draw(k, 2) % 2]
	return absi(y - at) >= ring_max() + BLADE_R + SimConfig.BIRD_RADIUS + MARGIN


func checksum(h: int) -> int:
	var out := mix_all(super(h), [king_y, from_y, to_y, ring, angle, blades, int(telling), _k])
	for i in blades:
		out = mix_all(out, [blade_x[i], blade_y[i]])
	return out


## While the warning ring shows: the way the saw jumps and where it lands (with
## its blade ring in phase 3), until its next jump; in phase 2 also the reach
## of the blades it swings out there.
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if down_at >= 0 or clock() < 0 or not telling:
		return
	var lt := clock() % cycle()
	var top := mini(from_y, to_y)
	var bottom := maxi(from_y, to_y)
	if lt < TELL:
		var r := KING_R + (RING_HOP + BLADE_R if phase == 3 else 0)
		add_warning(
			out, KING_X - r, top - r, KING_X + r, bottom + r, TELL - lt, cycle() - TELL, WARN_KILL
		)
	if phase == 2:
		var far := ring_max() + BLADE_R
		var eta := RING_OUT - lt + (RING_SHOW + RING_SPEED - 1) / RING_SPEED
		var dur := RING_IN - RING_OUT + ring_max() / RING_SPEED
		add_warning(out, KING_X - far, to_y - far, KING_X + far, to_y + far, eta, dur, WARN_KILL)
