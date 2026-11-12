//! Port of sim/hazards/peg.gd.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Peg {
    pub base: Base,
    pub x: i64,
    pub base_y: i64,
    pub bob: i64,
    pub phase: i64,
    pub y: i64,
}

impl Peg {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 19 * Self::SUB;
    pub const BOB_PERIOD: i64 = 240;

    /// GDScript defaults: 0, 0, 0, 0.
    pub fn new(p_x: i64, p_y: i64, p_bob: i64, p_phase: i64) -> Peg {
        Peg { base: Base::new("peg"), x: p_x, base_y: p_y, bob: p_bob, phase: p_phase, y: p_y }
    }

    pub fn _place(&mut self) {
        if self.bob == 0 {
            self.y = self.base_y;
            return;
        }
        let a = (self.base.t + self.phase) * SimTrig::TURN / Self::BOB_PERIOD;
        self.y = self.base_y + self.bob * SimTrig::sin_t(a) / SimTrig::ONE;
    }
}

impl Hazard for Peg {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, _rng: &mut SimRng) {
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn kills(&self, sim: &GameSim) -> bool {
        sim.bird_touches_circle(self.x, self.y, Self::RADIUS)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.x, self.base_y, self.bob, self.phase, self.y])
    }
}
