//! STUB: to be ported from Sim/Hazards/Beam.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Beam {
    pub base: Base,
}

impl Hazard for Beam {
    impl_base!();
}
