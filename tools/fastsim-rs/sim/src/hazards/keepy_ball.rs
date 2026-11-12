//! Port of sim/hazards/keepy_ball.gd (Sim/Hazards/KeepyBall.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct KeepyBall {
    pub base: Base,
    pub gravity: i64,
    pub kick_vy: i64,
    pub waiting: i64,
    pub redrop: i64,

    pub x: i64,
    pub y: i64,
    pub vx: i64,
    pub vy: i64,
    pub cooldown: i64,
    pub bumps: i64,
}

impl KeepyBall {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 22 * Self::SUB;
    pub const GRAVITY: i64 = 18;
    pub const MAX_VY: i64 = 7 * Self::SUB;
    pub const KICK_VY: i64 = 9 * Self::SUB;
    pub const KICK_VX: i64 = 3 * Self::SUB;
    pub const COOLDOWN: i64 = 15;
    pub const MIN_X: i64 = 120 * Self::SUB;
    pub const MAX_X: i64 = 240 * Self::SUB;
    pub const HEAVY_GRAVITY: i64 = 27;
    pub const HEAVY_KICK_VY: i64 = 7 * Self::SUB;
    pub const SECOND_DROP: i64 = 120;
    pub const REDROP: i64 = 90;

    pub fn new() -> KeepyBall {
        KeepyBall {
            base: Base::new("keepy_ball"),
            gravity: Self::GRAVITY,
            kick_vy: Self::KICK_VY,
            waiting: 0,
            redrop: 0,
            x: 0,
            y: -Self::RADIUS,
            vx: 0,
            vy: 0,
            cooldown: 0,
            bumps: 0,
        }
    }

    /// C# returns `this` as a Hazard; here the ball itself (`.into()` for Hz).
    pub fn heavy(mut self) -> KeepyBall {
        self.gravity = Self::HEAVY_GRAVITY;
        self.kick_vy = Self::HEAVY_KICK_VY;
        self
    }

    /// C# returns `this` as a Hazard; here the ball itself (`.into()` for Hz).
    pub fn dropping(mut self, delay: i64) -> KeepyBall {
        self.waiting = delay;
        self.redrop = Self::REDROP;
        self
    }
}

impl Hazard for KeepyBall {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self.x = Self::MIN_X + rng.next_below(Self::MAX_X - Self::MIN_X + 1);
        self.y = -Self::RADIUS;
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.waiting > 0 {
            self.waiting -= 1;
            return;
        }
        if self.cooldown > 0 {
            self.cooldown -= 1;
        }
        self.vy = G::mini(self.vy + self.gravity, Self::MAX_VY);
        self.x += self.vx;
        self.y += self.vy;
        let left = sim.room.wall_left() + Self::RADIUS;
        let right = sim.room.wall_right() - Self::RADIUS;
        if self.x < left {
            self.x = 2 * left - self.x;
            self.vx = G::absi(self.vx);
        } else if self.x > right {
            self.x = 2 * right - self.x;
            self.vx = -G::absi(self.vx);
        }
        let top = SimConfig::KILL_TOP + Self::RADIUS;
        if self.vy < 0 && self.y < top {
            self.y = 2 * top - self.y;
            self.vy = -self.vy;
        }
        if self.y + Self::RADIUS >= SimConfig::KILL_BOTTOM {
            if self.redrop == 0 {
                self.base.alive = false;
                return;
            }
            self.waiting = self.redrop;
            self.x = G::clampi(SimConfig::WORLD_W - self.x, Self::MIN_X, Self::MAX_X);
            self.y = -Self::RADIUS;
            self.vx = 0;
            self.vy = 0;
            self.cooldown = 0;
        }
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if self.waiting > 0 || self.cooldown > 0 || !sim.bird_touches_circle(self.x, self.y, Self::RADIUS) {
            return;
        }
        let dx = self.x - sim.state.x;
        let reach = SimConfig::BIRD_RADIUS + Self::RADIUS;
        self.vx = G::clampi(dx, -reach, reach) * Self::KICK_VX / reach;
        self.vy = -self.kick_vy;
        let above = sim.state.y - reach;
        if self.y > above {
            self.y = above;
        }
        self.cooldown = Self::COOLDOWN;
        self.bumps += 1;
        sim.collect_coin(self.x, self.y, 1);
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(h, &[self.x, self.y, self.vx, self.vy, self.cooldown, self.bumps]);
        if self.gravity != Self::GRAVITY || self.kick_vy != Self::KICK_VY || self.redrop != 0 {
            out_ = mix_all(out_, &[self.gravity, self.kick_vy, self.waiting, self.redrop]);
        }
        out_
    }
}
