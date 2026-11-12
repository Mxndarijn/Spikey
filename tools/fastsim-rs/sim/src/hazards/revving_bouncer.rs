//! STUB: to be ported from Sim/Hazards/RevvingBouncer.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct RevvingBouncer {
    pub b: Bouncer,
}

impl Hazard for RevvingBouncer {
    impl_base!(b.base);
}
