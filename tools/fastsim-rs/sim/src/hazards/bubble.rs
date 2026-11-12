//! STUB: to be ported from Sim/Hazards/Bubble.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Bubble {
    pub base: Base,
}

impl Hazard for Bubble {
    impl_base!();
}
