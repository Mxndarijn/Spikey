//! STUB: to be ported from Sim/Hazards/Firework.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Firework {
    pub base: Base,
}

impl Hazard for Firework {
    impl_base!();
}
