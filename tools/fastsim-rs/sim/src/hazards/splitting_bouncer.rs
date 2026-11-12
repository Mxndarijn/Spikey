//! Port of sim/hazards/splitting_bouncer.gd (Sim/Hazards/SplittingBouncer.cs). A Bouncer
//! subclass: the parent is the field `b`. `other` is an owned Bouncer, not a room hazard.
use crate::rooms::hazard::{add_warning, WARN_KILL};
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct SplittingBouncer {
    pub b: Bouncer,
    pub warn: i64,
    pub other: Option<Bouncer>,
}

impl SplittingBouncer {
    pub const BIG_RADIUS: i64 = 24 * SimConfig::SUB;
    pub const BIG_SPEED_X: i64 = 154;
    pub const BIG_SPEED_Y: i64 = 2 * SimConfig::SUB;
    pub const SMALL_RADIUS: i64 = 14 * SimConfig::SUB;
    pub const SPLIT_AT: i64 = 240;
    pub const WARN: i64 = 60;
    pub const CLEAR: i64 = 120 * SimConfig::SUB;

    pub fn new() -> SplittingBouncer {
        SplittingBouncer {
            b: Bouncer::new(Self::BIG_RADIUS, crate::hazards::bouncer::Lane::ANY),
            warn: 0,
            other: None,
        }
    }

    fn _split(&mut self) {
        self.b.radius = Self::SMALL_RADIUS;
        self.b.vx = G::signi(self.b.vx) * Bouncer::SPEED_X;
        self.b.vy = -Bouncer::SPEED_Y;
        let mut other = Bouncer::new(Self::SMALL_RADIUS, crate::hazards::bouncer::Lane::ANY);
        other.x = self.b.x;
        other.y = self.b.y;
        other.vx = self.b.vx;
        other.vy = Bouncer::SPEED_Y;
        self.other = Some(other);
    }

    pub fn is_split(&self) -> bool {
        self.other.is_some()
    }
}

impl Hazard for SplittingBouncer {
    impl_base!(b.base);

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.b.setup(sim, rng);
        self.b.vx = G::signi(self.b.vx) * Self::BIG_SPEED_X;
        self.b.vy = G::signi(self.b.vy) * Self::BIG_SPEED_Y;
    }

    fn step(&mut self, sim: &mut GameSim) {
        self.b.move_(sim);
        if let Some(other) = &mut self.other {
            other.move_(sim);
            return;
        }
        let t = self.b.base.t;
        if t < Self::SPLIT_AT {
            return;
        }
        self.warn = G::mini(t - Self::SPLIT_AT, Self::WARN);
        if self.warn < Self::WARN {
            return;
        }
        if G::absi(self.b.x - sim.state.x) < Self::CLEAR {
            return;
        }
        self._split();
    }

    fn kills(&self, sim: &GameSim) -> bool {
        if self.b.kills(sim) {
            return true;
        }
        match &self.other {
            Some(other) => other.kills(sim),
            None => false,
        }
    }

    // straight_path() is `other != null`: before the split near_row and
    // adjust_wall do nothing; split, both balls fly straight.
    fn near_row(&self, sim: &GameSim, p_y: i64, half: i64, from: i64, to: i64) -> bool {
        if self.other.is_none() {
            return false;
        }
        self.b.near_row_straight(sim, p_y, half, from, to)
    }

    /// Split: a way past both balls (Bouncer.adjust_wall for each).
    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        if self.other.is_none() {
            return mask;
        }
        let mut out_ = self.b.adjust_wall_straight(sim, side, mask);
        if let Some(other) = &mut self.other {
            out_ = other.adjust_wall_straight(sim, side, out_);
        }
        out_
    }

    fn warnings(&self, _sim: &GameSim, out_: &mut Vec<i64>) {
        if self.other.is_some() || self.b.base.t < Self::SPLIT_AT {
            return;
        }
        let (x, y, r) = (self.b.x, self.b.y, self.b.radius);
        add_warning(out_, x - r, y - r, x + r, y + r, Self::WARN - self.warn, 1, WARN_KILL);
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(self.b.checksum(h), &[self.b.radius, self.warn]);
        if let Some(other) = &self.other {
            out_ = other.checksum(out_);
        }
        out_
    }
}
