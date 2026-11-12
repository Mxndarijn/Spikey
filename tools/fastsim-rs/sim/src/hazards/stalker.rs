//! STUB: to be ported from Sim/Hazards/Stalker.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Stalker {
    pub base: Base,
}

impl Hazard for Stalker {
    impl_base!();
}
