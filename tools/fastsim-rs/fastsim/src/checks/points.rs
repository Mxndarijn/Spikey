//! Checks.Points (Checks.cs), was tests/sim/test_room_points_cap.gd: the gap seeker never
//! scores more than a room's cap in one room (practice seeds of every room variant, and full
//! runs with a revive).
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{i, result, Check};
use crate::bots::SimBots;

/// How a case's sim is made (C# `Func<GameSim>`).
#[derive(Clone, Copy)]
enum Maker {
    /// `new GameSim(seed_value, rooms[i].season, i, v)`.
    Practice { seed_value: i64, index: i64, variant: &'static str },
    /// `new GameSim(seed_value)`.
    Run { seed_value: i64 },
}

impl Maker {
    fn make(self) -> GameSim {
        match self {
            Maker::Practice { seed_value, index, variant } => {
                GameSim::with(seed_value, RoomCatalog::all()[index as usize].season, index, variant)
            }
            Maker::Run { seed_value } => GameSim::new(seed_value),
        }
    }
}

#[derive(Default)]
pub struct Points {
    _cases: OnceLock<Vec<(String, Maker, bool)>>,
}

impl Points {
    /// Practice seeds per variant and revive runs (the GD test played 3 and 40).
    pub const SEEDS_PER_VARIANT: i64 = 12;
    pub const REVIVE_RUNS: i64 = 160;
    pub const MAX_TICKS: i64 = 6000;

    fn cases(&self) -> &Vec<(String, Maker, bool)> {
        self._cases.get_or_init(Self::make)
    }

    /// [label, sim maker, revive]: every room x ("" + each variant) x seed, then the revive runs.
    fn make() -> Vec<(String, Maker, bool)> {
        let mut out_ = Vec::new();
        let rooms = RoomCatalog::all();
        for index in 0..rooms.len() {
            let def = &rooms[index];
            let mut variants: Vec<&'static str> = vec![""];
            variants.extend(def.variants.iter().map(|v| v.id));
            for variant in variants {
                for s in 0..Self::SEEDS_PER_VARIANT {
                    let seed_value = 1000 + index as i64 * 37 + s;
                    out_.push((
                        format!("{}/{} seed {}", def.id, variant, s),
                        Maker::Practice { seed_value, index: index as i64, variant },
                        false,
                    ));
                }
            }
        }
        let mut seeds = SimRng::new(4242);
        for run in 0..Self::REVIVE_RUNS {
            let seed_value = seeds.next_u32();
            out_.push((format!("run {}", run), Maker::Run { seed_value }, true));
        }
        out_
    }

    fn cap(sim: &GameSim) -> i64 {
        // A boss room's exit opens after BOSS_POINTS bounces there.
        if sim.room.def().boss {
            SimConfig::BOSS_POINTS
        } else {
            SimConfig::POINTS_PER_ROOM
        }
    }
}

impl Check for Points {
    fn name(&self) -> &'static str {
        "points"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_room_points_cap.gd:test_"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (label, maker, revive) = &self.cases()[n];
        let revive = *revive;
        let mut sim = maker.make();
        let mut bot = SimRng::new(7);
        let mut room_index = sim.state.room_index;
        let mut entry_score = sim.state.score;
        let mut cap = Self::cap(&sim);
        let mut full: i64 = 0;
        let mut fails = Vec::new();
        while sim.state.tick < Self::MAX_TICKS {
            if sim.is_over() && !(revive && sim.can_revive() && sim.revive()) {
                break;
            }
            let tap = SimBots::gap_seeker(&sim, &mut bot);
            sim.step(tap);
            if sim.state.room_index != room_index {
                if sim.state.score - entry_score == cap {
                    full += 1;
                }
                room_index = sim.state.room_index;
                entry_score = sim.state.score;
                cap = Self::cap(&sim);
            }
            let gained = sim.state.score - entry_score;
            if gained > cap || sim.room.points > cap {
                fails.push(format!("{}: {} points in one room (tick {})", label, gained, sim.state.tick));
                break;
            }
        }
        result(fails, json!({ "full": if revive { 0 } else { full } }))
    }

    /// The bot reaches the cap in many rooms (else the check proves little).
    fn combine(&self, results: &[Value]) -> Vec<String> {
        let full: i64 = results.iter().map(|r| i(&r["full"])).sum();
        if full > RoomCatalog::all().len() as i64 {
            Vec::new()
        } else {
            vec![format!("the bot reaches the cap in many rooms: only {} stays did", full)]
        }
    }

    fn summary(&self, results: &[Value]) -> String {
        let full: i64 = results.iter().map(|r| i(&r["full"])).sum();
        format!(
            "{} runs ({} seeds per room variant, {} with a revive), {} stays hit the cap",
            results.len(),
            Self::SEEDS_PER_VARIANT,
            Self::REVIVE_RUNS,
            full
        )
    }
}
