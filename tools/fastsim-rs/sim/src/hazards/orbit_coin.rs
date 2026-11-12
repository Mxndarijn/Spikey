//! Port of sim/hazards/orbit_coin.gd (Sim/Hazards/OrbitCoin.cs). A CoinPickup
//! subclass: the parent is the field `c`. It keeps CoinPickup's `touch` (and
//! so CoinPickup's `visible()`, which OrbitCoin does not override).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct OrbitCoin {
    pub c: CoinPickup,
    pub cx: i64,
    pub cy: i64,
    pub radius: i64,
    pub phase: i64,
}

impl OrbitCoin {
    pub const PERIOD: i64 = 640;

    /// C# defaults: all 0.
    pub fn new(p_cx: i64, p_cy: i64, p_radius: i64, p_phase: i64) -> OrbitCoin {
        let mut o = OrbitCoin { c: CoinPickup::new(p_cx, p_cy, 0), cx: 0, cy: 0, radius: 0, phase: 0 };
        o.cx = p_cx;
        o.cy = p_cy;
        o.radius = p_radius;
        o.phase = p_phase;
        o._place();
        o
    }

    pub fn coin(&self) -> &CoinPickup {
        &self.c
    }

    pub fn coin_mut(&mut self) -> &mut CoinPickup {
        &mut self.c
    }

    pub fn _place(&mut self) {
        let a = self.phase + self.c.base.t * SimTrig::TURN / Self::PERIOD;
        self.c.x = self.cx + self.radius * SimTrig::cos_t(a) / SimTrig::ONE;
        self.c.y = self.cy + self.radius * SimTrig::sin_t(a) / SimTrig::ONE;
    }
}

impl Hazard for OrbitCoin {
    impl_base!(c.base);

    fn setup(&mut self, _sim: &mut GameSim, _rng: &mut SimRng) {
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn touch(&mut self, sim: &mut GameSim) {
        self.c.touch(sim);
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.c.x, self.c.y, self.cx, self.cy, self.radius, self.phase])
    }
}
