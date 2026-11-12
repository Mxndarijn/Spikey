//! Port of sim/hazards/cave_drip.gd.
use crate::prelude::*;
use crate::rooms::hazard::{add_warning, WARN_KILL};

#[derive(Clone, Debug)]
pub struct CaveDrip {
    pub base: Base,
    pub x: i64,
    pub tip_y: i64,
    pub floor_y: i64,
    pub first: i64,
    pub every: i64,
    pub falling: bool,
    pub y: i64,
    pub eta: i64,
}

impl CaveDrip {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 7 * Self::SUB;
    pub const GLINT: i64 = 60;
    pub const SPEED: i64 = 4 * Self::SUB;

    /// GDScript defaults: 0, 0, 0, 0, 1.
    pub fn new(p_x: i64, p_tip_y: i64, p_floor_y: i64, p_first: i64, p_every: i64) -> CaveDrip {
        CaveDrip {
            base: Base::new("cave_drip"),
            x: p_x,
            tip_y: p_tip_y,
            floor_y: p_floor_y,
            first: p_first,
            every: p_every,
            falling: false,
            y: p_tip_y,
            eta: -1,
        }
    }

    pub fn fall_steps(&self) -> i64 {
        (self.floor_y - self.tip_y) / Self::SPEED + 1
    }

    pub fn _place(&mut self) {
        self.falling = false;
        self.y = self.tip_y;
        self.eta = -1;
        let k = self.base.t - self.first;
        if k < 0 {
            if k >= -Self::GLINT {
                self.eta = -k;
            }
            return;
        }
        let c = k % self.every;
        if c < self.fall_steps() {
            self.falling = true;
            self.y = self.tip_y + c * Self::SPEED;
        } else if c >= self.every - Self::GLINT {
            self.eta = self.every - c;
        }
    }
}

impl Hazard for CaveDrip {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, _rng: &mut SimRng) {
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.falling && sim.bird_touches_circle(self.x, self.y, Self::RADIUS)
    }

    fn warnings(&self, _sim: &GameSim, out_: &mut Vec<i64>) {
        if self.eta < 0 {
            return;
        }
        add_warning(
            out_,
            self.x - Self::RADIUS,
            self.tip_y,
            self.x + Self::RADIUS,
            self.floor_y,
            self.eta,
            self.fall_steps(),
            WARN_KILL,
        );
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(
            h,
            &[self.x, self.tip_y, self.floor_y, self.first, self.every, G::b(self.falling), self.y, self.eta],
        )
    }
}
