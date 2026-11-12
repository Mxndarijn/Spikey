//! Port of sim/hazards/stalker.gd (Sim/Hazards/Stalker.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Stalker {
    pub base: Base,
    pub side: i64,
    pub y: i64,
    pub x: i64,
}

impl Stalker {
    pub const DEPTH: i64 = SimConfig::SPIKE_DEPTH;
    pub const HALF_BASE: i64 = SimConfig::SPIKE_HALF_BASE;
    pub const HALF_H: i64 = 2 * SimConfig::SPIKE_HALF_BASE;
    pub const MAX_SPEED: i64 = 80;
    pub const MIN_Y: i64 = SimConfig::SLOT_TOP + Self::HALF_H;
    pub const MAX_Y: i64 = SimConfig::SLOT_TOP + SimConfig::SLOT_COUNT * SimConfig::SLOT_SIZE - Self::HALF_H;

    pub fn new() -> Stalker {
        Stalker { base: Base::new("stalker"), side: 1, y: 0, x: 0 }
    }

    pub fn base_x(&self, sim: &GameSim) -> i64 {
        if self.side == 0 { sim.room.wall_left() } else { sim.room.wall_right() }
    }

    pub fn dir(&self) -> i64 {
        if self.side == 0 { 1 } else { -1 }
    }
}

impl Hazard for Stalker {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        self.side = if sim.state.vx > 0 { 1 } else { 0 };
        self.y = Self::MIN_Y + rng.next_below(Self::MAX_Y - Self::MIN_Y + 1);
        self.x = self.base_x(sim);
    }

    fn step(&mut self, sim: &mut GameSim) {
        self.side = if sim.state.vx > 0 { 1 } else { 0 };
        let target = G::clampi(sim.state.y, Self::MIN_Y, Self::MAX_Y);
        let old = self.y;
        self.y += G::clampi(target - self.y, -Self::MAX_SPEED, Self::MAX_SPEED);
        self.y = ExitZone::stop_y(sim, self.side, old, self.y, Self::HALF_H, Self::MIN_Y, Self::MAX_Y);
        self.x = self.base_x(sim);
    }

    fn kills(&self, sim: &GameSim) -> bool {
        let bx = self.x;
        let tip = bx + self.dir() * Self::DEPTH;
        let r = SimConfig::BIRD_RADIUS;
        let mut cy = self.y - Self::HALF_BASE;
        if SimMath::circle_hits_triangle(
            sim.state.x,
            sim.state.y,
            r,
            bx,
            cy - Self::HALF_BASE,
            bx,
            cy + Self::HALF_BASE,
            tip,
            cy,
        ) {
            return true;
        }
        cy = self.y + Self::HALF_BASE;
        if SimMath::circle_hits_triangle(
            sim.state.x,
            sim.state.y,
            r,
            bx,
            cy - Self::HALF_BASE,
            bx,
            cy + Self::HALF_BASE,
            tip,
            cy,
        ) {
            return true;
        }
        false
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.side, self.y, self.x])
    }
}
