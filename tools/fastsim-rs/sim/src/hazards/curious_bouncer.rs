//! STUB: to be ported from Sim/Hazards/CuriousBouncer.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CuriousBouncer {
    pub b: Bouncer,
}

impl Hazard for CuriousBouncer {
    impl_base!(b.base);
}
