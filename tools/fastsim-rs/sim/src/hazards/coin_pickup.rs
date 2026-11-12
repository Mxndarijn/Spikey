//! STUB: to be ported from Sim/Hazards/CoinPickup.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CoinPickup {
    pub base: Base,
}

impl CoinPickup {
    pub fn new(_x: i64, _y: i64, _appear_at: i64) -> CoinPickup {
        CoinPickup { base: Base::new("coin") }
    }
}

impl Hazard for CoinPickup {
    impl_base!();
}
