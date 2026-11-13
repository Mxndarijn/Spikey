//! Checks.Reach (Checks.cs), tests/sim/test_exits_reachable.gd: the exit at 40 of seed
//! 3392377610 (v21): in Stalactite Run's floor variant the fangs followed the bird, the exit
//! could be planned anywhere, and a bird that was high when the exit opened low had no way in.
//! Now the exits are planned at room start and the fangs and walls steer to them: on several
//! random lines per seed (a slow and a fast player alike) the exit can always still be taken
//! once its ghost shows.
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{i, result, Check};
use crate::bots::SurvivalSearch;
use crate::dotnet_random::DotnetRandom;
use crate::setups::Setups;

#[derive(Default)]
pub struct Reach {
    _cases: OnceLock<Vec<(&'static str, &'static str, i64)>>,
}

impl Reach {
    pub const SEEDS_EACH: i64 = 8;
    pub const LINES: i64 = 3;
    pub const ROOMS: [&'static str; 6] = ["stalac", "gates", "crates", "gifts", "lava", "isles"];

    fn cases(&self) -> &Vec<(&'static str, &'static str, i64)> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<(&'static str, &'static str, i64)> {
        let mut out_ = Vec::new();
        for id in Self::ROOMS {
            let def = &RoomCatalog::all()[RoomCatalog::index_of(id) as usize];
            let ids: Vec<&'static str> =
                if def.variants.is_empty() { vec![""] } else { def.variants.iter().map(|v| v.id).collect() };
            for v in ids {
                for s in 0..Self::SEEDS_EACH {
                    out_.push((id, v, 1000 + s * 61));
                }
            }
        }
        out_
    }

    /// Plays random surviving lines until `until`, at most `max` ticks. `rnd` is the one
    /// Random every search picks with (C# shares the reference); it is handed back after each.
    fn advance(sim: &mut GameSim, rnd: &mut Option<DotnetRandom>, until: impl Fn(&GameSim) -> bool, max: i64) -> bool {
        let mut done: i64 = 0;
        while !until(sim) && done < max {
            let mut s = SurvivalSearch::new();
            s.pick = rnd.take();
            let ok = s.run(sim, 360);
            *rnd = s.pick.take();
            if !ok {
                return false;
            }
            let n = 120.min(s.best_inputs.len());
            let mut k = 0;
            while k < n && !until(sim) {
                sim.step(s.best_inputs[k] == 1);
                done += 1;
                k += 1;
            }
        }
        until(sim)
    }
}

impl Check for Reach {
    fn name(&self) -> &'static str {
        "reach"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_exits_reachable.gd:test_every_exit_can_be_reached_when_it_opens"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (id, variant, seed_value) = self.cases()[n];
        let mut fails = Vec::new();
        let mut opened: i64 = 0;
        for line in 0..Self::LINES {
            let mut sim = Setups::practice(id, seed_value, if variant.is_empty() { "classic" } else { variant });
            // From the ghost: the player sees where the exit opens one bounce ahead. Some line
            // must go through it, with two more crossings to spare (solid islands turn the bird
            // round). A bird that only lives by bouncing over the top spike of the exit's wall
            // doesn't count.
            let mut rnd = Some(DotnetRandom::new((seed_value as i32) * 7 + line as i32));
            if !Self::advance(&mut sim, &mut rnd, |g| g.state.exit_preview, 1500) {
                continue;
            }
            opened += 1;
            let room = sim.state.room_index;
            let crossing = (sim.room.wall_right() - sim.room.wall_left()) / SimConfig::SPEED_X;
            let mut s = SurvivalSearch::new();
            s.run(&sim, sim.steps_to_exit(sim.state.exit_side) + 2 * crossing + 10);
            if s.best.as_ref().is_none_or(|b| b.state.room_index == room) {
                fails.push(format!(
                    "{}/{} seed {} line {}: no way into the exit at {} px from the ghost (bird at {} px)",
                    id,
                    variant,
                    seed_value,
                    line,
                    sim.state.exit_a_y / SimConfig::SUB,
                    sim.state.y / SimConfig::SUB
                ));
            }
        }
        result(fails, json!({ "opened": opened }))
    }

    fn summary(&self, results: &[Value]) -> String {
        let opened: i64 = results.iter().map(|r| i(&r["opened"])).sum();
        format!(
            "{} ghosts shown on {} random lines per seed, {} seeds per variant of {}",
            opened,
            Self::LINES,
            Self::SEEDS_EACH,
            Self::ROOMS.join(", ")
        )
    }
}
