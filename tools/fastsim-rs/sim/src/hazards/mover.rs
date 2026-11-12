//! STUB: to be ported from Sim/Hazards/Mover.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Mover {
    pub base: Base,
}

impl Hazard for Mover {
    impl_base!();
}
