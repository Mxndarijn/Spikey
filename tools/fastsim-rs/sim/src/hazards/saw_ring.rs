//! STUB: to be ported from Sim/Hazards/SawRing.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct SawRing {
    pub base: Base,
}

impl Hazard for SawRing {
    impl_base!();
}
