//! STUB: to be ported from Sim/Hazards/EdgePad.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct EdgePad {
    pub base: Base,
}

impl Hazard for EdgePad {
    impl_base!();
}
