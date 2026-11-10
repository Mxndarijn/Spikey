class_name RoomRuntime
extends RefCounted
## The room being played: its RoomDef, its live hazards, and the wall rules that
## change over time (tide spikes, blinking walls, squeezing walls, speed).

const TIDE_PERIOD := 120
## Narrow: how fast the walls slide in at room start, per step.
const INSET_SPEED := 2 * SimConfig.SUB
const BLINK_PERIOD := 60
## Squeeze Box: each point in the room moves both walls in by this much.
const SQUEEZE_STEP := 6 * SimConfig.SUB
const SQUEEZE_MAX_POINTS := 10
const CoinPickup := preload("res://sim/hazards/coin_pickup.gd")

var def: RoomDef
## Index of `def` in RoomCatalog.all() (part of the checksum).
var index := 0
## Sim steps since the room started (speed changes how many per tick).
var t := 0
## Real ticks since the room started.
var ticks := 0
## Points scored in this room.
var points := 0
## Which of def.variants this room is (0 when the room has none).
var variant := 0
var hazards: Array[Hazard] = []
## Tide: which spiked slots move, and a phase offset (redrawn every bounce).
var tide_left := 0
var tide_right := 0
var tide_salt := 0
## Blink: the second pattern of each wall.
var blink_left := 0
var blink_right := 0


func start(p_def: RoomDef, p_index: int, sim: GameSim, rng: SimRng) -> void:
	def = p_def
	index = p_index
	t = 0
	ticks = 0
	points = 0
	variant = 0
	tide_left = 0
	tide_right = 0
	tide_salt = 0
	blink_left = 0
	blink_right = 0
	hazards.clear()
	var list: Array[Callable] = def.hazards.duplicate()
	# The variant is drawn first, then the combo: this order is part of the rules.
	if def.variants.size() > 1:
		variant = rng.next_below(def.variants.size())
	if not def.variants.is_empty():
		for f: Callable in def.variants[variant].hazards:
			list.append(f)
	if not def.combos.is_empty():
		var combo: Array = def.combos[rng.next_below(def.combos.size())]
		for f: Callable in combo:
			list.append(f)
	for f in list:
		var h: Hazard = f.call()
		h.skin = def.skin
		hazards.append(h)
		h.setup(sim, rng)


## How many sim steps this tick runs: Midnight Cage runs 5 per 4 ticks,
## Slow-Mo Breather 1 per 2 ticks.
func steps_this_tick() -> int:
	return steps_at(ticks)


## Sim steps that room tick `tick` runs.
func steps_at(tick: int) -> int:
	match def.speed:
		RoomDef.Speed.FAST:
			return 2 if tick % 4 == 0 else 1
		RoomDef.Speed.SLOW:
			return 1 if tick % 2 == 0 else 0
	return 1


func step(sim: GameSim) -> void:
	t += 1
	for h in hazards:
		if h.alive:
			h.t = t
			h.step(sim)


## How far both walls stand in from the cage's edge right now. Narrow slides
## them in over the room's first steps (the bird leaves its wall twice as fast,
## so a wall never catches it); Squeeze Box steps them in per point.
func inset() -> int:
	var out := mini(t * INSET_SPEED, def.inset)
	if def.squeeze:
		out += mini(points, SQUEEZE_MAX_POINTS) * SQUEEZE_STEP
	return out


## Id of the variant being played ("" when the room has none).
func variant_id() -> String:
	return "" if def.variants.is_empty() else def.variants[variant].id


## A still wall spike's depth in this room (the variant can scale it).
func spike_depth() -> int:
	if def.variants.is_empty():
		return SimConfig.SPIKE_DEPTH
	var v := def.variants[variant]
	return SimConfig.SPIKE_DEPTH * v.spike_num / v.spike_den


## Half the height of a wall spike's base: scaled like its depth, but never
## wider than its slot.
func spike_half_base() -> int:
	if def.variants.is_empty():
		return SimConfig.SPIKE_HALF_BASE
	var v := def.variants[variant]
	return mini(SimConfig.SPIKE_HALF_BASE * v.spike_num / v.spike_den, SimConfig.SLOT_SIZE / 2)


## Tide spikes slide from flat to this far out: 1.5 times a still spike.
func tide_max_depth() -> int:
	return spike_depth() * 3 / 2


## The furthest any wall spike can reach in this room.
func max_spike_depth() -> int:
	return tide_max_depth() if def.wall_mode == RoomDef.WallMode.TIDE else spike_depth()


## The variant's extra (or fewer) spikes per wall.
func spike_bonus() -> int:
	return 0 if def.variants.is_empty() else def.variants[variant].extra_spikes


func wall_left() -> int:
	return inset()


func wall_right() -> int:
	return SimConfig.WORLD_W - inset()


func blink_showing_second() -> bool:
	return def.wall_mode == RoomDef.WallMode.BLINK and (t / BLINK_PERIOD) % 2 == 1


## The spike mask a wall shows right now (0 = left, 1 = right).
func wall_mask(side: int, base_mask: int) -> int:
	if blink_showing_second():
		return blink_left if side == 0 else blink_right
	return base_mask


## How far a wall spike sticks out right now; tide spikes slide in and out,
## from flat to longer than a normal spike.
func slot_depth(side: int, slot: int) -> int:
	if def.wall_mode != RoomDef.WallMode.TIDE:
		return spike_depth()
	var moving := tide_left if side == 0 else tide_right
	if not RoomRules.has_slot(moving, slot):
		return spike_depth()
	var phase := (slot * 29 + tide_salt) % TIDE_PERIOD
	return SimTrig.ping_pong(t + phase, TIDE_PERIOD, tide_max_depth())


## Adds a room coin at (x, y) now (Coin Garden's extra bounce coins).
func add_coin(x: int, y: int) -> void:
	var h: Hazard = CoinPickup.new(x, y, 0)
	h.skin = def.skin
	h.t = t
	hazards.append(h)


## A wall just got new spikes: redraw the extra wall rules for it.
func on_wall_generated(side: int, mask: int, sim: GameSim, rng: SimRng) -> void:
	match def.wall_mode:
		RoomDef.WallMode.TIDE:
			var moving := rng.next_u32() & mask
			tide_salt = rng.next_below(TIDE_PERIOD)
			if side == 0:
				tide_left = moving
			else:
				tide_right = moving
		RoomDef.WallMode.BLINK:
			var second := RoomRules.generate_wall(rng, sim.state.score, def)
			if side == 0:
				blink_left = second
			else:
				blink_right = second


func checksum(h: int) -> int:
	var out := Hazard.mix_all(
		h,
		[
			index,
			t,
			ticks,
			points,
			variant,
			tide_left,
			tide_right,
			tide_salt,
			blink_left,
			blink_right
		]
	)
	for hz in hazards:
		out = SimHash.mix(out, int(hz.alive))
		out = hz.checksum(out)
	return out
