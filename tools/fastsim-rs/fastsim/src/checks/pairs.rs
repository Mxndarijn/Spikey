//! Checks.Pairs (Checks.cs), was test_every_pair_has_a_way_through in
//! tests/sim/test_double_trouble.gd: SurvivalSearch lives through each pair's practice seeds.
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{result, Check};
use crate::bots::SurvivalSearch;

#[derive(Default)]
pub struct Pairs {
    _cases: OnceLock<Vec<i64>>,
}

impl Pairs {
    /// Seeds searched per pair (the GD test played the first 2) and how long.
    pub const SEARCH_SEEDS: i64 = 8;
    pub const SEARCH_TICKS: i64 = 600;

    fn cases(&self) -> &Vec<i64> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<i64> {
        let n = RoomCatalog::find("double").expect("no room 'double'").variants.len() as i64;
        (0..n * Self::SEARCH_SEEDS).collect()
    }
}

impl Check for Pairs {
    fn name(&self) -> &'static str {
        "pairs"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_double_trouble.gd:test_every_pair_has_a_way_through"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let index = RoomCatalog::index_of("double");
        let def = &RoomCatalog::all()[index as usize];
        let pairs = def.variants.len() as i64;
        let i = self.cases()[n];
        let p = i % pairs;
        let mut fails = Vec::new();
        // The first practice seed whose pair is `p`, by the hazards the room built.
        let mut s = 1000 + i * 7;
        while s < 3000 {
            let sim = GameSim::with(s, def.season, index, "");
            if sim.room.variant != p {
                s += 1;
                continue;
            }
            let mut search = SurvivalSearch::new();
            if !search.run(&sim, Self::SEARCH_TICKS) {
                fails.push(format!("pair {} seed {}: all died at tick {}", p, s, search.ticks_survived));
            }
            return result(fails, json!({}));
        }
        result(vec![format!("no seed for pair {}", p)], json!({}))
    }

    fn summary(&self, results: &[Value]) -> String {
        format!("{} searches ({} seeds per pair)", results.len(), Self::SEARCH_SEEDS)
    }
}
