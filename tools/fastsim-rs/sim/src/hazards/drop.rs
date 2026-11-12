//! STUB: to be ported from Sim/Hazards/Drop.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Drop {
    pub base: Base,
}

impl Hazard for Drop {
    impl_base!();
}
