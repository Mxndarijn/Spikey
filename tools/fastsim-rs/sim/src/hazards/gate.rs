//! STUB: to be ported from Sim/Hazards/Gate.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Gate {
    pub base: Base,
}

impl Hazard for Gate {
    impl_base!();
}
