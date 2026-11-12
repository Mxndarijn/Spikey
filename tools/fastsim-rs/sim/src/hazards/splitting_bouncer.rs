//! STUB: to be ported from Sim/Hazards/SplittingBouncer.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct SplittingBouncer {
    pub b: Bouncer,
}

impl Hazard for SplittingBouncer {
    impl_base!(b.base);
}
