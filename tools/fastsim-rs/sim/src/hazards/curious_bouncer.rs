//! Port of sim/hazards/curious_bouncer.gd (Sim/Hazards/CuriousBouncer.cs). A Bouncer
//! subclass: the parent is the field `b`.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CuriousBouncer {
    pub b: Bouncer,
    pub look: i64,
}

impl CuriousBouncer {
    pub const STEER: i64 = 4;
    pub const MAX_VY: i64 = 154;
    pub const START_VY: i64 = 38;
    pub const STEER_DIV: i64 = 512;

    pub fn new() -> CuriousBouncer {
        CuriousBouncer { b: Bouncer::default_(), look: 0 }
    }
}

impl Hazard for CuriousBouncer {
    impl_base!(b.base);

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.b.setup(sim, rng);
        self.b.vy = G::signi(self.b.vy) * Self::START_VY;
    }

    fn step(&mut self, sim: &mut GameSim) {
        let d = sim.state.y - self.b.y;
        self.look = G::signi(d);
        self.b.vy = G::clampi(
            self.b.vy + G::clampi(d / Self::STEER_DIV, -Self::STEER, Self::STEER),
            -Self::MAX_VY,
            Self::MAX_VY,
        );
        self.b.move_(sim);
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.b.kills(sim)
    }

    // straight_path() is false: near_row stays the Hazard default (false).

    fn checksum(&self, h: i64) -> i64 {
        mix_all(self.b.checksum(h), &[self.look])
    }
}
