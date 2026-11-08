class_name RoomRuntime
extends RefCounted
## The room being played: its RoomDef, its live hazards, and the wall rules that
## change over time (tide spikes, blinking walls, squeezing walls, speed).

const TIDE_PERIOD := 120
## Tide spikes slide from flat to this far out: 1.5 times a normal spike.
const TIDE_MAX_DEPTH := SimConfig.SPIKE_DEPTH * 3 / 2
const BLINK_PERIOD := 60
## Squeeze Box: each point in the room moves both walls in by this much.
const SQUEEZE_STEP := 6 * SimConfig.SUB
const SQUEEZE_MAX_POINTS := 10

var def: RoomDef
## Index of `def` in RoomCatalog.all() (part of the checksum).
var index := 0
## Sim steps since the room started (speed changes how many per tick).
var t := 0
## Real ticks since the room started.
var ticks := 0
## Points scored in this room.
var points := 0
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
	tide_left = 0
	tide_right = 0
	tide_salt = 0
	blink_left = 0
	blink_right = 0
	hazards.clear()
	var list: Array[Callable] = def.hazards.duplicate()
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
	match def.speed:
		RoomDef.Speed.FAST:
			return 2 if ticks % 4 == 0 else 1
		RoomDef.Speed.SLOW:
			return 1 if ticks % 2 == 0 else 0
	return 1


func step(sim: GameSim) -> void:
	t += 1
	for h in hazards:
		if h.alive:
			h.t = t
			h.step(sim)


func inset() -> int:
	if not def.squeeze:
		return 0
	return mini(points, SQUEEZE_MAX_POINTS) * SQUEEZE_STEP


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
		return SimConfig.SPIKE_DEPTH
	var moving := tide_left if side == 0 else tide_right
	if not RoomRules.has_slot(moving, slot):
		return SimConfig.SPIKE_DEPTH
	var phase := (slot * 29 + tide_salt) % TIDE_PERIOD
	return SimTrig.ping_pong(t + phase, TIDE_PERIOD, TIDE_MAX_DEPTH)


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
		h, [index, t, ticks, points, tide_left, tide_right, tide_salt, blink_left, blink_right]
	)
	for hz in hazards:
		out = SimHash.mix(out, int(hz.alive))
		out = hz.checksum(out)
	return out
