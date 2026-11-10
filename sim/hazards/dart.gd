extends Hazard
## Hunter Spike: a spike on the far wall glows, a dashed lane line marks the
## bird's height at the moment the glow starts, then the spike shoots across
## along that lane. Only the flying dart kills.
##
## Lanes mode (Valentine's Cupid Lanes): a lane picked from the
## room's RNG flashes, then an arrow crosses it. Rooms use at most two lanes
## darts (different `slot`s) so at most two lanes are live at once.
##
## Twin hunters: one dart per wall (`home`), always firing from it; the second
## (slot 1) starts TWIN_DELAY steps later, half a cycle, so they take turns.

enum State { IDLE, GLOW, FLY }

const START_DELAY := 60
const IDLE_TICKS := 50
const GLOW_TICKS := 40
const SPEED := 7 * SimConfig.SUB
## Length and half height of the dart (its deadly body).
const LENGTH := 30 * SimConfig.SUB
const HALF_H := 5 * SimConfig.SUB
## Lanes stay clear of the ceiling and floor.
const LANE_MIN := 90 * SimConfig.SUB
const LANE_MAX := 550 * SimConfig.SUB
## Lanes mode: LANES fixed lanes from LANE_MIN to LANE_MAX.
const LANES := 8
const LANE_STEP := (LANE_MAX - LANE_MIN) / (LANES - 1)
const LANES_SPEED := 6 * SimConfig.SUB
const LANES_FLASH := 45
const LANES_IDLE := 40
## Lanes mode: extra start delay per slot so two darts take turns.
const SLOT_DELAY := 70
## Twin hunters: the second dart's extra start delay (a cycle is about 150 steps).
const TWIN_DELAY := 75

## Lanes mode (Cupid Lanes) instead of hunting the bird.
var lanes := false
## Which of a room's lanes darts this is (staggers their timing).
var slot := 0
## The wall this dart always fires from (0 = left, 1 = right), or -1: the far
## wall from the bird at each shot.
var home := -1
var state := State.IDLE
## Step at which the current state began, and how long the idle wait lasts.
var since := 0
var wait := START_DELAY
## Wall the dart leaves from: 0 = left, 1 = right.
var side := 1
## Height of the lane, and the dart's tip x while flying.
var lane_y := 0
var x := 0
## Shots so far and the RNG salt (lanes mode picks lanes from them).
var shots := 0
var salt := 0


func _init(p_lanes: bool = false, p_slot: int = 0, p_home: int = -1) -> void:
	kind = "dart"
	lanes = p_lanes
	slot = p_slot
	home = p_home


func setup(sim: GameSim, rng: SimRng) -> void:
	salt = rng.next_u32()
	state = State.IDLE
	since = 0
	wait = START_DELAY + slot * (SLOT_DELAY if lanes else TWIN_DELAY)
	side = 1 if sim.state.x < SimConfig.WORLD_W / 2 else 0
	if home >= 0:
		side = home
	lane_y = LANE_MIN
	x = _base_x()


func _base_x() -> int:
	return 0 if side == 0 else SimConfig.WORLD_W


func _dir() -> int:
	return 1 if side == 0 else -1


func step(sim: GameSim) -> void:
	match state:
		State.IDLE:
			if t - since >= wait:
				_aim(sim)
				state = State.GLOW
				since = t
		State.GLOW:
			if t - since >= (LANES_FLASH if lanes else GLOW_TICKS):
				state = State.FLY
				since = t
				x = _base_x()
		State.FLY:
			x += _dir() * (LANES_SPEED if lanes else SPEED)
			if x < -LENGTH or x > SimConfig.WORLD_W + LENGTH:
				state = State.IDLE
				since = t
				wait = LANES_IDLE if lanes else IDLE_TICKS
				shots += 1
				x = _base_x()


## Picks the lane and wall for the next shot.
func _aim(sim: GameSim) -> void:
	if lanes:
		var r := SimHash.mix(salt, shots)
		lane_y = LANE_MIN + posmod(r, LANES) * LANE_STEP
		side = (r >> 8) & 1
		return
	# The far wall from the bird, at the bird's height right now.
	side = 1 if sim.state.x < SimConfig.WORLD_W / 2 else 0
	if home >= 0:
		side = home
	lane_y = clampi(sim.state.y, LANE_MIN, LANE_MAX)


## 0..1024 how far into the warning (0 outside it).
func glow() -> int:
	if state != State.GLOW:
		return 0
	return SimTrig.ONE * (t - since) / (LANES_FLASH if lanes else GLOW_TICKS)


## The back end of the dart (the tip is `x`).
func tail_x() -> int:
	return x - _dir() * LENGTH


func kills(sim: GameSim) -> bool:
	if state != State.FLY:
		return false
	return sim.bird_touches_rect(tail_x(), lane_y - HALF_H, x, lane_y + HALF_H)


func checksum(h: int) -> int:
	return mix_all(
		h, [int(lanes), slot, home, int(state), since, wait, side, lane_y, x, shots, salt]
	)
