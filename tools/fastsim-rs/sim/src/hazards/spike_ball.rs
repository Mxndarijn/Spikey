//! STUB: to be ported from Sim/Hazards/SpikeBall.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct SpikeBall {
    pub base: Base,
}

impl Hazard for SpikeBall {
    impl_base!();
}
