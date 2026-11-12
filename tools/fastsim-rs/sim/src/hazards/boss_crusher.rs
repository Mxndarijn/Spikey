//! STUB: to be ported from Sim/Hazards/BossCrusher.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct BossCrusher {
    pub boss: Boss,
}

impl BossCrusher {
    pub fn boss(&self) -> &Boss {
        &self.boss
    }
    pub fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }
}

impl Hazard for BossCrusher {
    impl_base!(boss.base);
}
