//! Checks.Passable (Checks.cs), was tests/sim/test_variants_passable.gd: SurvivalSearch gets
//! through each practice seed of every variant and takes the first portal.
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{result, Check};
use crate::bots::SurvivalSearch;

#[derive(Default)]
pub struct Passable {
    _cases: OnceLock<Vec<(&'static str, i64, i64)>>,
}

impl Passable {
    /// Practice seeds per room variant (the GD test played the first 2 of these).
    pub const SEEDS_EACH: i64 = 6;
    /// test_variants_passable.gd CASES: [room id, ticks].
    pub const CASES: [(&'static str, i64); 44] = [
        ("narrow", 900), ("tide", 1150), ("cloud", 1150), ("bramble", 1150), ("rain", 1150),
        ("swing", 1150), ("updraft", 1150), ("crosswind", 1150), ("belt", 1150), ("lockexit", 1700),
        ("lava", 1150), ("echo", 1150), ("bubbles", 1150), ("garden", 1150), ("slowmo", 2300),
        ("court", 1150), ("crowded", 1150), ("squeeze", 1150), ("blink", 1150), ("hunter", 1150),
        ("flip", 1150), ("midnight", 1150), ("sawring", 1150), ("bats", 1150), ("cupid", 1150),
        ("fireworks", 1150), ("crawl", 1150), ("crabs", 1150), ("pumpkin", 1150), ("keepy", 1150),
        ("beachball", 1150), ("hearts", 1150), ("isles", 1150), ("eggs", 1150), ("gates", 1150),
        ("ghostdoors", 1150), ("piston", 1150), ("stalac", 1150), ("crates", 1150), ("gifts", 1150),
        ("beams", 1150),
        ("boss_watcher", 1950), ("boss_crusher", 1950), ("boss_saw", 1950),
    ];

    fn cases(&self) -> &Vec<(&'static str, i64, i64)> {
        self._cases.get_or_init(Self::make)
    }

    /// [room id, practice seed, ticks] (seed -1: a variant with too few seeds),
    /// picked as test_variants_passable.gd _cases().
    fn make() -> Vec<(&'static str, i64, i64)> {
        let mut out_ = Vec::new();
        for (id, ticks) in Self::CASES {
            let index = RoomCatalog::index_of(id);
            let def = &RoomCatalog::all()[index as usize];
            // C# Dictionary<long, long> (only removals after the adds: keys stay in order).
            let mut wanted: Vec<(i64, i64)> = Vec::new();
            for v in 0..G::maxi(def.variants.len() as i64, 1) {
                wanted.push((v, Self::SEEDS_EACH));
            }
            let mut seed_value: i64 = 500;
            while !wanted.is_empty() && seed_value < 6000 {
                seed_value += 37;
                let v = GameSim::with(seed_value, def.season, index, "").room.variant;
                let Some(k) = wanted.iter().position(|w| w.0 == v) else { continue };
                wanted[k].1 -= 1;
                if wanted[k].1 == 0 {
                    wanted.remove(k);
                }
                out_.push((id, seed_value, ticks));
            }
            for (v, _) in wanted {
                out_.push((id, -1, v));
            }
        }
        out_
    }
}

impl Check for Passable {
    fn name(&self) -> &'static str {
        "passable"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_variants_passable.gd:test_rooms_are_passable_in_every_variant"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (id, seed_value, ticks) = self.cases()[n];
        if seed_value < 0 {
            return result(vec![format!("{}: variant {} has fewer than {} seeds", id, ticks, Self::SEEDS_EACH)], json!({}));
        }
        let index = RoomCatalog::index_of(id);
        let def = &RoomCatalog::all()[index as usize];
        let sim = GameSim::with(seed_value, def.season, index, "");
        let what = format!("{} seed {} ({})", id, seed_value, sim.room.variant_id());
        let mut search = SurvivalSearch::new();
        let ok = search.run(&sim, ticks);
        let mut fails = Vec::new();
        if !ok {
            fails.push(format!("{}: all died at tick {}", what, search.ticks_survived));
        } else if search.best.as_ref().map(|b| b.state.room_index).unwrap_or(0) < 1 {
            fails.push(format!("{}: took no portal", what));
        }
        result(fails, json!({}))
    }

    fn summary(&self, results: &[Value]) -> String {
        format!(
            "{} searches, {} practice seeds per variant of {} rooms",
            results.len(),
            Self::SEEDS_EACH,
            Self::CASES.len()
        )
    }
}
