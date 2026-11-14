//! `fastsim check forkexits` (tests/sim/test_fork_exits.gd): at a Calm/Wild fork every room
//! variant that hosts one (RoomDef.hosts_fork) plans both exits, on both walls, where nothing
//! kills in their mouths (ExitPlanner.in_mouth: not in a cave's rock). Arrivals as the reaction
//! benchmark makes them (Reaction::arrival heights, both sides), at the scores before the first
//! three fork exits. One more case: the picker never gives a room that hosts no fork a fork exit
//! (and still picks it at other scores).
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{i, result, Check};
use crate::setups::Reaction;

#[derive(Default)]
pub struct ForkExits {
    /// [room index, variant]; index -1 is the picker case.
    _cases: OnceLock<Vec<(i64, &'static str)>>,
}

impl ForkExits {
    /// Arrivals per room variant and fork score.
    pub const COUNT: i64 = 40;
    /// Scores just before a fork exit (FORK_EVERY, not a boss's BOSS_EVERY).
    pub const SCORES: [i64; 3] = [40, 140, 240];

    fn cases(&self) -> &Vec<(i64, &'static str)> {
        self._cases.get_or_init(|| {
            let mut out_ = vec![(-1, "")];
            for (n, def) in RoomCatalog::all().iter().enumerate() {
                if def.boss || !def.hosts_fork {
                    continue;
                }
                if def.variants.is_empty() {
                    out_.push((n as i64, ""));
                }
                for v in def.variants.iter() {
                    out_.push((n as i64, v.id));
                }
            }
            out_
        })
    }

    /// The fork exits planned on each wall with something deadly in the mouth (empty: none).
    pub fn blocked_exits(sim: &GameSim) -> Vec<String> {
        let mut out_ = Vec::new();
        let s = &sim.state;
        let walls = [(0, s.plan_a_y_left, s.plan_b_y_left), (1, s.plan_a_y_right, s.plan_b_y_right)];
        for (side, a, b) in walls {
            for y in [a, b] {
                let mut c = sim.clone_deep();
                if ExitPlanner::in_mouth(&mut c, side, y) {
                    out_.push(format!("side {} {} px", side, y / SimConfig::SUB));
                }
            }
        }
        out_
    }
}

impl ForkExits {
    /// Picks per score and season in the picker case.
    pub const PICKS: i64 = 400;

    /// pick_next from random decks and arrival heights: at a score whose next exit is a fork,
    /// never a room that hosts no fork; one step later such rooms still come up.
    fn picker() -> Value {
        let all = RoomCatalog::all();
        let mut fails = Vec::new();
        let mut at_fork = 0;
        let mut later = 0;
        for score in [40i64, 140, 240, 50, 150, 250] {
            let fork = ExitPlanner::fork_at(score + SimConfig::POINTS_PER_ROOM);
            for season in Seasons::NONE..Seasons::COUNT {
                let mut rng = SimRng::new(score * 1000 + season + 7);
                for k in 0..Self::PICKS {
                    let mut st = SimState::default();
                    st.score = score;
                    st.anchor_y = (130 + (k * 53) % 380) * SimConfig::SUB;
                    st.deck_lo = rng.next_u32() as i64 & rng.next_u32() as i64;
                    let got = RoomCatalog::pick_next(&mut rng, &mut st, -1, season);
                    if got < 0 || all[got as usize].hosts_fork {
                        continue;
                    }
                    if fork {
                        at_fork += 1;
                        if fails.len() < 4 {
                            fails.push(format!(
                                "score {} season {}: picked {}, which hosts no fork, for a fork exit",
                                score, season, all[got as usize].id
                            ));
                        }
                    } else {
                        later += 1;
                    }
                }
            }
        }
        if later == 0 {
            fails.push("no room that hosts no fork was picked at any other score".to_string());
        }
        result(fails, json!({ "forks": 0, "no_fork_at_fork": at_fork, "no_fork_later": later }))
    }
}

impl Check for ForkExits {
    fn name(&self) -> &'static str {
        "forkexits"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_fork_exits.gd:test_both_fork_exits_are_free_in_every_room"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (index, v) = self.cases()[n];
        if index < 0 {
            return Self::picker();
        }
        let id = RoomCatalog::all()[index as usize].id;
        let mut fails = Vec::new();
        let mut forks = 0;
        let mut bad_n = 0;
        for score in Self::SCORES {
            for k in 0..Self::COUNT {
                let sim = Reaction::arrival_at(index, k, v, score);
                if !ExitPlanner::is_fork(&sim, sim.state.plan_at) {
                    continue;
                }
                forks += 1;
                let bad = Self::blocked_exits(&sim);
                if !bad.is_empty() {
                    bad_n += 1;
                }
                if !bad.is_empty() && fails.len() < 4 {
                    fails.push(format!(
                        "{}/{} arrival {} score {} (anchor {} px): fork exit blocked: {}",
                        id,
                        sim.room.variant_id(),
                        k,
                        score,
                        sim.state.anchor_y / SimConfig::SUB,
                        bad.join(", ")
                    ));
                }
            }
        }
        if forks == 0 {
            fails.push(format!("{}/{}: no fork exit planned", id, v));
        }
        if bad_n > 4 {
            fails.push(format!("{}/{}: {} of {} fork plans blocked", id, v, bad_n, forks));
        }
        result(fails, json!({ "forks": forks }))
    }

    fn summary(&self, results: &[Value]) -> String {
        let forks: i64 = results.iter().map(|r| i(&r["forks"])).sum();
        let later: i64 = results.iter().map(|r| i(&r["no_fork_later"])).sum();
        format!(
            "{} fork plans ({} room variants x {} arrivals x scores {:?}), both walls; rooms that host no fork picked {} times off fork exits, never for one",
            forks,
            results.len() - 1,
            Self::COUNT,
            Self::SCORES,
            later
        )
    }
}
