//! Port of Bots/PlannerBot.cs (tests/support/planner_bot.gd) and Bots/SimBots.cs.
use sim::prelude::*;

pub struct PlannerBot {
    _rng: SimRng,
    /// This bot's look-ahead and rollouts (lighter for fast checks).
    _horizon: i64,
    _rollouts: i64,
}

impl PlannerBot {
    pub const HORIZON: i64 = 120;
    pub const ROLLOUTS: i64 = 4;

    /// C# defaults: seed_value = 1, horizon = HORIZON, rollouts = ROLLOUTS.
    pub fn new(seed_value: i64, horizon: i64, rollouts: i64) -> PlannerBot {
        PlannerBot { _rng: SimRng::new(seed_value), _horizon: horizon, _rollouts: rollouts }
    }

    pub fn decide(&mut self, sim: &GameSim) -> bool {
        if !sim.state.started {
            return true;
        }
        let tap = self._value(sim, true);
        let wait = self._value(sim, false);
        tap > wait
    }

    fn _value(&mut self, sim: &GameSim, first: bool) -> i64 {
        let mut best = -1;
        for r in 0..self._rollouts {
            let mut c = sim.clone_deep();
            c.step(first);
            let mut prng = SimRng::new(self._rng.next_u32());
            let mut n = 0;
            while n < self._horizon && !c.is_over() {
                let tap = Self::_policy(&c, &mut prng, r);
                c.step(tap);
                n += 1;
            }
            let room_gain = c.state.room_index - sim.state.room_index;
            let gain = (c.state.score - sim.state.score) * 3 + room_gain * 40 + c.state.coins;
            let value = n * 100 + gain;
            best = G::maxi(best, value);
            if n >= self._horizon && r > 0 {
                break;
            }
        }
        best
    }

    fn _policy(sim: &GameSim, rng: &mut SimRng, kind: i64) -> bool {
        match kind {
            1 => return rng.next_below(9) == 0,
            2 => return rng.next_below(16) == 0,
            3 => return false,
            _ => {}
        }
        Self::aim(sim, rng)
    }

    pub fn aim(sim: &GameSim, rng: &mut SimRng) -> bool {
        let s = &sim.state;
        let side = if s.vx > 0 { 1 } else { 0 };
        let mut target = Self::gap_center_y(sim.wall_mask(side));
        if s.exit_open && s.exit_side == side {
            target = s.exit_a_y;
            if s.exit_b_kind == ExitKind::WILD {
                target = s.exit_b_y;
            }
        }
        let jitter = (rng.next_below(9) - 4) * SimConfig::SUB;
        let margin = 6 * SimConfig::SUB;
        if sim.room.gravity < 0 {
            return s.y < target - margin - jitter && s.vy <= 0;
        }
        s.y > target + margin + jitter && s.vy >= 0
    }

    pub fn gap_center_y(mask: i64) -> i64 {
        let (mut best_start, mut best_len, mut run_start, mut run_len) = (0, 0, 0, 0);
        for slot in 0..SimConfig::SLOT_COUNT {
            if RoomRules::has_slot(mask, slot) {
                run_len = 0;
            } else {
                if run_len == 0 {
                    run_start = slot;
                }
                run_len += 1;
                if run_len > best_len {
                    best_len = run_len;
                    best_start = run_start;
                }
            }
        }
        let top = SimConfig::SLOT_TOP + best_start * SimConfig::SLOT_SIZE;
        top + best_len * SimConfig::SLOT_SIZE / 2
    }
}

/// Port of Bots/SimBots.cs (tests/support/sim_bots.gd).
pub struct SimBots;

impl SimBots {
    /// Taps at random, roughly every `every` ticks on average (C# default 12).
    pub fn random_tapper(_sim: &GameSim, rng: &mut SimRng, every: i64) -> bool {
        rng.next_below(every) == 0
    }

    /// Plays one full run with gap_seeker: the sim as it ended.
    pub fn play_gap(seed_value: i64, bot_seed: i64) -> GameSim {
        let mut sim = GameSim::new(seed_value);
        let mut rng = SimRng::new(bot_seed);
        while !sim.is_over() && sim.state.tick < SimConfig::MAX_TICKS {
            let tap = Self::gap_seeker(&sim, &mut rng);
            sim.step(tap);
        }
        sim
    }

    /// Aims for the middle of the largest gap on the wall ahead.
    pub fn gap_seeker(sim: &GameSim, rng: &mut SimRng) -> bool {
        let s = &sim.state;
        if !s.started {
            return true;
        }
        let side = if s.vx > 0 { 1 } else { 0 };
        let mask = sim.wall_mask(side);
        let mut target = PlannerBot::gap_center_y(mask);
        // Head for the exit when it is on the wall ahead (Wild at a fork).
        if s.exit_open && s.exit_side == side {
            target = s.exit_a_y;
            if s.exit_b_kind == ExitKind::WILD {
                target = s.exit_b_y;
            }
        }
        let jitter = (rng.next_below(9) - 4) * SimConfig::SUB;
        let margin = 6 * SimConfig::SUB;
        s.y > target + margin + jitter && s.vy >= 0
    }
}
