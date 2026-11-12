//! STUB: to be ported from Sim/Hazards/OrchardSpawner.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct OrchardSpawner {
    pub base: Base,
}

impl Hazard for OrchardSpawner {
    impl_base!();
}
