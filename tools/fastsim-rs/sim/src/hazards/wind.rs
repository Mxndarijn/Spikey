//! STUB: to be ported from Sim/Hazards/Wind.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Wind {
    pub base: Base,
}

impl Hazard for Wind {
    impl_base!();
}
