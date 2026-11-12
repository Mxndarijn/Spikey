//! Port of sim/rooms/catalog_boss.gd (Sim/Rooms/CatalogBoss.cs). Order is part of the rules.
use crate::prelude::*;

pub struct CatalogBoss;

impl CatalogBoss {
    pub const SPIKES: i64 = 3;

    pub fn defs() -> Vec<RoomDef> {
        let mut out_ = Vec::new();
        out_.push(Self::_boss("boss_watcher", mk(|| BossWatcher::new().into())));
        out_.push(Self::_boss("boss_crusher", mk(|| BossCrusher::new().into())));
        out_.push(Self::_boss("boss_saw", mk(|| BossSaw::new().into())));
        out_
    }

    pub fn _boss(id: &'static str, make: Factory) -> RoomDef {
        let mut def = RoomDef::new(id, "boss", SimConfig::BOSS_EVERY);
        def.boss = true;
        def.max_spikes = Self::SPIKES;
        def.hazards.push(make);
        def
    }
}
