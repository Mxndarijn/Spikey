//! STUB: to be ported from Sim/Hazards/BossWatcher.cs
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct BossWatcher {
    pub boss: Boss,
}

impl BossWatcher {
    pub fn boss(&self) -> &Boss {
        &self.boss
    }
    pub fn boss_mut(&mut self) -> &mut Boss {
        &mut self.boss
    }
}

impl Hazard for BossWatcher {
    impl_base!(boss.base);
}
