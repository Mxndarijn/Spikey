//! Port of sim/hazards/bouncer.gd (Sim/Hazards/Bouncer.cs).
use crate::prelude::*;

pub struct Lane;
impl Lane {
    pub const ANY: i64 = 0;
    pub const UPPER: i64 = 1;
    pub const LOWER: i64 = 2;
}

#[derive(Clone, Debug)]
pub struct Bouncer {
    pub base: Base,
    pub radius: i64,
    pub lane: i64,
    pub x: i64,
    pub y: i64,
    pub vx: i64,
    pub vy: i64,
}

impl Bouncer {
    pub const RADIUS: i64 = 20 * SimConfig::SUB;
    pub const SPEED_X: i64 = 3 * SimConfig::SUB;
    pub const SPEED_Y: i64 = 2 * SimConfig::SUB + 32;
    pub const MARGIN: i64 = 44 * SimConfig::SUB;
    pub const TWIN_RADIUS: i64 = 15 * SimConfig::SUB;

    /// C# defaults: p_radius = RADIUS, p_lane = Lane.ANY.
    pub fn new(p_radius: i64, p_lane: i64) -> Bouncer {
        Bouncer { base: Base::new("bouncer"), radius: p_radius, lane: p_lane, x: 0, y: 0, vx: 0, vy: 0 }
    }

    pub fn default_() -> Bouncer {
        Self::new(Self::RADIUS, Lane::ANY)
    }

    pub fn move_(&mut self, sim: &GameSim) -> bool {
        self.x += self.vx;
        self.y += self.vy;
        let side = self.bounce_sides(sim);
        let top = self.bounce_top();
        let bottom = self.bounce_bottom();
        side || top || bottom
    }

    pub fn bounce_sides(&mut self, sim: &GameSim) -> bool {
        let left = sim.room.wall_left() + self.radius;
        let right = sim.room.wall_right() - self.radius;
        let mut out_ = false;
        if self.x < left {
            self.x = 2 * left - self.x;
            self.vx = G::absi(self.vx);
            out_ = true;
        } else if self.x > right {
            self.x = 2 * right - self.x;
            self.vx = -G::absi(self.vx);
            out_ = true;
        }
        if let Some(b) = ExitZone::bounce(sim, self.x, self.y, self.vx, self.vy, self.radius) {
            self.x = b[0];
            self.y = b[1];
            self.vx = b[2];
            self.vy = b[3];
            out_ = true;
        }
        out_
    }

    pub fn bounce_top(&mut self) -> bool {
        if self.y < self.top_y() {
            self.y = 2 * self.top_y() - self.y;
            self.vy = G::absi(self.vy);
            return true;
        }
        false
    }

    pub fn bounce_bottom(&mut self) -> bool {
        if self.y > self.bottom_y() {
            self.y = 2 * self.bottom_y() - self.y;
            self.vy = -G::absi(self.vy);
            return true;
        }
        false
    }

    pub fn top_y(&self) -> i64 {
        Self::MARGIN + self.radius
    }

    pub fn bottom_y(&self) -> i64 {
        SimConfig::WORLD_H - Self::MARGIN - self.radius
    }

    /// Bouncer.near_row for a straight path (the subclasses' straight_path() is false).
    pub fn near_row_straight(&self, sim: &GameSim, p_y: i64, half: i64, from: i64, to: i64) -> bool {
        // C# moves itself and restores the fields after; a copy is the same.
        let mut c = self.clone();
        let mut out_ = false;
        for k in 0..to {
            c.move_(sim);
            if k + 1 >= from && G::absi(c.y - p_y) < c.radius + half {
                out_ = true;
                break;
            }
        }
        out_
    }
}

impl Hazard for Bouncer {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        let bird_left = sim.state.x < SimConfig::WORLD_W / 2;
        let top = Self::MARGIN + self.radius;
        let span = SimConfig::WORLD_H - 2 * top;
        if self.lane == Lane::UPPER {
            self.x = if bird_left { SimConfig::WORLD_W * 3 / 4 } else { SimConfig::WORLD_W / 4 };
            self.y = top + rng.next_below(span / 2);
            self.vy = Self::SPEED_Y;
        } else if self.lane == Lane::LOWER {
            self.x = if bird_left { SimConfig::WORLD_W * 5 / 8 } else { SimConfig::WORLD_W * 3 / 8 };
            self.y = top + span / 2 + rng.next_below(span / 2);
            self.vy = -Self::SPEED_Y;
        } else {
            self.x = if bird_left { SimConfig::WORLD_W * 3 / 4 } else { SimConfig::WORLD_W / 4 };
            self.y = top + rng.next_below(span);
            self.vy = if rng.next_below(2) == 0 { Self::SPEED_Y } else { -Self::SPEED_Y };
        }
        self.vx = if bird_left { Self::SPEED_X } else { -Self::SPEED_X };
    }

    fn step(&mut self, sim: &mut GameSim) {
        self.move_(sim);
    }

    fn kills(&self, sim: &GameSim) -> bool {
        sim.bird_touches_circle(self.x, self.y, self.radius)
    }

    fn near_row(&self, sim: &GameSim, p_y: i64, half: i64, from: i64, to: i64) -> bool {
        self.near_row_straight(sim, p_y, half, from, to)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.x, self.y, self.vx, self.vy])
    }
}
