extends Hazard
## A lantern on a chain swinging from the ceiling (Lantern Swing). The lantern
## kills; the chain is safe. Settings per lantern, so a room can hang several:
## its pivot, chain, size, widest swing and swing time. Options: a gust makes
## the swing grow and shrink, a winch winds the chain up and down, and a twin
## is a second lantern on its own chain swinging exactly the other way.

## The classic lantern (Double Trouble): stays inside x 40..320 px.
const PIVOT_X := 180 * SimConfig.SUB
const PIVOT_Y := SimConfig.KILL_TOP
const LENGTH := 280 * SimConfig.SUB
const RADIUS := 22 * SimConfig.SUB
## Widest swing as a SimTrig angle (52/1024 of a turn, about 18 degrees).
const AMPLITUDE := 52
## Steps per full swing (there and back).
const PERIOD := 180
## Out of a portal: evenly spaced swings tried, to keep the lantern off the
## arrival path (FairLanes.arrival_path).
const ARRIVAL_TRIES := 32
## Chain lengths blocks_exit() tries apart, for a winch.
const SWING_STEP := 4 * SimConfig.SUB
## adjust_wall: a bird at a free height of the wall it flies to must stay
## clear of the lanterns (by MARGIN) from WALL_FROM to WALL_TO steps around
## its arrival there (sampled every WALL_STEP), flying in and back out.
const WALL_FROM := -30
const WALL_TO := 12
const WALL_STEP := 3
const MARGIN := 4 * SimConfig.SUB
## Generated Lantern Swing's fallback: chains stay at least this long, lanterns
## inside x SIDE_MIN..SIDE_MAX, and swing phases tried when no length fits.
const MIN_CHAIN := 60 * SimConfig.SUB
const SIDE_MIN := 40 * SimConfig.SUB
const SIDE_MAX := 320 * SimConfig.SUB
const FALLBACK_PHASES := 16

var pivot_x := PIVOT_X
var pivot_y := PIVOT_Y
var length := LENGTH
var radius := RADIUS
var amplitude := AMPLITUDE
var period := PERIOD
## Gust: the widest swing grows and shrinks by this much (SimTrig units) over
## gust_period steps, starting at `amplitude` and growing. 0 = steady.
var gust := 0
var gust_period := 1
## Winch: the chain winds this much shorter and longer than `length` over
## winch_period steps, starting at its shortest. 0 = fixed chain.
var winch := 0
var winch_period := 1
## Twin: a second lantern (twin_length 0 = none) at twin_x on the ceiling,
## swinging the opposite way to the first.
var twin_x := 0
var twin_length := 0

var phase := 0
## Current swing angle (SimTrig units, 0 = straight down, + = to the right).
var angle := 0
## Current chain length (changes with a winch).
var chain := 0
## Lantern centre.
var x := 0
var y := 0
## Twin lantern centre (when there is one).
var x2 := 0
var y2 := 0


func _init(
	p_pivot_x := PIVOT_X,
	p_length := LENGTH,
	p_radius := RADIUS,
	p_amplitude := AMPLITUDE,
	p_period := PERIOD
) -> void:
	kind = "pendulum"
	pivot_x = p_pivot_x
	length = p_length
	radius = p_radius
	amplitude = p_amplitude
	period = p_period


## The widest swing changes by `p_gust` over `p_period` steps.
func gusting(p_gust: int, p_period: int) -> Hazard:
	gust = p_gust
	gust_period = p_period
	return self


## The chain winds `p_winch` shorter and longer over `p_period` steps.
func winding(p_winch: int, p_period: int) -> Hazard:
	winch = p_winch
	winch_period = p_period
	return self


## Adds a twin lantern on a `p_length` chain at `p_x`, swinging the other way.
func with_twin(p_x: int, p_length: int) -> Hazard:
	twin_x = p_x
	twin_length = p_length
	return self


func has_twin() -> bool:
	return twin_length > 0


## Generated Lantern Swing's fallback: gives each lantern (the twin too) the
## chain nearest its own that keeps its whole swing (widest swing, whole winch)
## off the band a bird holding its height sweeps, above it or below it, inside
## the cage, its pivot moved in if the swing would leave SIDE_MIN..SIDE_MAX. If
## winding makes that impossible, the winch winds half as far, then not at
## all. Changes nothing and returns false if no chain works. No RNG.
func fit_clear(p: VariantParams) -> bool:
	var widest := amplitude + absi(gust)
	var c := SimTrig.cos_t(widest)
	var s := SimTrig.sin_t(widest)
	var main := PackedInt32Array()
	var w := 0
	for wind: int in [absi(winch), absi(winch) / 2, 0]:
		main = _clear_chain(p, length, wind, pivot_x, c, s)
		if not main.is_empty():
			w = wind
			break
	if main.is_empty():
		return false
	var twin := PackedInt32Array([twin_length, twin_x])
	if has_twin():
		twin = _clear_chain(p, twin_length, 0, twin_x, c, s)
		if twin.is_empty():
			return false
	length = main[0]
	pivot_x = main[1]
	twin_length = twin[0]
	twin_x = twin[1]
	winch = w if winch >= 0 else -w
	_place()
	return true


## The chain nearest `l` (winding `w` either way) that keeps this lantern's
## swing clear of the hold band, and the pivot x for it (`px`, moved in when
## the swing would leave SIDE_MIN..SIDE_MAX), as [chain, x]; empty if none.
func _clear_chain(p: VariantParams, l: int, w: int, px: int, c: int, s: int) -> PackedInt32Array:
	# Above the band: the lowest point (chain + winch + radius) over its top;
	# any chain this long or shorter is clear.
	var up := p.hold_top() - SimConfig.SUB - pivot_y - w - radius
	# Below the band: the highest point ((chain - winch) * cos - radius) under
	# it; any chain this long or longer is clear.
	var down := ((p.hold_bottom() + SimConfig.SUB + radius - pivot_y) * SimTrig.ONE + c - 1) / c + w
	# The valid one nearest `l` (the first of equals, in this order).
	var out := PackedInt32Array()
	var best := -1
	for t: int in [mini(l, up), maxi(l, down), up, down]:
		if t - w < MIN_CHAIN or pivot_y + t + w + radius > SimConfig.KILL_BOTTOM:
			continue
		var side := (t + w) * s / SimTrig.ONE + radius
		if SIDE_MIN + side > SIDE_MAX - side:
			continue
		if best < 0 or absi(t - l) < best:
			best = absi(t - l)
			out = PackedInt32Array([t, clampi(px, SIDE_MIN + side, SIDE_MAX - side)])
	return out


func setup(sim: GameSim, rng: SimRng) -> void:
	phase = rng.next_below(SimTrig.TURN)
	var first := phase
	var pick := phase
	if sim.state.started:
		# Out of a portal: the first swing that keeps the lanterns off the
		# arrival lane (else see FairLanes.ARRIVAL_PATH_MIN; else the swing
		# drawn).
		var arrival := FairLanes.arrival_path(sim)
		var settled := false
		for k in ARRIVAL_TRIES:
			phase = (first + k * SimTrig.TURN / ARRIVAL_TRIES) % SimTrig.TURN
			var clear := _arrival_clear(arrival)
			if clear >= FairLanes.ARRIVAL_PATH_TICKS:
				pick = phase
				break
			if clear >= FairLanes.ARRIVAL_PATH_MIN and not settled:
				pick = phase
				settled = true
	else:
		# Before the first tap (the room waits for it): the first swing that
		# keeps the lanterns off the bird's forced first hop
		# (FairLanes.start_path), else the one that keeps off it longest.
		var start := FairLanes.start_path(sim)
		var best := -1
		for k in ARRIVAL_TRIES:
			phase = (first + k * SimTrig.TURN / ARRIVAL_TRIES) % SimTrig.TURN
			var clear := _path_clear(start)
			if clear > best:
				best = clear
				pick = phase
			if clear >= FairLanes.START_PATH:
				break
	phase = pick
	_place()


## Steps until a lantern first comes near the arrival path
## (FairLanes.arrival_path), or ARRIVAL_PATH_TICKS if none does.
func _arrival_clear(arrival: PackedInt32Array) -> int:
	return _path_clear(arrival)


## Steps until a lantern first comes near the bird on `path` (x, y pairs per
## step, FairLanes.arrival_path_hits), or the path's length if none does.
func _path_clear(path: PackedInt32Array) -> int:
	var keep := t
	var out := path.size() / 2
	for k in path.size() / 2:
		t = k
		_place()
		if FairLanes.arrival_path_hits(path, k, x, y, radius):
			out = k
			break
		if has_twin() and FairLanes.arrival_path_hits(path, k, x2, y2, radius):
			out = k
			break
	t = keep
	_place()
	return out


func step(_sim: GameSim) -> void:
	_place()


func _place() -> void:
	var widest := amplitude
	if gust != 0:
		widest += gust * SimTrig.sin_t(t * SimTrig.TURN / gust_period) / SimTrig.ONE
	chain = length
	if winch != 0:
		var wind := t * SimTrig.TURN / winch_period - SimTrig.TURN / 4
		chain += winch * SimTrig.sin_t(wind) / SimTrig.ONE
	angle = widest * SimTrig.sin_t(phase + t * SimTrig.TURN / period) / SimTrig.ONE
	x = pivot_x + chain * SimTrig.sin_t(angle) / SimTrig.ONE
	y = pivot_y + chain * SimTrig.cos_t(angle) / SimTrig.ONE
	if has_twin():
		x2 = twin_x - twin_length * SimTrig.sin_t(angle) / SimTrig.ONE
		y2 = pivot_y + twin_length * SimTrig.cos_t(angle) / SimTrig.ONE


## A swinging lantern can't keep out of an exit's mouth (ExitZone), so an exit
## goes nowhere its swing could ever reach: every angle of the widest swing,
## every chain length of the winch, for both lanterns.
func blocks_exit(sim: GameSim, side: int, p_y: int) -> bool:
	var widest := amplitude + absi(gust)
	var longest := length + absi(winch)
	if not _may_reach(sim, side, pivot_x, longest):
		if not has_twin() or not _may_reach(sim, side, twin_x, twin_length):
			return false
	var a := -widest
	while a <= widest:
		var s := SimTrig.sin_t(a)
		var c := SimTrig.cos_t(a)
		var chain_len := length - absi(winch)
		while chain_len <= longest:
			var lx := pivot_x + chain_len * s / SimTrig.ONE
			var ly := pivot_y + chain_len * c / SimTrig.ONE
			if ExitZone.circle_in_box(sim, side, p_y, lx, ly, radius):
				return true
			chain_len += SWING_STEP if winch != 0 else longest + 1
		if has_twin():
			var tx := twin_x - twin_length * s / SimTrig.ONE
			var ty := pivot_y + twin_length * c / SimTrig.ONE
			if ExitZone.circle_in_box(sim, side, p_y, tx, ty, radius):
				return true
		a += 1
	return false


## True if a lantern on a `chain_len` chain from `px` could get near wall `side`.
func _may_reach(sim: GameSim, side: int, px: int, chain_len: int) -> bool:
	var far := chain_len + radius
	if side == 0:
		return px - far <= ExitZone.right_on(sim, 0)
	return px + far >= ExitZone.left_on(sim, 1)


## Keeps a way past the lanterns on the wall the bird flies to: a free run as
## wide as the room's gap (or the widest the lanterns leave) whose heights no
## lantern swings in front of around the bird's arrival (WALL_FROM..WALL_TO).
## The swing is fixed by time, so this reads no bird but its x. No RNG draws.
func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var at := sim.steps_to_wall(side)
	var r := SimConfig.BIRD_RADIUS
	var edge := sim.room.wall_right() - r if side == 1 else sim.room.wall_left() + r
	var into := -1 if side == 1 else 1
	var reach := radius + r + MARGIN
	var keep := t
	var blocked := 0
	for d in range(WALL_FROM, WALL_TO + 1, WALL_STEP):
		t = keep + at + d
		_place()
		var bx := edge + into * absi(d) * SimConfig.SPEED_X
		for slot in SimConfig.SLOT_COUNT:
			var sy := SimConfig.slot_center_y(slot)
			if _near(bx, sy, x, y, reach) or has_twin() and _near(bx, sy, x2, y2, reach):
				blocked |= 1 << slot
	t = keep
	_place()
	var safe := ((1 << SimConfig.SLOT_COUNT) - 1) & ~blocked
	var need := mini(sim.room.def.gap, RoomRules.longest_gap(blocked))
	return RoomRules.keep_run(mask, need, safe)


static func _near(ax: int, ay: int, bx: int, by: int, reach: int) -> bool:
	var dx := ax - bx
	var dy := ay - by
	return dx * dx + dy * dy < reach * reach


func kills(sim: GameSim) -> bool:
	if has_twin() and sim.bird_touches_circle(x2, y2, radius):
		return true
	return sim.bird_touches_circle(x, y, radius)


func checksum(h: int) -> int:
	return mix_all(
		h, [phase, angle, chain, x, y, x2, y2, length, twin_length, winch, pivot_x, twin_x]
	)
