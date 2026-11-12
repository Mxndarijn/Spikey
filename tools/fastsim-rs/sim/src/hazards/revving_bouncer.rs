//! Port of sim/hazards/revving_bouncer.gd (Sim/Hazards/RevvingBouncer.cs). A Bouncer
//! subclass: the parent is the field `b`.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct RevvingBouncer {
    pub b: Bouncer,
    pub level: i64,
}

impl RevvingBouncer {
    pub const MAX_LEVEL: i64 = 7;

    pub fn new() -> RevvingBouncer {
        RevvingBouncer { b: Bouncer::default_(), level: 0 }
    }

    fn _set_speed(&mut self) {
        self.b.vx = G::signi(self.b.vx) * Bouncer::SPEED_X * (6 + self.level) / 10;
        self.b.vy = G::signi(self.b.vy) * Bouncer::SPEED_Y * (6 + self.level) / 10;
    }
}

impl Hazard for RevvingBouncer {
    impl_base!(b.base);

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.b.setup(sim, rng);
        self.level = 0;
        self._set_speed();
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.b.move_(sim) && self.level < Self::MAX_LEVEL {
            self.level += 1;
            self._set_speed();
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.b.kills(sim)
    }

    // straight_path() is false: near_row stays the Hazard default (false).

    fn checksum(&self, h: i64) -> i64 {
        mix_all(self.b.checksum(h), &[self.level])
    }
}
