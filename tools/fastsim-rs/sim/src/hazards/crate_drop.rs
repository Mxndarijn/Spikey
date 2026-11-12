//! STUB: to be ported from Sim/Hazards/CrateDrop.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CrateDrop {
    pub base: Base,
}

impl Hazard for CrateDrop {
    impl_base!();
}
