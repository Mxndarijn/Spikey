//! Checks.Runs (CheckSearches.cs), was tests/sim/test_bot_runs.gd: random tappers keep the sim's
//! invariants and every run ends; gap seekers clear several rooms (more runs here: the GD test
//! played 150 and 40).
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{result, Check};
use crate::bots::SimBots;

#[derive(Default)]
pub struct Runs {
    /// (kind, run, seed).
    _cases: OnceLock<Vec<(&'static str, i64, i64)>>,
}

impl Runs {
    pub const RANDOM_RUNS: i64 = 600;
    pub const SEEKER_RUNS: i64 = 160;
    pub const RANDOM_TICKS: i64 = 20000;

    fn cases(&self) -> &Vec<(&'static str, i64, i64)> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<(&'static str, i64, i64)> {
        let mut out_ = Vec::new();
        let mut seeds = SimRng::new(1001);
        for run in 0..Self::RANDOM_RUNS {
            out_.push(("random", run, seeds.next_u32()));
        }
        seeds = SimRng::new(2002);
        for run in 0..Self::SEEKER_RUNS {
            out_.push(("seeker", run, seeds.next_u32()));
        }
        out_
    }

    fn scores(results: &[Value]) -> Vec<i64> {
        results.iter().filter(|r| !r["score"].is_null()).map(|r| super::i(&r["score"])).collect()
    }
}

impl Check for Runs {
    fn name(&self) -> &'static str {
        "runs"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_bot_runs.gd"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (kind, run, seed_value) = self.cases()[n];
        let mut fails: Vec<String> = Vec::new();
        if kind == "seeker" {
            return result(fails, json!({ "score": SimBots::play_gap(seed_value, run + 1).state.score }));
        }
        let mut sim = GameSim::new(seed_value);
        let mut bot = SimRng::new(run + 1);
        let mut last_score = 0;
        while !sim.is_over() && sim.state.tick < Self::RANDOM_TICKS {
            let tap = SimBots::random_tapper(&sim, &mut bot, 12);
            sim.step(tap);
            let s = &sim.state;
            let r = SimConfig::BIRD_RADIUS;
            if s.x - r < -SimConfig::SPEED_X || s.x + r > SimConfig::WORLD_W + SimConfig::SPEED_X {
                fails.push(format!("run {} tick {}: bird outside side walls (x={})", run, s.tick, s.x));
            }
            if s.score < last_score || s.score > last_score + 1 {
                fails.push(format!("run {} tick {}: score jumped {} -> {}", run, s.tick, last_score, s.score));
            }
            // Rooms change through exits, which open every POINTS_PER_ROOM points.
            if s.room_index > s.score / SimConfig::POINTS_PER_ROOM {
                fails.push(format!("run {} tick {}: room {} at score {}", run, s.tick, s.room_index, s.score));
            }
            if s.left_spikes != 0 && s.right_spikes != 0 {
                fails.push(format!("run {} tick {}: both walls have spikes", run, s.tick));
            }
            if !fails.is_empty() {
                return result(fails, json!({}));
            }
            last_score = s.score;
        }
        if !sim.is_over() {
            fails.push(format!("run {} never ended", run));
        }
        result(fails, json!({}))
    }

    fn combine(&self, results: &[Value]) -> Vec<String> {
        let got = Self::scores(results);
        let mut fails = Vec::new();
        let best = got.iter().copied().max().unwrap_or(0);
        if best < 3 * SimConfig::POINTS_PER_ROOM {
            fails.push(format!("best bot run reaches room 4 (got {})", best));
        }
        let changes = got.iter().filter(|&&x| x >= SimConfig::POINTS_PER_ROOM).count() as i64;
        if changes < Self::SEEKER_RUNS / 2 {
            fails.push(format!("most bot runs change room at least once ({} of {})", changes, Self::SEEKER_RUNS));
        }
        fails
    }

    fn summary(&self, results: &[Value]) -> String {
        let got = Self::scores(results);
        let best = got.iter().copied().max().unwrap_or(0);
        let avg = if got.is_empty() { 0 } else { got.iter().sum::<i64>() / got.len() as i64 };
        format!(
            "{} random tapper runs, {} gap seeker runs (best {}, average {})",
            Self::RANDOM_RUNS,
            Self::SEEKER_RUNS,
            best,
            avg
        )
    }
}
