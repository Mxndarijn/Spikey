//! STUB: to be ported from Sim/Hazards/OrbitCoin.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct OrbitCoin {
    pub c: CoinPickup,
}

impl OrbitCoin {
    pub fn coin(&self) -> &CoinPickup {
        &self.c
    }
    pub fn coin_mut(&mut self) -> &mut CoinPickup {
        &mut self.c
    }
}

impl Hazard for OrbitCoin {
    impl_base!(c.base);
}
