//! STUB: to be ported from Sim/Hazards/Stalactite.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Stalactite {
    pub base: Base,
}

impl Hazard for Stalactite {
    impl_base!();
}
