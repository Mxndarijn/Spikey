extends Hazard
## Locked Out: the room's exit opens locked. Until the bird has every key,
## flying into the exit is a bounce (Hazard.locks_exit), and with the exit
## open a bounce scores nothing, so the room waits for the keys.
##
## While the exit is locked the cage closes in (lockdown): every bounce adds a
## spike next to the free run of the new wall, up to LOCKDOWN_MAX. After
## MAX_LOCKED_BOUNCES locked bounces the lock gives up, so the room is never a
## trap.
##
## Keys sit in the wall bands (KEY_OFF_MIN to KEY_OFF_MAX from a wall), so the
## bird takes one just after a bounce. Every second new wall on a key's side
## keeps a bounce spot clear at the key's height (adjust_wall), and an exit
## planned on a key's wall opens near the key (blocks_exit).
##
## Variants (the room's variant id picks one):
##   orbit:   one key on a wide oval that swings through both wall bands.
##   trio:    three keys, all shown at the start; you need all three.
##   quad:    the same with four keys.
##   chain:   three keys, one at a time; the next shows up near the wall the
##            bird just left, at least CHAIN_D_MIN away from its height.
## One key pays COINS; with more keys each pays 1 and the last adds a bonus of
## one coin per key.
enum Mode { ORBIT, TRIO, QUAD, CHAIN }

const SUB := SimConfig.SUB
const RADIUS := 12 * SUB
const COINS := 3
const MAX_KEYS := 4
## The lock gives up after this many bounces with the exit locked.
const MAX_LOCKED_BOUNCES := 8
## Lockdown: at most this many spikes added to a new wall.
const LOCKDOWN_MAX := 4
## Wall bands: a key's distance from its wall.
const KEY_OFF_MIN := 62 * SUB
const KEY_OFF_MAX := 96 * SUB
const KEY_MIN_Y := 130 * SUB
const KEY_MAX_Y := 510 * SUB
## A wall-band key keeps wall slots this close to its height free, every
## second wall on its side, so the bird can bounce there and take it.
const SPOT_HALF := 30 * SUB
## An exit on a key's wall opens at most this far from the key's height.
const EXIT_NEAR := 100 * SUB
## Laid-out keys (trio, quad): one per height band between these, with a
## margin, x in one of three zones (left band, middle, right band).
const LAYOUT_TOP := 120
const LAYOUT_SPAN := 400
const LAYOUT_MARGIN := 15
const ZONE_LO: Array[int] = [62, 160, 264]
const ZONE_HI: Array[int] = [96, 200, 298]
## Laid-out keys are at least this far apart, and two in the same zone at
## least ZONE_APART apart in height. A bad layout is drawn again, up to
## PLACE_TRIES times, then a fixed zigzag is used.
const KEYS_APART := 110 * SUB
const ZONE_APART := 150 * SUB
const PLACE_TRIES := 12
## Chain: the next key's distance from the wall behind the bird, and from the
## bird's height.
const CHAIN_OFF_MAX := 150 * SUB
const CHAIN_D_MIN := 160 * SUB
const CHAIN_D_MAX := 200 * SUB
const MID_Y := 320 * SUB
## Orbit: an oval round the middle, one lap in ORBIT_STEPS.
const ORBIT_CX := 180 * SUB
const ORBIT_CY := 330 * SUB
const ORBIT_RX := 128 * SUB
const ORBIT_RY := 165 * SUB
const ORBIT_STEPS := 540

var mode := Mode.ORBIT
## Keys needed, and taken so far.
var count := 1
var got := 0
## Bit i: key i is taken.
var taken_mask := 0
## Key spots (a chain key's spot is set when it shows up).
var kx: Array[int] = [0, 0, 0, 0]
var ky: Array[int] = [0, 0, 0, 0]
## Room step a key showed up (for the painter's pop-in).
var born: Array[int] = [0, 0, 0, 0]
## Chain: each next key's distance from the wall, and from the bird's height.
var chain_off: Array[int] = [0, 0, 0, 0]
var chain_d: Array[int] = [0, 0, 0, 0]
var phase := 0
var locked_bounces := 0
## New walls made on each side (left, right) since the room began.
var walls_left := 0
var walls_right := 0
## The open exit, copied each step for the painter (it draws the padlock).
var door_open := false
var door_side := 0
var door_a_y := 0
var door_b_y := 0


## `p_mode` -1: take it from the room's variant.
func _init(p_mode: int = -1) -> void:
	kind = "exit_key"
	mode = p_mode


## Draws, in order: orbit its phase; trio and quad their layout (_lay_out);
## chain a side, a wall offset and a height for its first key, then an offset
## and a distance per later key.
func setup(sim: GameSim, rng: SimRng) -> void:
	if mode < 0:
		match sim.room.variant_id():
			"trio":
				mode = Mode.TRIO
			"quad":
				mode = Mode.QUAD
			"chain":
				mode = Mode.CHAIN
			_:
				mode = Mode.ORBIT
	match mode:
		Mode.TRIO:
			count = 3
		Mode.QUAD:
			count = 4
		Mode.CHAIN:
			count = 3
		_:
			count = 1
	match mode:
		Mode.ORBIT:
			phase = rng.next_below(SimTrig.TURN)
			_place_orbit()
		Mode.TRIO, Mode.QUAD:
			_lay_out(rng)
		Mode.CHAIN:
			var side := rng.next_below(2)
			var off := KEY_OFF_MIN + rng.next_below(KEY_OFF_MAX - KEY_OFF_MIN + 1)
			kx[0] = _from_wall(sim, side, off)
			ky[0] = KEY_MIN_Y + rng.next_below(KEY_MAX_Y - KEY_MIN_Y + 1)
			for i in range(1, count):
				chain_off[i] = KEY_OFF_MIN + rng.next_below(CHAIN_OFF_MAX - KEY_OFF_MIN + 1)
				chain_d[i] = CHAIN_D_MIN + rng.next_below(CHAIN_D_MAX - CHAIN_D_MIN + 1)


## One key per height band, x from the zones in a shuffled order (each zone
## once before one repeats), redrawn while two keys sit too close.
func _lay_out(rng: SimRng) -> void:
	var band := LAYOUT_SPAN / count
	var zones: Array[int] = [0, 0, 0, 0]
	for attempt in PLACE_TRIES:
		var order: Array[int] = [0, 1, 2]
		for i in [2, 1]:
			var j := rng.next_below(i + 1)
			var swap := order[i]
			order[i] = order[j]
			order[j] = swap
		while order.size() < count:
			order.append(0 if rng.next_below(2) == 0 else 2)
		for i in count:
			var z := order[i]
			zones[i] = z
			kx[i] = (ZONE_LO[z] + rng.next_below(ZONE_HI[z] - ZONE_LO[z] + 1)) * SUB
			var top := LAYOUT_TOP + i * band + LAYOUT_MARGIN
			ky[i] = (top + rng.next_below(band - 2 * LAYOUT_MARGIN + 1)) * SUB
		if _layout_ok(zones):
			return
	for i in count:
		kx[i] = (80 if i % 2 == 0 else 280) * SUB
		ky[i] = (LAYOUT_TOP + i * band + band / 2) * SUB


func _layout_ok(zones: Array[int]) -> bool:
	for i in count:
		for j in range(i + 1, count):
			var dx := kx[i] - kx[j]
			var dy := ky[i] - ky[j]
			if dx * dx + dy * dy < KEYS_APART * KEYS_APART:
				return false
			if zones[i] == zones[j] and absi(dy) < ZONE_APART:
				return false
	return true


## x at `off` from wall `side` (0 = left, 1 = right).
static func _from_wall(sim: GameSim, side: int, off: int) -> int:
	return sim.room.wall_left() + off if side == 0 else sim.room.wall_right() - off


func step(sim: GameSim) -> void:
	if mode == Mode.ORBIT and not done():
		_place_orbit()
	var s := sim.state
	door_open = s.exit_open
	door_side = s.exit_side
	door_a_y = s.exit_a_y
	door_b_y = s.exit_b_y if s.exit_b_kind != SimState.ExitKind.NORMAL else 0


func _place_orbit() -> void:
	var a := phase + t * SimTrig.TURN / ORBIT_STEPS
	kx[0] = ORBIT_CX + ORBIT_RX * SimTrig.cos_t(a) / SimTrig.ONE
	ky[0] = ORBIT_CY + ORBIT_RY * SimTrig.sin_t(a) / SimTrig.ONE


## All keys taken.
func done() -> bool:
	return got >= count


## Whether key `i` is in the room now: not taken, and in a chain the current
## one.
func shown(i: int) -> bool:
	if i >= count or (taken_mask >> i) & 1 == 1:
		return false
	return mode != Mode.CHAIN or i == got


func touch(sim: GameSim) -> void:
	for i in count:
		if not shown(i) or not sim.bird_touches_circle(kx[i], ky[i], RADIUS):
			continue
		taken_mask |= 1 << i
		got += 1
		if count == 1:
			for c in COINS:
				sim.collect_coin(kx[i], ky[i])
		else:
			sim.collect_coin(kx[i], ky[i])
			if done():
				sim.collect_coin(kx[i], ky[i], count)
		if mode == Mode.CHAIN and not done():
			_show_next(sim, got)
		return


## Chain: key `i` shows up near the wall behind the bird, far from its height.
func _show_next(sim: GameSim, i: int) -> void:
	var s := sim.state
	kx[i] = _from_wall(sim, 0 if s.vx > 0 else 1, chain_off[i])
	var y := s.y - chain_d[i] if s.y > MID_Y else s.y + chain_d[i]
	ky[i] = clampi(y, KEY_MIN_Y, KEY_MAX_Y)
	born[i] = t


## The first key still out in wall `side`'s band (within CHAIN_OFF_MAX of
## it), or -1. The orbit key moves, so it never counts.
func band_key(side: int) -> int:
	if mode == Mode.ORBIT:
		return -1
	for i in count:
		if not shown(i):
			continue
		var off := kx[i] if side == 0 else SimConfig.WORLD_W - kx[i]
		if off <= CHAIN_OFF_MAX:
			return i
	return -1


func adjust_wall(sim: GameSim, side: int, mask: int) -> int:
	var walls := 0
	if side == 0:
		walls_left += 1
		walls = walls_left
	else:
		walls_right += 1
		walls = walls_right
	var out := mask
	# A bounce spot at a wall-band key's height, every second wall.
	var spot := 0
	var k := band_key(side)
	if k >= 0 and walls % 2 == 0:
		for slot in SimConfig.SLOT_COUNT:
			if absi(SimConfig.slot_center_y(slot) - ky[k]) <= SPOT_HALF:
				spot |= 1 << slot
		out &= ~spot
	# Lockdown: spikes next to the free run, one more per locked bounce.
	if sim.state.exit_open and locked():
		out = _add_spikes(out, mini(LOCKDOWN_MAX, locked_bounces + 1), spot)
	return out


## Adds up to `n` spikes to `mask`, in the free slots nearest the free run
## (above it first, then below, moving outward), never in the free run or in
## `keep`.
static func _add_spikes(mask: int, n: int, keep: int) -> int:
	var run := RoomRules.longest_gap_mask(mask)
	if run == 0:
		return mask
	var lo := 0
	while (run >> lo) & 1 == 0:
		lo += 1
	var hi := lo
	while hi + 1 < SimConfig.SLOT_COUNT and (run >> (hi + 1)) & 1 == 1:
		hi += 1
	var out := mask
	var added := 0
	for d in range(1, SimConfig.SLOT_COUNT):
		for slot: int in [lo - d, hi + d]:
			if added >= n:
				return out
			if slot < 0 or slot >= SimConfig.SLOT_COUNT:
				continue
			if (out >> slot) & 1 == 1 or (keep >> slot) & 1 == 1:
				continue
			out |= 1 << slot
			added += 1
	return out


## An exit on a wall with a key in its band opens near that key.
func blocks_exit(_sim: GameSim, side: int, y: int) -> bool:
	var k := band_key(side)
	return k >= 0 and absi(y - ky[k]) > EXIT_NEAR


func locks_exit(_sim: GameSim) -> bool:
	return locked()


## Whether the open exit is locked right now (for the view).
func locked() -> bool:
	return not done() and locked_bounces < MAX_LOCKED_BOUNCES


func on_bounce(sim: GameSim, _rng: SimRng) -> void:
	if sim.state.exit_open and not done():
		locked_bounces += 1


func checksum(h: int) -> int:
	var out := mix_all(
		h,
		[
			mode,
			count,
			got,
			taken_mask,
			phase,
			locked_bounces,
			walls_left,
			walls_right,
			int(door_open),
			door_side,
			door_a_y,
			door_b_y
		]
	)
	for i in MAX_KEYS:
		out = mix_all(out, [kx[i], ky[i], born[i], chain_off[i], chain_d[i]])
	return out
