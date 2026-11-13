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
        Self::set_speed(&mut self.b, self.level);
    }

    fn set_speed(b: &mut Bouncer, level: i64) {
        b.vx = G::signi(b.vx) * Bouncer::SPEED_X * (6 + level) / 10;
        b.vy = G::signi(b.vy) * Bouncer::SPEED_Y * (6 + level) / 10;
    }

    /// One step as step() moves the ball (step(), and adjust_wall's look ahead).
    pub fn path_step(b: &mut Bouncer, level: &mut i64, sim: &GameSim) {
        if b.move_(sim) && *level < Self::MAX_LEVEL {
            *level += 1;
            Self::set_speed(b, *level);
        }
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
        Self::path_step(&mut self.b, &mut self.level, sim);
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let mut level = self.level;
        self.b.adjust_wall_path(sim, side, mask, &mut |b: &mut Bouncer, s: &GameSim| {
            Self::path_step(b, &mut level, s);
        })
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.b.kills(sim)
    }

    // straight_path() is false: near_row stays the Hazard default (false).

    fn checksum(&self, h: i64) -> i64 {
        mix_all(self.b.checksum(h), &[self.level])
    }
}
