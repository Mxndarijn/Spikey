//! STUB: to be ported from Sim/Hazards/ExitKey.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct ExitKey {
    pub base: Base,
}

impl Hazard for ExitKey {
    impl_base!();
}
