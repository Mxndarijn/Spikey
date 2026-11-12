//! STUB: to be ported from Sim/Hazards/Crawler.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Crawler {
    pub base: Base,
}

impl Hazard for Crawler {
    impl_base!();
}
