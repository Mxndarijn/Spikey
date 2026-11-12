//! STUB: to be ported from Sim/Hazards/Belt.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Belt {
    pub base: Base,
}

impl Hazard for Belt {
    impl_base!();
}
