//! Checks.Revive (Checks.cs), was tests/sim/test_revive_survivable.gd: after a revive, in every
//! room, whatever the exit was doing and however the bird came in, SurvivalSearch finds a way to
//! live on. The GD test played one exit case and wall per room; this plays all.
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{result, Check};
use crate::bots::SurvivalSearch;
use crate::setups::Setups;

#[derive(Default)]
pub struct Revive {
    _cases: OnceLock<Vec<(i64, &'static str, i64, i64, i64)>>,
}

impl Revive {
    pub const TICKS: i64 = SimConfig::ARRIVAL_HOLD + 180;
    pub const CASES: [&'static str; 3] = ["none", "open", "ghost"];

    fn cases(&self) -> &Vec<(i64, &'static str, i64, i64, i64)> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<(i64, &'static str, i64, i64, i64)> {
        let mut out_ = Vec::new();
        for index in 0..RoomCatalog::all().len() as i64 {
            for exit in Self::CASES {
                for side in 0..2 {
                    for toward in 0..2 {
                        for y in Setups::ENTRY_YS {
                            out_.push((index, exit, side, toward, y));
                        }
                    }
                }
            }
        }
        out_
    }
}

impl Check for Revive {
    fn name(&self) -> &'static str {
        "revive"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_revive_survivable.gd:test_every_room_is_survivable_after_a_revive"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (index, exit, side, toward, y) = self.cases()[n];
        let sim = Setups::revived(index, 9000 + index, exit, side, toward, y);
        let mut search = SurvivalSearch::new();
        let mut fails = Vec::new();
        if !search.run(&sim, Self::TICKS) {
            let deaths: Vec<String> = search.last_deaths.iter().map(|(k, v)| format!("{}: {}", k, v)).collect();
            fails.push(format!(
                "{}, exit {} on wall {}, came in toward {} at {} px: all died {} ticks after the revive ({})",
                RoomCatalog::all()[index as usize].id,
                exit,
                side,
                toward,
                y / SimConfig::SUB,
                search.ticks_survived,
                deaths.join(", ")
            ));
        }
        result(fails, json!({}))
    }

    fn summary(&self, results: &[Value]) -> String {
        format!(
            "{} revives (every room x {} exit cases x both walls x both ways in x {} heights)",
            results.len(),
            Self::CASES.len(),
            Setups::ENTRY_YS.len()
        )
    }
}
