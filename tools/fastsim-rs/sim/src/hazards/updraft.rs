//! Port of sim/hazards/updraft.gd (Sim/Hazards/Updraft.cs).
use crate::prelude::*;

pub struct Gust;
impl Gust {
    pub const NONE: i64 = 0;
    pub const OFF: i64 = 1;
    pub const WARN: i64 = 2;
    pub const ON: i64 = 3;
}

#[derive(Clone, Debug)]
pub struct Updraft {
    pub base: Base,
    pub x0: i64,
    pub x1: i64,
    pub half_w: i64,
    pub lift: i64,
    pub drift_min: i64,
    pub drift_span: i64,
    pub gust: i64,
    pub phase: i64,
}

impl Updraft {
    pub const SUB: i64 = SimConfig::SUB;
    pub const HALF_W: i64 = 60 * Self::SUB;
    pub const LIFT: i64 = SimConfig::GRAVITY * 2 / 3;
    pub const HOVER: i64 = SimConfig::GRAVITY;
    pub const CHIMNEY: i64 = SimConfig::GRAVITY * 3 / 2;
    pub const STRONG: i64 = SimConfig::GRAVITY * 2;
    pub const GUST_OFF: i64 = 60;
    pub const GUST_WARN: i64 = SimConfig::ARRIVAL_BLIND;
    pub const GUST_ON: i64 = 90;
    pub const GUST_PERIOD: i64 = Self::GUST_OFF + Self::GUST_WARN + Self::GUST_ON;

    /// C# defaults: p_center = WORLD_W / 2, p_half_w = HALF_W, p_lift = LIFT.
    pub fn new(p_center: i64, p_half_w: i64, p_lift: i64) -> Updraft {
        let mut u = Updraft {
            base: Base::new("updraft"),
            x0: 0,
            x1: 0,
            half_w: p_half_w,
            lift: p_lift,
            drift_min: 0,
            drift_span: 0,
            gust: Gust::NONE,
            phase: 0,
        };
        u._place(p_center);
        u
    }

    pub fn drifting(mut self, p_min: i64, p_span: i64) -> Updraft {
        self.drift_min = p_min;
        self.drift_span = p_span;
        self._place(p_min);
        self
    }

    pub fn gusty(mut self) -> Updraft {
        self.gust = Gust::OFF;
        self
    }

    pub fn blowing(&self) -> bool {
        self.gust == Gust::NONE || self.gust == Gust::ON
    }

    pub fn inside(&self, sim: &GameSim) -> bool {
        sim.state.x >= self.x0 && sim.state.x <= self.x1
    }

    pub fn gust_step(&self) -> i64 {
        G::posmod(self.base.t + self.phase, Self::GUST_PERIOD)
    }

    fn _update(&mut self) {
        if self.drift_span > 0 {
            let center =
                self.drift_min + SimTrig::ping_pong(self.base.t + self.phase, self._drift_period(), self.drift_span);
            self._place(center);
        }
        if self.gust != Gust::NONE {
            let m = self.gust_step();
            if m < Self::GUST_OFF {
                self.gust = Gust::OFF;
            } else if m < Self::GUST_OFF + Self::GUST_WARN {
                self.gust = Gust::WARN;
            } else {
                self.gust = Gust::ON;
            }
        }
    }

    fn _drift_period(&self) -> i64 {
        2 * self.drift_span / Self::SUB
    }

    fn _place(&mut self, center: i64) {
        self.x0 = center - self.half_w;
        self.x1 = center + self.half_w;
    }
}

impl Hazard for Updraft {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        if self.drift_span > 0 {
            self.phase = rng.next_below(self._drift_period());
        } else if self.gust != Gust::NONE {
            self.phase = rng.next_below(Self::GUST_OFF);
        }
        self._update();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._update();
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if self.blowing() && self.inside(sim) {
            let vy = sim.state.vy - self.lift;
            sim.state.vy = G::clampi(vy, -SimConfig::MAX_FALL_VY, SimConfig::MAX_FALL_VY);
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.x0, self.x1, self.lift, self.drift_min, self.drift_span, self.gust, self.phase])
    }
}
