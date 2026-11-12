//! STUB: to be ported from Sim/Hazards/Rotor.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Rotor {
    pub base: Base,
}

impl Hazard for Rotor {
    impl_base!();
}
