//! STUB: to be ported from Sim/Hazards/PadCoin.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct PadCoin {
    pub c: CoinPickup,
}

impl PadCoin {
    pub fn coin(&self) -> &CoinPickup {
        &self.c
    }
    pub fn coin_mut(&mut self) -> &mut CoinPickup {
        &mut self.c
    }
}

impl Hazard for PadCoin {
    impl_base!(c.base);
}
