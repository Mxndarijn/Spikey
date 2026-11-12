//! Port of sim/hazards/boss.gd (Sim/Hazards/Boss.cs), the base of the boss
//! hazards. Not in `Hz` itself: each boss holds a `Boss` as the field `boss`.
//!
//! C# virtual methods (safe_y, boss_setup, on_phase, boss_step,
//! boss_down_step, boss_kills) are the trait `BossKind`; the base methods that
//! call them (setup, step, kills, adjust_wall, _safe_span) are generic
//! associated functions, `Boss::step(self, sim)`, so the subclass's override
//! runs exactly as in C#.
use crate::prelude::*;

/// The C# virtual methods of `Boss`, overridden by each boss.
#[allow(unused_variables)]
pub trait BossKind {
    fn boss(&self) -> &Boss;
    fn boss_mut(&mut self) -> &mut Boss;
    fn safe_y(&self, y: i64, steps: i64) -> bool {
        true
    }
    fn boss_setup(&mut self, sim: &mut GameSim) {}
    fn on_phase(&mut self) {}
    fn boss_step(&mut self, sim: &mut GameSim) {}
    fn boss_down_step(&mut self, sim: &mut GameSim) {}
    fn boss_kills(&self, sim: &GameSim) -> bool {
        false
    }
}

#[derive(Clone, Debug)]
pub struct Boss {
    pub base: Base,
    pub tier: i64,
    pub phase: i64,
    pub phase_start: i64,
    pub down_at: i64,
    pub seed: i64,
}

impl Boss {
    pub const PHASE_AT: [i64; 2] = [7, 14];
    pub const STAGGER: i64 = 70;
    pub const FIRST_DELAY: i64 = SimConfig::ARRIVAL_BLIND + SimConfig::ARRIVAL_FOLLOW / 2;
    pub const WALL_FROM: i64 = -6;
    pub const WALL_TO: i64 = 30;
    pub const WALL_STEP: i64 = 6;
    pub const MARGIN: i64 = 4 * SimConfig::SUB;

    pub fn new(kind: &'static str) -> Boss {
        Boss { base: Base::new(kind), tier: 1, phase: 1, phase_start: Self::FIRST_DELAY, down_at: -1, seed: 0 }
    }

    pub fn setup<K: BossKind>(k: &mut K, sim: &mut GameSim, rng: &mut SimRng) {
        let b = k.boss_mut();
        b.tier = SimConfig::boss_tier(sim.room.entry_score);
        b.seed = rng.next_u32();
        k.boss_setup(sim);
    }

    pub fn step<K: BossKind>(k: &mut K, sim: &mut GameSim) {
        let b = k.boss_mut();
        if b.down_at < 0 && (sim.state.exit_open || sim.state.exit_preview) {
            b.down_at = b.base.t;
        }
        if b.down_at >= 0 {
            k.boss_down_step(sim);
            return;
        }
        let p = Self::phase_of(sim.room.points);
        let b = k.boss_mut();
        if p != b.phase {
            b.phase = p;
            b.phase_start = b.base.t + Self::STAGGER;
            k.on_phase();
        }
        k.boss_step(sim);
    }

    pub fn kills<K: BossKind>(k: &K, sim: &GameSim) -> bool {
        if k.boss().down_at >= 0 {
            return false;
        }
        k.boss_kills(sim)
    }

    pub fn phase_of(points: i64) -> i64 {
        if points >= Self::PHASE_AT[1] {
            return 3;
        }
        if points >= Self::PHASE_AT[0] {
            return 2;
        }
        1
    }

    pub fn clock(&self) -> i64 {
        self.base.t - self.phase_start
    }

    pub fn clock_in(&self, steps: i64) -> i64 {
        self.base.t + steps - self.phase_start
    }

    pub fn draw(&self, k: i64, salt: i64) -> i64 {
        SimHash::mix(SimHash::mix(SimHash::mix(SimHash::SEED, self.seed), k), salt)
    }

    pub fn x_after(sim: &GameSim, steps: i64) -> i64 {
        let r = SimConfig::BIRD_RADIUS;
        let lo = sim.room.wall_left() + r;
        let hi = sim.room.wall_right() - r;
        let span = hi - lo;
        if span <= 0 {
            return sim.state.x;
        }
        let mut pos = if sim.state.vx > 0 { sim.state.x - lo } else { 2 * span - (sim.state.x - lo) };
        pos = G::posmod(pos + steps * G::absi(sim.state.vx), 2 * span);
        lo + (if pos <= span { pos } else { 2 * span - pos })
    }

    pub fn adjust_wall<K: BossKind>(k: &mut K, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        if k.boss().down_at >= 0 {
            return mask;
        }
        let at = sim.steps_to_wall(side);
        let mut blocked = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if !Self::_safe_span(k, SimConfig::slot_center_y(slot), at) {
                blocked |= 1i64 << slot;
            }
        }
        let safe = ((1i64 << SimConfig::SLOT_COUNT) - 1) & !blocked;
        let need = G::mini(sim.room.def().gap, RoomRules::longest_gap(blocked));
        RoomRules::keep_run(mask, need, safe)
    }

    pub fn _safe_span<K: BossKind>(k: &K, y: i64, at: i64) -> bool {
        let mut d = Self::WALL_FROM;
        while d < Self::WALL_TO + 1 {
            if !k.safe_y(y, at + d) {
                return false;
            }
            d += Self::WALL_STEP;
        }
        true
    }

    pub fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.tier, self.phase, self.phase_start, self.down_at, self.seed])
    }
}
