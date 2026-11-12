//! STUB: to be ported from Sim/Hazards/Bumper.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Bumper {
    pub base: Base,
}

impl Hazard for Bumper {
    impl_base!();
}
