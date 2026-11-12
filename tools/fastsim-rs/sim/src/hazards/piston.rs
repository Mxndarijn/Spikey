//! STUB: to be ported from Sim/Hazards/Piston.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Piston {
    pub base: Base,
}

impl Hazard for Piston {
    impl_base!();
}
