//! STUB: to be ported from Sim/Hazards/Lava.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Lava {
    pub base: Base,
}

impl Hazard for Lava {
    impl_base!();
}
