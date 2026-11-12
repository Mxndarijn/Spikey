//! Port of sim/hazards/pad_coin.gd (Sim/Hazards/PadCoin.cs). A CoinPickup
//! subclass: the parent is the field `c`. It overrides `visible()`, `step` and
//! `touch`, so no CoinPickup method that calls `visible()` runs for it.
use crate::hazards::Hz;
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct PadCoin {
    pub c: CoinPickup,
    pub on_top: bool,
    pub wait: i64,
}

impl PadCoin {
    pub const RESPAWN: i64 = 60;

    /// C# default: p_on_top = false.
    pub fn new(p_on_top: bool) -> PadCoin {
        PadCoin { c: CoinPickup::new(0, 0, 0), on_top: p_on_top, wait: 0 }
    }

    pub fn coin(&self) -> &CoinPickup {
        &self.c
    }

    pub fn coin_mut(&mut self) -> &mut CoinPickup {
        &mut self.c
    }

    /// PadCoin's override of CoinPickup.visible().
    pub fn visible(&self) -> bool {
        self.wait == 0
    }

    pub fn _follow(&mut self, sim: &GameSim) {
        let hs = &sim.room.hazards;
        for i in 0..hs.len() {
            // Our own slot holds Hz::Taken (never an EdgePad).
            if let Hz::EdgePad(pad) = &hs[i] {
                if pad.top == self.on_top {
                    self.c.x = G::clampi((pad.x0() + pad.x1()) / 2, SimConfig::COIN_MIN_X, SimConfig::COIN_MAX_X);
                    self.c.y = if self.on_top { SimConfig::COIN_MIN_Y } else { SimConfig::COIN_MAX_Y };
                    return;
                }
            }
        }
    }
}

impl Hazard for PadCoin {
    impl_base!(c.base);

    fn setup(&mut self, sim: &mut GameSim, _rng: &mut SimRng) {
        self._follow(sim);
    }

    fn step(&mut self, sim: &mut GameSim) {
        if self.wait > 0 {
            self.wait -= 1;
        }
        self._follow(sim);
    }

    fn touch(&mut self, sim: &mut GameSim) {
        if self.visible() && sim.bird_touches_circle(self.c.x, self.c.y, SimConfig::COIN_RADIUS) {
            sim.collect_coin(self.c.x, self.c.y, 1);
            self.on_top = !self.on_top;
            self.wait = Self::RESPAWN;
            self._follow(sim);
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.c.x, self.c.y, G::b(self.on_top), self.wait])
    }
}
