//! Port of sim/hazards/wind.gd (Sim/Hazards/Wind.cs).
use crate::prelude::*;

pub struct Mode;
impl Mode {
    pub const STEADY: i64 = 0;
    pub const SPLIT: i64 = 1;
    pub const GUSTY: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Wind {
    pub base: Base,
    pub mode: i64,
    pub a_y0: i64,
    pub a_y1: i64,
    pub a_dir: i64,
    pub b_y0: i64,
    pub b_y1: i64,
    pub b_dir: i64,
}

impl Wind {
    pub const SUB: i64 = SimConfig::SUB;
    pub const PUSH: i64 = SimConfig::SPEED_X / 4;
    pub const GUST_PERIOD: i64 = 320;
    pub const GUST_CALM: i64 = 110;
    pub const GUST_WARN: i64 = 60;

    /// C# default: p_mode = -1.
    pub fn new(p_mode: i64) -> Wind {
        Wind {
            base: Base::new("wind"),
            mode: p_mode,
            a_y0: 250 * Self::SUB,
            a_y1: 370 * Self::SUB,
            a_dir: 1,
            b_y0: 0,
            b_y1: 0,
            b_dir: 0,
        }
    }

    pub fn blowing(&self) -> bool {
        if self.mode != Mode::GUSTY {
            return true;
        }
        G::posmod(self.base.t, Self::GUST_PERIOD) >= Self::GUST_CALM + Self::GUST_WARN
    }

    pub fn warning(&self) -> bool {
        if self.mode != Mode::GUSTY {
            return false;
        }
        let p = G::posmod(self.base.t, Self::GUST_PERIOD);
        p >= Self::GUST_CALM && p < Self::GUST_CALM + Self::GUST_WARN
    }
}

impl Hazard for Wind {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        if self.mode < 0 {
            self.mode = match sim.room.variant_id() {
                "split" => Mode::SPLIT,
                "gusty" => Mode::GUSTY,
                _ => Mode::STEADY,
            };
        }
        self.a_dir = if rng.next_below(2) == 0 { 1 } else { -1 };
        if self.mode == Mode::SPLIT {
            self.a_y0 = 180 * Self::SUB;
            self.a_y1 = 280 * Self::SUB;
            self.b_y0 = 400 * Self::SUB;
            self.b_y1 = 500 * Self::SUB;
            self.b_dir = -self.a_dir;
        }
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if !self.blowing() {
            return;
        }
        let y = sim.state.y;
        if y >= self.a_y0 && y <= self.a_y1 {
            sim.state.x += self.a_dir * Self::PUSH;
        } else if self.b_dir != 0 && y >= self.b_y0 && y <= self.b_y1 {
            sim.state.x += self.b_dir * Self::PUSH;
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.mode, self.a_y0, self.a_y1, self.a_dir, self.b_y0, self.b_y1, self.b_dir])
    }
}
