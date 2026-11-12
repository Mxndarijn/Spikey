//! STUB: to be ported from Sim/Hazards/Dart.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Dart {
    pub base: Base,
}

impl Hazard for Dart {
    impl_base!();
}
