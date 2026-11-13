//! Port of sim/hazards/coin_pickup.gd (Sim/Hazards/CoinPickup.cs).
use crate::hazards::Hz;
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CoinPickup {
    pub base: Base,
    pub x: i64,
    pub y: i64,
    pub appear_at: i64,
    pub vy: i64,
    pub beside_band: i64,
    pub value: i64,
    pub behind: bool,
    pub drift: i64,
    pub home_x: i64,
}

impl CoinPickup {
    pub const BESIDE_GAP: i64 = 22 * SimConfig::SUB;
    pub const BESIDE_MAX_X: i64 = 290 * SimConfig::SUB;
    pub const GOLD_VALUE: i64 = 5;

    /// C# defaults: all 0.
    pub fn new(p_x: i64, p_y: i64, p_appear_at: i64) -> CoinPickup {
        CoinPickup {
            base: Base::new("coin"),
            x: p_x,
            y: p_y,
            appear_at: p_appear_at,
            vy: 0,
            beside_band: -1,
            value: 1,
            behind: false,
            drift: 0,
            home_x: 0,
        }
    }

    pub fn visible(&self) -> bool {
        self.base.t >= self.appear_at
    }
}

impl Hazard for CoinPickup {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        if self.beside_band < 0 {
            return;
        }
        let hs = &sim.room.hazards;
        for i in 0..hs.len() {
            // Our own slot holds Hz::Taken (a coin, never a Block).
            if let Hz::Block(island) = &hs[i] {
                if island.band == self.beside_band {
                    self.x = if island.x1 + Self::BESIDE_GAP + island.drift <= Self::BESIDE_MAX_X {
                        island.x1 + Self::BESIDE_GAP
                    } else {
                        island.x0 - Self::BESIDE_GAP
                    };
                    if self.behind {
                        let left = island.x0 + island.x1 < SimConfig::WORLD_W;
                        self.x = if left { island.x0 - Self::BESIDE_GAP } else { island.x1 + Self::BESIDE_GAP };
                    }
                    self.y = (island.y0 + island.y1) / 2;
                    self.drift = island.drift;
                    self.home_x = self.x;
                    return;
                }
            }
        }
    }

    fn step(&mut self, _sim: &mut GameSim) {
        if self.drift > 0 {
            self.x = self.home_x + Block::sway(self.drift, self.base.t);
        }
        if self.vy != 0 && self.visible() {
            self.y += self.vy;
            if self.y > SimConfig::KILL_BOTTOM + SimConfig::COIN_RADIUS {
                self.base.alive = false;
            }
        }
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if self.visible() && sim.bird_touches_circle(self.x, self.y, SimConfig::COIN_RADIUS) {
            self.base.alive = false;
            sim.collect_coin(self.x, self.y, self.value);
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.x, self.y, self.appear_at, self.vy])
    }
}
