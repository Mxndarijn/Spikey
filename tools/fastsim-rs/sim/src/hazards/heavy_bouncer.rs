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

    /// One step of the arc (step(), and adjust_wall's look ahead on copies).
    pub fn path_step(b: &mut Bouncer, bounces: &mut i64, sim: &GameSim) {
        b.vy += Self::GRAVITY;
        b.x += b.vx;
        b.y += b.vy;
        b.bounce_sides(sim);
        b.bounce_top();
        if b.y > b.bottom_y() {
            b.y = b.bottom_y();
            b.vy = -Self::LAUNCH[(*bounces % 2) as usize];
            *bounces += 1;
        }
    }

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
        Self::path_step(&mut self.b, &mut self.bounces, sim);
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let mut bounces = self.bounces;
        let out = self.b.adjust_wall_path(sim, side, mask, &mut |b: &mut Bouncer, s: &GameSim| {
            Self::path_step(b, &mut bounces, s);
        });
        // A way over the ball: a free run above the highest it gets on the crossing.
        let at = sim.steps_to_wall(side);
        let mut c = self.b.clone();
        let mut cb = self.bounces;
        let mut peak = c.y;
        for _ in 0..at {
            Self::path_step(&mut c, &mut cb, sim);
            peak = G::mini(peak, c.y);
        }
        let clear = peak - self.b.radius - SimConfig::BIRD_RADIUS - Bouncer::ESCORT_MARGIN;
        let mut ok = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if SimConfig::slot_center_y(slot) < clear {
                ok |= 1i64 << slot;
            }
        }
        let all = (1i64 << SimConfig::SLOT_COUNT) - 1;
        let need = G::mini(sim.room.def().gap, RoomRules::longest_gap(all & !ok));
        RoomRules::keep_run(out, need, ok)
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.b.kills(sim)
    }

    // straight_path() is false: near_row stays the Hazard default (false).

    fn checksum(&self, h: i64) -> i64 {
        mix_all(self.b.checksum(h), &[self.bounces])
    }
}
