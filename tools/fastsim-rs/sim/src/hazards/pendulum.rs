//! STUB: to be ported from Sim/Hazards/Pendulum.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Pendulum {
    pub base: Base,
}

impl Hazard for Pendulum {
    impl_base!();
}
