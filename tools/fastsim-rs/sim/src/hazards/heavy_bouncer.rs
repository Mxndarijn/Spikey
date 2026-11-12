//! Port of sim/hazards/heavy_bouncer.gd (Sim/Hazards/HeavyBouncer.cs). A Bouncer subclass:
//! the parent is the field `b`.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct HeavyBouncer {
    pub b: Bouncer,
    pub bounces: i64,
}

impl HeavyBouncer {
    pub const HEAVY_RADIUS: i64 = 22 * SimConfig::SUB;
    pub const HEAVY_SPEED_X: i64 = 160;
    pub const GRAVITY: i64 = 8;
    pub const LAUNCH: [i64; 2] = [479, 594];

    pub fn new() -> HeavyBouncer {
        HeavyBouncer { b: Bouncer::new(Self::HEAVY_RADIUS, crate::hazards::bouncer::Lane::ANY), bounces: 0 }
    }
}

impl Hazard for HeavyBouncer {
    impl_base!(b.base);

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.b.setup(sim, rng);
        self.b.vx = G::signi(self.b.vx) * Self::HEAVY_SPEED_X;
        self.b.vy = 0;
    }

    fn step(&mut self, sim: &mut GameSim) {
        let b = &mut self.b;
        b.vy += Self::GRAVITY;
        b.x += b.vx;
        b.y += b.vy;
        b.bounce_sides(sim);
        b.bounce_top();
        if b.y > b.bottom_y() {
            b.y = b.bottom_y();
            b.vy = -Self::LAUNCH[(self.bounces % 2) as usize];
            self.bounces += 1;
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.b.kills(sim)
    }

    // straight_path() is false: near_row stays the Hazard default (false).

    fn checksum(&self, h: i64) -> i64 {
        mix_all(self.b.checksum(h), &[self.bounces])
    }
}
