//! Port of sim/hazards/updraft.gd (Sim/Hazards/Updraft.cs).
use crate::rooms::hazard::{add_warning, WARN_PUSH};
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
    pub y0: i64,
    pub y1: i64,
    pub half_w: i64,
    pub lift: i64,
    pub drift_min: i64,
    pub drift_span: i64,
    pub gust: i64,
    pub phase: i64,
    pub last_low: i64,
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
    pub const GUST_UP_REACH: i64 = 160 * Self::SUB;
    pub const GUST_DOWN_REACH: i64 = 40 * Self::SUB;
    pub const GUST_TOP: i64 = 160 * Self::SUB;

    /// C# defaults: p_center = WORLD_W / 2, p_half_w = HALF_W, p_lift = LIFT.
    pub fn new(p_center: i64, p_half_w: i64, p_lift: i64) -> Updraft {
        let mut u = Updraft {
            base: Base::new("updraft"),
            x0: 0,
            x1: 0,
            y0: SimConfig::KILL_TOP,
            y1: SimConfig::KILL_BOTTOM,
            half_w: p_half_w,
            lift: p_lift,
            drift_min: 0,
            drift_span: 0,
            gust: Gust::NONE,
            phase: 0,
            last_low: -1,
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
        sim.state.x >= self.x0 && sim.state.x <= self.x1 && sim.state.y >= self.y0 && sim.state.y <= self.y1
    }

    pub fn clear_band(&mut self, sim: &GameSim, p: &VariantParams) {
        if self.lift > 0 {
            self.y0 = p.hold_bottom(sim);
        } else {
            self.y1 = p.hold_top(sim);
        }
    }

    /// True if the gust blows at some step the bird, flying straight to wall
    /// `side`, is inside the band.
    pub fn _gust_on_way(&self, sim: &GameSim, side: i64) -> bool {
        let at = sim.steps_to_wall(side);
        let dir = if side == 1 { 1 } else { -1 };
        for k in 0..at + 1 {
            let bx = sim.state.x + dir * k * SimConfig::SPEED_X;
            let (mut lo, mut hi) = (self.x0, self.x1);
            if self.drift_span > 0 {
                let c = self.drift_min
                    + SimTrig::ping_pong(self.base.t + k + self.phase, self._drift_period(), self.drift_span);
                lo = c - self.half_w;
                hi = c + self.half_w;
            }
            if bx >= lo
                && bx <= hi
                && (self.gust == Gust::NONE
                    || G::posmod(self.base.t + k + self.phase, Self::GUST_PERIOD) >= Self::GUST_OFF + Self::GUST_WARN)
            {
                return true;
            }
        }
        false
    }

    pub fn gust_step(&self) -> i64 {
        G::posmod(self.base.t + self.phase, Self::GUST_PERIOD)
    }

    pub fn _update(&mut self) {
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

    /// Gusts: keeps the wall the bird flies to within reach of a bird the gust
    /// lifts on the way (GUST_DOWN_REACH). No RNG draws.
    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let mut out = mask;
        if self.lift > 0 && self._gust_on_way(sim, side) {
            let low = if self.last_low >= 0 { self.last_low } else { sim.state.anchor_y };
            let mut ok = 0;
            for slot in 0..SimConfig::SLOT_COUNT {
                let y = SimConfig::slot_center_y(slot);
                if y >= G::maxi(Self::GUST_TOP, low - Self::GUST_UP_REACH) && y <= low + Self::GUST_DOWN_REACH {
                    ok |= 1i64 << slot;
                }
            }
            let all = (1i64 << SimConfig::SLOT_COUNT) - 1;
            let need = G::mini(sim.room.def().gap, RoomRules::longest_gap(all & !ok));
            out = RoomRules::keep_run(mask, need, ok);
        }
        let run = RoomRules::longest_gap_mask(out);
        for slot in 0..SimConfig::SLOT_COUNT {
            if (run >> slot) & 1 == 1 {
                self.last_low = SimConfig::slot_center_y(slot);
            }
        }
        out
    }

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

    fn warnings(&self, _sim: &GameSim, out_: &mut Vec<i64>) {
        if self.gust != Gust::WARN {
            return;
        }
        let eta = Self::GUST_OFF + Self::GUST_WARN - self.gust_step();
        add_warning(out_, self.x0, self.y0, self.x1, self.y1, eta, Self::GUST_ON, WARN_PUSH);
    }

    fn checksum(&self, h: i64) -> i64 {
        let out_ = mix_all(h, &[self.x0, self.x1, self.lift, self.drift_min, self.drift_span, self.gust, self.phase, self.last_low]);
        if self.y0 != SimConfig::KILL_TOP || self.y1 != SimConfig::KILL_BOTTOM {
            return mix_all(out_, &[self.y0, self.y1]);
        }
        out_
    }
}
