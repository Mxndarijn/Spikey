//! Port of sim/hazards/bubble.gd (Sim/Hazards/Bubble.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Bubble {
    pub base: Base,
    pub x: i64,
    pub y: i64,
    pub vy: i64,
    pub next_x: i64,
    pub carrying: bool,
    pub lane: i64,
    pub cooldown: i64,
    pub since_pop: i64,
    pub radius: i64,
    pub spiked: bool,
    pub wait: i64,
    pub delay: i64,
    pub coin_bubble: bool,
    pub has_coin: bool,
}

impl Bubble {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 22 * Self::SUB;
    pub const RISE: i64 = 96;
    pub const GIANT_RADIUS: i64 = 38 * Self::SUB;
    pub const GIANT_RISE: i64 = 56;
    pub const SPIKED_RADIUS: i64 = 24 * Self::SUB;
    pub const WARN: i64 = 60;
    pub const POP_TOP: i64 = SimConfig::KILL_TOP + 10 * Self::SUB;
    pub const MIN_X: i64 = 90 * Self::SUB;
    pub const MAX_X: i64 = 270 * Self::SUB;
    pub const REGRAB: i64 = 12;

    /// C# defaults: p_lane = 0, p_radius = RADIUS, p_rise = RISE.
    pub fn new(p_lane: i64, p_radius: i64, p_rise: i64) -> Bubble {
        Bubble {
            base: Base::new("bubble"),
            x: 0,
            y: 0,
            vy: -p_rise,
            next_x: 0,
            carrying: false,
            lane: p_lane,
            cooldown: 0,
            since_pop: 1000,
            radius: p_radius,
            spiked: false,
            wait: 0,
            delay: 0,
            coin_bubble: false,
            has_coin: false,
        }
    }

    pub fn spiky(mut self, p_delay: i64) -> Bubble {
        self.spiked = true;
        self.radius = Self::SPIKED_RADIUS;
        self.delay = p_delay;
        self
    }

    pub fn with_coin(mut self) -> Bubble {
        self.coin_bubble = true;
        self
    }

    pub fn pop(&mut self) {
        self.carrying = false;
        self.since_pop = 0;
        self.cooldown = Self::REGRAB;
        self.x = self.next_x;
        self.y = SimConfig::WORLD_H + self.radius;
        self.has_coin = self.coin_bubble;
        if self.spiked {
            self.wait = Self::WARN;
        }
    }

    pub fn _other_carrying(&self, sim: &GameSim) -> bool {
        let hs = &sim.room.hazards;
        for i in 0..hs.len() {
            // C# `h != this`: our own slot (Taken while touch runs) is skipped.
            if i == self.base.idx {
                continue;
            }
            let h = &hs[i];
            if h.alive() && h.kind() == "bubble" {
                let Hz::Bubble(b) = h else { panic!("kind bubble is not a Bubble") };
                if b.carrying {
                    return true;
                }
            }
        }
        false
    }

    pub fn _take_coin(&mut self, sim: &mut GameSim) {
        if !self.has_coin || !self.coin_in_reach() {
            return;
        }
        if sim.bird_touches_circle(self.x, self.y, SimConfig::COIN_RADIUS) {
            self.has_coin = false;
            sim.collect_coin(self.x, self.y, 1);
        }
    }

    pub fn coin_in_reach(&self) -> bool {
        self.y >= SimConfig::COIN_MIN_Y && self.y <= SimConfig::COIN_MAX_Y
    }

    pub fn _hold(&mut self, sim: &mut GameSim) {
        self.x = sim.state.x;
        sim.state.y = self.y;
        sim.state.vy = self.vy;
    }
}

impl Hazard for Bubble {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self.x = Self::MIN_X + rng.next_below(Self::MAX_X - Self::MIN_X + 1);
        self.next_x = Self::MIN_X + rng.next_below(Self::MAX_X - Self::MIN_X + 1);
        self.y = (520 - self.lane * 170) * Self::SUB;
        self.has_coin = self.coin_bubble;
        if self.spiked {
            self.y = SimConfig::WORLD_H + self.radius;
            self.wait = Self::WARN + self.delay;
        }
    }

    fn step(&mut self, _sim: &mut GameSim) {
        if self.cooldown > 0 {
            self.cooldown -= 1;
        }
        self.since_pop = G::mini(self.since_pop + 1, 1000);
        if self.wait > 0 {
            self.wait -= 1;
            return;
        }
        self.y += self.vy;
        if self.y - self.radius <= Self::POP_TOP {
            self.pop();
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        self.spiked && self.wait == 0 && sim.bird_touches_circle(self.x, self.y, self.radius)
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if self.spiked {
            return;
        }
        if self.carrying {
            self._hold(sim);
        } else if self.cooldown == 0
            && sim.bird_touches_circle(self.x, self.y, self.radius - SimConfig::BIRD_RADIUS)
        {
            if !self._other_carrying(sim) {
                self.carrying = true;
                self._hold(sim);
            }
        }
        self._take_coin(sim);
    }

    fn on_bounce(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self.next_x = Self::MIN_X + rng.next_below(Self::MAX_X - Self::MIN_X + 1);
    }

    fn on_flap(&mut self, _sim: &mut GameSim) {
        if self.carrying {
            self.pop();
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(
            h,
            &[
                self.x,
                self.y,
                self.vy,
                self.next_x,
                G::b(self.carrying),
                self.lane,
                self.cooldown,
                self.since_pop,
                self.radius,
                G::b(self.spiked),
                self.wait,
                G::b(self.has_coin),
            ],
        )
    }
}
