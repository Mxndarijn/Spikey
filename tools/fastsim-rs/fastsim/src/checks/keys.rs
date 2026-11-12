//! Checks.Keys (Checks.cs), Locked Out: every key of every variant can be taken on the way out.
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{result, Check};
use crate::bots::SurvivalSearch;

#[derive(Default)]
pub struct Keys {
    _cases: OnceLock<Vec<(&'static str, i64)>>,
}

impl Keys {
    pub const SEEDS_EACH: i64 = 12;
    /// 10 points, the locked bounces and the way out.
    pub const TICKS: i64 = 2400;

    fn cases(&self) -> &Vec<(&'static str, i64)> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<(&'static str, i64)> {
        let mut out_ = Vec::new();
        let index = RoomCatalog::index_of("lockexit");
        for v in &RoomCatalog::all()[index as usize].variants {
            for s in 0..Self::SEEDS_EACH {
                out_.push((v.id, 700 + s * 53));
            }
        }
        out_
    }

    /// The room's key (hazards[0]): (got, count, done).
    fn key(sim: &GameSim) -> (i64, i64, bool) {
        match &sim.room.hazards[0] {
            Hz::ExitKey(k) => (k.got, k.count, k.done()),
            _ => panic!("lockexit: hazards[0] is not an ExitKey"),
        }
    }
}

impl Check for Keys {
    fn name(&self) -> &'static str {
        "keys"
    }
    fn test(&self) -> &'static str {
        "tests/unit/test_locked_out.gd:test_every_key_can_be_taken"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (variant, seed_value) = self.cases()[n];
        let index = RoomCatalog::index_of("lockexit");
        let mut sim = GameSim::with(seed_value, Seasons::NONE, index, variant);
        let what = format!("lockexit/{} seed {}", variant, seed_value);
        let mut search = SurvivalSearch::new();
        let mut fails = Vec::new();
        if !search.run(&sim.clone_deep(), Self::TICKS) {
            fails.push(format!("{}: all died at tick {}", what, search.ticks_survived));
        } else if search.best.as_ref().map(|b| b.state.room_index).unwrap_or(0) < 1 {
            fails.push(format!("{}: took no portal", what));
        } else {
            // C# keeps a reference to the key hazard taken before each step, so it sees that
            // step's changes too, up to the moment the bird leaves the room. Here the key is read
            // after each step that stays in the room; on the step that leaves, the state from
            // before it is kept (a key taken in the very tick the bird goes through is missed).
            let mut key = Self::key(&sim);
            for &tap in &search.best_inputs {
                if sim.state.room_index > 0 {
                    break;
                }
                key = Self::key(&sim);
                sim.step(tap == 1);
                if sim.state.room_index == 0 {
                    key = Self::key(&sim);
                }
            }
            let (got, count, done) = key;
            if !done {
                fails.push(format!("{}: left with {} of {} keys", what, got, count));
            }
        }
        result(fails, json!({}))
    }

    fn summary(&self, results: &[Value]) -> String {
        format!("{} searches, {} seeds per Locked Out variant", results.len(), Self::SEEDS_EACH)
    }
}
