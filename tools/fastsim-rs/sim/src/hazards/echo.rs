//! STUB: to be ported from Sim/Hazards/Echo.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Echo {
    pub base: Base,
}

impl Hazard for Echo {
    impl_base!();
}
