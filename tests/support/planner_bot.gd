class_name PlannerBot
extends RefCounted
## A strong playtest player. Every tick it copies the sim and compares "tap now"
## with "wait", each followed by a few quick rollouts, and takes whichever lives
## longest. Much stronger than SimBots.gap_seeker, so if it keeps dying in a room,
## that room is likely unfair. Test/tool code only (slow: hundreds of sim steps
## per tick).

## How far ahead each rollout looks, in ticks (about 2 s: longer than one trip
## across the cage, so it sees the far wall's spikes in time).
const HORIZON := 120
const ROLLOUTS := 4

var _rng: SimRng


func _init(seed_value: int = 1) -> void:
	_rng = SimRng.new(seed_value)


## Whether to tap this tick.
func decide(sim: GameSim) -> bool:
	if not sim.state.started:
		return true
	var tap := _value(sim, true)
	var wait := _value(sim, false)
	return tap > wait


## Best result over the rollouts after taking `first` now.
func _value(sim: GameSim, first: bool) -> int:
	var best := -1
	for r in ROLLOUTS:
		var c := SimClone.copy(sim)
		c.step(first)
		var prng := SimRng.new(_rng.next_u32())
		var n := 0
		while n < HORIZON and not c.is_over():
			c.step(_policy(c, prng, r))
			n += 1
		# Living longer counts most; then rooms reached, points and coins.
		var room_gain := c.state.room_index - sim.state.room_index
		var gain := (c.state.score - sim.state.score) * 3 + room_gain * 40 + c.state.coins
		var value := n * 100 + gain
		best = maxi(best, value)
		if n >= HORIZON and r > 0:
			break
	return best


static func _policy(sim: GameSim, rng: SimRng, kind: int) -> bool:
	match kind:
		1:
			return rng.next_below(9) == 0
		2:
			return rng.next_below(16) == 0
		3:
			return false
	return aim(sim, rng)


## Like SimBots.gap_seeker, but understands flipped gravity.
static func aim(sim: GameSim, rng: SimRng) -> bool:
	var s := sim.state
	var side := 1 if s.vx > 0 else 0
	var target := SimBots._gap_center_y(sim.wall_mask(side))
	if s.exit_open and s.exit_side == side:
		target = s.exit_a_y
		if s.exit_b_kind == SimState.ExitKind.WILD:
			target = s.exit_b_y
	var jitter := (rng.next_below(9) - 4) * SimConfig.SUB
	var margin := 6 * SimConfig.SUB
	if sim.room.def.gravity_sign < 0:
		return s.y < target - margin - jitter and s.vy <= 0
	return s.y > target + margin + jitter and s.vy >= 0
