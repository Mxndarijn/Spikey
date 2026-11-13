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
## Left press: the one moving wall steps in this much per point.
const SQUEEZE_LEFT_STEP := 9 * SimConfig.SUB
## Breathing box: both walls slide this far in and back out, once per period
## (steps). At most about 0.33 px a step, far slower than the bird.
const BREATHE_IN := 60 * SimConfig.SUB
const BREATHE_PERIOD := 360
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
## Which way gravity pulls right now: the room's gravity_sign, turned round on
## every wall bounce in Flip-flop.
var gravity := 1
## The room's own RNG seed, drawn from the run's spine (GameSim._spine) when
## the room is entered. Every wall after the first draws from an RNG seeded
## from it and the wall's number (GameSim._new_wall), so what a player does
## in the room never changes what comes later.
var rng_seed := 0
## Walls generated in this room so far (the arrival's wall is 0).
var walls := 0
## The run's score when the room was entered (a boss room's tier and exit).
var entry_score := 0


func start(p_def: RoomDef, p_index: int, sim: GameSim, rng: SimRng) -> void:
	def = p_def
	index = p_index
	entry_score = sim.state.score
	t = 0
	ticks = 0
	points = 0
	variant = 0
	tide_left = 0
	tide_right = 0
	tide_salt = 0
	blink_left = 0
	blink_right = 0
	gravity = def.gravity_sign
	walls = 0
	hazards.clear()
	var list: Array[Callable] = def.hazards.duplicate()
	# The variant is drawn first, then the combo: this order is part of the rules.
	# Out of a portal only variants that fit the arrival height are drawn
	# (RoomVariant.arrival_skip); none fitting = any. The height is the exit's
	# (SimState.anchor_y), never the bird's, so every player gets the same.
	var drawn: Array[int] = []
	if sim.state.started:
		drawn = def.arrival_variants(sim.state.anchor_y)
	if drawn.is_empty():
		for i in def.variants.size():
			drawn.append(i)
	if drawn.size() > 1:
		variant = drawn[rng.next_below(drawn.size())]
		# A GENERATED variant drawn by the room seed's first draw stays: the
		# arrival retries (GameSim._arrival_retries, which skip draws before
		# the room starts) lay it out again rather than draw another variant.
		# The first try is the same draw, so nothing changes there, nor in a
		# room whose first draw is a static variant.
		if sim.state.started and not sim._arrival_unpin:
			var first: int = drawn[SimRng.new(rng_seed).next_below(drawn.size())]
			if def.variants[first].kind == RoomVariant.Kind.GENERATED:
				variant = first
	elif drawn.size() == 1:
		variant = drawn[0]
	if sim.forced_variant != "":
		variant = _variant_index(sim.forced_variant, variant)
	var gen := (
		not def.variants.is_empty() and def.variants[variant].kind == RoomVariant.Kind.GENERATED
	)
	if not def.variants.is_empty():
		for f: Callable in def.variants[variant].hazards:
			list.append(f)
	# A generated variant is built after the room's own hazards and before the
	# combo's (the same order a static one is set up in).
	var after: Array[Callable] = []
	if not def.combos.is_empty():
		var combo: Array = def.combos[rng.next_below(def.combos.size())]
		for f: Callable in combo:
			if gen:
				after.append(f)
			else:
				list.append(f)
	for f in list:
		var h: Hazard = f.call()
		hazards.append(h)
		h.setup(sim, rng)
	if gen:
		_generate(sim, rng, def.variants[variant])
	for f in after:
		var h: Hazard = f.call()
		hazards.append(h)
		h.setup(sim, rng)


## Builds a GENERATED variant (RoomVariant.recipe): generate, check
## (VariantCheck), and on a fail throw that layout away and build again from
## the next draws, up to GENERATE_TRIES times; the last try is the recipe's
## safe fallback, kept unchecked.
func _generate(sim: GameSim, rng: SimRng, v: RoomVariant) -> void:
	var base := hazards.size()
	var p := VariantParams.make(sim, rng)
	for k in RoomVariant.GENERATE_TRIES:
		p.attempt = k
		p.fallback = k == RoomVariant.GENERATE_TRIES - 1
		v.recipe.call(p)
		if p.fallback or VariantCheck.holds(sim, v.avoid_touch, v.hold_steps):
			return
		hazards.resize(base)


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


## How far wall `side` (0 = left) stands in from the cage's edge right now.
## Narrow slides both in over the room's first steps (the bird leaves its wall
## twice as fast, so a wall never catches it); Squeeze Box steps them in per
## point (Left press: only the left one), or slides them in and out (Breathing).
func inset(side: int = 0) -> int:
	var out := mini(t * INSET_SPEED, def.inset)
	if def.squeeze:
		var squeezed := mini(points, SQUEEZE_MAX_POINTS)
		var mode := RoomVariant.Squeeze.POINTS
		if not def.variants.is_empty():
			mode = _variant().squeeze
		match mode:
			RoomVariant.Squeeze.LEFT:
				if side == 0:
					out += squeezed * SQUEEZE_LEFT_STEP
			RoomVariant.Squeeze.BREATHE:
				out += SimTrig.ping_pong(t, BREATHE_PERIOD, BREATHE_IN)
			_:
				out += squeezed * SQUEEZE_STEP
	return out


func _variant() -> RoomVariant:
	return def.variants[variant]


## The bird just bounced off a side wall (not a portal).
func on_wall_bounce() -> void:
	if not def.variants.is_empty() and _variant().flip_flop:
		gravity = -gravity


## Index of the variant with id `id`, or `fallback` when this room has none.
func _variant_index(id: String, fallback: int) -> int:
	for i in def.variants.size():
		if def.variants[i].id == id:
			return i
	return fallback


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


## Tide spikes slide from flat to this far out: 1.5 times a still spike (the
## variant can reach further: Tide big 2.25 times).
func tide_max_depth() -> int:
	if def.variants.is_empty():
		return spike_depth() * 3 / 2
	var v := _variant()
	return spike_depth() * v.tide_num / v.tide_den


## The furthest any wall spike can reach in this room.
func max_spike_depth() -> int:
	return tide_max_depth() if def.wall_mode == RoomDef.WallMode.TIDE else spike_depth()


## The variant's extra (or fewer) spikes on wall `side` (Lopsided leans them
## onto the left wall).
func spike_bonus(side: int = 0) -> int:
	var boss := SimConfig.boss_tier(entry_score) - 1 if def.boss else 0
	if def.variants.is_empty():
		return boss
	var v := _variant()
	return boss + v.extra_spikes + (v.lean if side == 0 else -v.lean)


func wall_left() -> int:
	return inset(0)


func wall_right() -> int:
	return SimConfig.WORLD_W - inset(1)


## Steps between Blink Walls swaps.
func _blink_period() -> int:
	if not def.variants.is_empty() and _variant().blink_period > 0:
		return _variant().blink_period
	return BLINK_PERIOD


func blink_showing_second() -> bool:
	return def.wall_mode == RoomDef.WallMode.BLINK and (t / _blink_period()) % 2 == 1


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
			# A fast blink leaves no time to wait for a pattern: the first
			# pattern's free run stays free in the second too.
			if _blink_period() != BLINK_PERIOD:
				second &= ~RoomRules.longest_gap_mask(mask)
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
			blink_right,
			gravity,
			rng_seed,
			walls,
			entry_score
		]
	)
	for hz in hazards:
		out = SimHash.mix(out, int(hz.alive))
		out = hz.checksum(out)
	return out
