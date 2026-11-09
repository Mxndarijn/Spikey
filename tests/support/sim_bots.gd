class_name SimBots
extends RefCounted
## Scripted players for tests and golden-replay generation.
## Bots read sim state but only ever act through taps, like a real player.


## Taps at random, roughly every `every` ticks on average.
static func random_tapper(_sim: GameSim, rng: SimRng, every: int = 12) -> bool:
	return rng.next_below(every) == 0


## Aims for the middle of the largest gap on the wall ahead.
static func gap_seeker(sim: GameSim, rng: SimRng) -> bool:
	var s := sim.state
	if not s.started:
		return true
	var side := 1 if s.vx > 0 else 0
	var mask := sim.wall_mask(side)
	var target := _gap_center_y(mask)
	# Head for the exit when it is on the wall ahead (Wild at a fork).
	if s.exit_open and s.exit_side == side:
		target = s.exit_a_y
		if s.exit_b_kind == SimState.ExitKind.WILD:
			target = s.exit_b_y
	var jitter := (rng.next_below(9) - 4) * SimConfig.SUB
	var margin := 6 * SimConfig.SUB
	return s.y > target + margin + jitter and s.vy >= 0


static func _gap_center_y(mask: int) -> int:
	var best_start := 0
	var best_len := 0
	var run_start := 0
	var run_len := 0
	for slot in SimConfig.SLOT_COUNT:
		if RoomRules.has_slot(mask, slot):
			run_len = 0
		else:
			if run_len == 0:
				run_start = slot
			run_len += 1
			if run_len > best_len:
				best_len = run_len
				best_start = run_start
	var top := SimConfig.SLOT_TOP + best_start * SimConfig.SLOT_SIZE
	return top + best_len * SimConfig.SLOT_SIZE / 2


## Plays one full run with the given bot; returns the recorded replay.
## With stop_after_tick >= 0 the bot stops tapping then, so the run ends soon after.
static func play(
	seed_value: int, bot: Callable, bot_seed: int = 1, stop_after_tick: int = -1
) -> Replay:
	var sim := GameSim.new(seed_value)
	var rng := SimRng.new(bot_seed)
	var taps := PackedInt32Array()
	while not sim.is_over() and sim.state.tick < SimConfig.MAX_TICKS:
		var active := stop_after_tick < 0 or sim.state.tick < stop_after_tick
		var tap: bool = active and bot.call(sim, rng)
		if tap:
			taps.append(sim.state.tick)
		sim.step(tap)
	return Replay.from_sim(sim, taps)


## Like play(), but the bot stops tapping after `first_ticks`, the run is
## revived when it dies, and the bot plays `more_ticks` more before it stops
## for good.
static func play_revived(
	seed_value: int, bot: Callable, bot_seed: int, first_ticks: int, more_ticks: int
) -> Replay:
	var sim := GameSim.new(seed_value)
	var rng := SimRng.new(bot_seed)
	var taps := PackedInt32Array()
	var revives := PackedInt32Array()
	var stop := first_ticks
	while sim.state.tick < SimConfig.MAX_TICKS:
		if sim.is_over():
			if not sim.can_revive():
				break
			revives.append(sim.state.tick)
			sim.revive()
			stop = sim.state.tick + more_ticks
		var tap: bool = sim.state.tick < stop and bot.call(sim, rng)
		if tap:
			taps.append(sim.state.tick)
		sim.step(tap)
	return Replay.from_sim(sim, taps, revives)
