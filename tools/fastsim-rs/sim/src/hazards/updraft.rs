//! STUB: to be ported from Sim/Hazards/Updraft.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Updraft {
    pub base: Base,
}

impl Hazard for Updraft {
    impl_base!();
}
