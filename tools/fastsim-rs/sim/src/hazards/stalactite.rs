//! Port of sim/hazards/stalactite.gd.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Stalactite {
    pub base: Base,
    pub x: i64,
    pub gap_y: i64,
    pub target_y: i64,
    pub follows: bool,
    pub top: bool,
    pub bottom: bool,
    pub gap: i64,
    pub half_w: i64,
    pub fixed_lo: i64,
    pub fixed_hi: i64,
    pub scheduled: bool,
    pub schedule: Vec<i64>,
    pub slides: i64,
}

impl Stalactite {
    pub const GAP: i64 = 150 * SimConfig::SUB;
    pub const HALF_W: i64 = 22 * SimConfig::SUB;
    pub const GAP_MIN: i64 = 150 * SimConfig::SUB;
    pub const GAP_MAX: i64 = 490 * SimConfig::SUB;
    pub const MAX_STEP: i64 = 60 * SimConfig::SUB;
    pub const SCHED_REACH: i64 = 100 * SimConfig::SUB;
    pub const WALL_CLEAR: i64 = 70 * SimConfig::SUB;
    pub const SLIDE: i64 = 3 * SimConfig::SUB;
    pub const HOP_MID: i64 = 30 * SimConfig::SUB;
    pub const EXIT_NEAR: i64 = 120 * SimConfig::SUB;
    pub const FIXED_REACH: i64 = 120 * SimConfig::SUB;

    /// GDScript defaults: p_x = 0, p_follows = false.
    pub fn new(p_x: i64, p_follows: bool) -> Stalactite {
        Stalactite {
            base: Base::new("stalactite"),
            x: p_x,
            gap_y: 0,
            target_y: 0,
            follows: p_follows,
            top: true,
            bottom: true,
            gap: Self::GAP,
            half_w: Self::HALF_W,
            fixed_lo: -1,
            fixed_hi: -1,
            scheduled: false,
            schedule: Vec::new(),
            slides: 0,
        }
    }

    pub fn _draw_schedule(&mut self, sim: &GameSim, rng: &mut SimRng) {
        self.schedule = Vec::new();
        self.slides = 0;
        let to_ghost = G::maxi(sim.next_exit_score() - 1 - sim.state.score, 0);
        let park = G::maxi((to_ghost + 1) / 2 - 1, 0);
        let mut y = self.gap_y;
        let lo = G::maxi(Self::GAP_MIN, self.gap_y - Self::SCHED_REACH);
        let hi = G::mini(Self::GAP_MAX, self.gap_y + Self::SCHED_REACH);
        for _i in 0..park + 1 {
            y = Self::_within(rng, y, Self::MAX_STEP, lo, hi);
            self.schedule.push(y);
        }
    }

    /// GDScript `_clear_wall_ahead(sim, column)` reads only `column.target_y`.
    pub fn _clear_wall_ahead(sim: &mut GameSim, column_target_y: i64) {
        let s = &mut sim.state;
        let mut mask = if s.vx > 0 { s.right_spikes } else { s.left_spikes };
        for slot in 0..SimConfig::SLOT_COUNT {
            if G::absi(SimConfig::slot_center_y(slot) - column_target_y) < Self::WALL_CLEAR {
                mask &= !(1i64 << slot);
            }
        }
        if s.vx > 0 {
            s.right_spikes = mask;
        } else {
            s.left_spikes = mask;
        }
    }

    pub fn _within(rng: &mut SimRng, center: i64, spread: i64, lo: i64, hi: i64) -> i64 {
        let a = G::maxi(lo, center - spread);
        let b = G::mini(hi, center + spread);
        if a > b {
            return G::clampi(center, lo, hi);
        }
        a + rng.next_below(b - a + 1)
    }

    pub fn _near_wall(&self) -> i64 {
        if self.x > SimConfig::WORLD_W / 2 {
            1
        } else {
            0
        }
    }

    pub fn top_tip(&self) -> i64 {
        self.gap_y - self.gap / 2
    }

    pub fn bottom_tip(&self) -> i64 {
        self.gap_y + self.gap / 2
    }
}

impl Hazard for Stalactite {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.fixed_lo >= 0 {
            self.gap_y = G::clampi(FairLanes::entry_y(sim) - Self::HOP_MID, self.fixed_lo, self.fixed_hi);
            self.target_y = self.gap_y;
            return;
        }
        self.gap_y = G::clampi(FairLanes::entry_y(sim) - Self::HOP_MID, Self::GAP_MIN, Self::GAP_MAX);
        self.target_y = self.gap_y;
        if self.scheduled {
            self._draw_schedule(sim, rng);
        }
    }

    fn on_bounce(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        if self.follows {
            return;
        }
        if self.fixed_lo >= 0 {
            Self::_clear_wall_ahead(sim, self.target_y);
            return;
        }
        if !self.scheduled || (sim.state.vx > 0) != (self._near_wall() == 1) {
            return;
        }
        self.target_y = self.schedule[G::mini(self.slides, self.schedule.len() as i64 - 1) as usize];
        self.slides += 1;
        Self::_clear_wall_ahead(sim, self.target_y);
    }

    fn blocks_exit(&self, _sim: &GameSim, side: i64, y: i64) -> bool {
        let r = SimConfig::BIRD_RADIUS;
        if self.scheduled {
            if side != self._near_wall() || self.schedule.is_empty() {
                return false;
            }
            let lane = self.schedule[self.schedule.len() - 1];
            return G::absi(y - lane) > self.gap / 2 - r;
        }
        if self.fixed_lo < 0 {
            return false;
        }
        let wall = if side == 0 { 0 } else { SimConfig::WORLD_W };
        if G::absi(self.x - wall) > Self::EXIT_NEAR {
            return (self.top && y < self.top_tip() - Self::FIXED_REACH)
                || (self.bottom && y > self.bottom_tip() + Self::FIXED_REACH);
        }
        if self.top && y < self.gap_y - self.gap / 2 + r {
            return true;
        }
        self.bottom && y > self.gap_y + self.gap / 2 - r
    }

    fn step(&mut self, _sim: &mut GameSim) {
        if self.gap_y < self.target_y {
            self.gap_y = G::mini(self.gap_y + Self::SLIDE, self.target_y);
        } else if self.gap_y > self.target_y {
            self.gap_y = G::maxi(self.gap_y - Self::SLIDE, self.target_y);
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        (self.top && sim.bird_touches_rect(self.x - self.half_w, 0, self.x + self.half_w, self.top_tip()))
            || (self.bottom
                && sim.bird_touches_rect(self.x - self.half_w, self.bottom_tip(), self.x + self.half_w, SimConfig::WORLD_H))
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(
            h,
            &[
                self.x,
                self.gap_y,
                self.target_y,
                G::b(self.follows),
                G::b(self.top),
                G::b(self.bottom),
                self.gap,
                self.half_w,
                self.fixed_lo,
            ],
        );
        if self.scheduled {
            let mut xs = vec![self.slides];
            xs.extend_from_slice(&self.schedule);
            out_ = mix_all(out_, &xs);
        }
        out_
    }
}
