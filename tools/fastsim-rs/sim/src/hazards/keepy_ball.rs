//! STUB: to be ported from Sim/Hazards/KeepyBall.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct KeepyBall {
    pub base: Base,
}

impl Hazard for KeepyBall {
    impl_base!();
}
