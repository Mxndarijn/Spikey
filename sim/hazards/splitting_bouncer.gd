extends "res://sim/hazards/bouncer.gd"
## Splitting Bramble: a big, slow ball that shakes for a second (the warning)
## and then bursts into two small, quick balls flying apart up and down. It
## only splits while it is well away from the bird; until then it keeps
## shaking.

const Bouncer := preload("res://sim/hazards/bouncer.gd")

const BIG_RADIUS := 24 * SimConfig.SUB
## 2.4 px across and 2 px up or down per step.
const BIG_SPEED_X := 154
const BIG_SPEED_Y := 2 * SimConfig.SUB
const SMALL_RADIUS := 14 * SimConfig.SUB
## Steps before the shaking starts, and how long it shakes at least.
const SPLIT_AT := 240
const WARN := 60
## It splits only this far (centre to centre) from the bird.
const CLEAR := 120 * SimConfig.SUB

## Steps it has shaken so far (0..WARN), for the painter.
var warn := 0
## The second ball once it has split, null before.
var other: Bouncer = null


func _init() -> void:
	super(BIG_RADIUS)


func setup(sim: GameSim, rng: SimRng) -> void:
	super.setup(sim, rng)
	vx = signi(vx) * BIG_SPEED_X
	vy = signi(vy) * BIG_SPEED_Y


func step(sim: GameSim) -> void:
	move(sim)
	if other != null:
		other.move(sim)
		return
	if t < SPLIT_AT:
		return
	warn = mini(t - SPLIT_AT, WARN)
	if warn < WARN:
		return
	var dx := x - sim.state.x
	var dy := y - sim.state.y
	if dx * dx + dy * dy < CLEAR * CLEAR:
		return
	_split()


func _split() -> void:
	radius = SMALL_RADIUS
	vx = signi(vx) * SPEED_X
	vy = -SPEED_Y
	other = Bouncer.new(SMALL_RADIUS)
	other.x = x
	other.y = y
	other.vx = vx
	other.vy = SPEED_Y


func is_split() -> bool:
	return other != null


func kills(sim: GameSim) -> bool:
	if super.kills(sim):
		return true
	return other != null and other.kills(sim)


## Its path isn't a straight bounce, so it can't say ahead where it will be.
func straight_path() -> bool:
	return false


func checksum(h: int) -> int:
	var out := mix_all(super.checksum(h), [radius, warn])
	if other != null:
		out = other.checksum(out)
	return out


## While it shakes: the ball where it is now (the two halves start there). It
## splits at the end of the shaking, or later, once the bird is CLEAR of it.
func warnings(_sim: GameSim, out: PackedInt64Array) -> void:
	if other != null or t < SPLIT_AT:
		return
	add_warning(out, x - radius, y - radius, x + radius, y + radius, WARN - warn, 1, WARN_KILL)
