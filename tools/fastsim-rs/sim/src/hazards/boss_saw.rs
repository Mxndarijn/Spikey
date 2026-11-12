//! STUB: to be ported from Sim/Hazards/BossSaw.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct BossSaw {
    pub boss: Boss,
}

impl BossSaw {
    pub fn boss(&self) -> &Boss {
        &self.boss
    }
    pub fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }
}

impl Hazard for BossSaw {
    impl_base!(boss.base);
}
