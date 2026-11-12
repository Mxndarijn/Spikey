//! STUB: to be ported from Sim/Hazards/Block.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Block {
    pub base: Base,
}

impl Hazard for Block {
    impl_base!();
}
