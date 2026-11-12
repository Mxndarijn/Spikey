//! Checks.Searches and its checks (CheckSearches.cs): crawl, gates, isles, rescued. Lists of
//! SurvivalSearch cases that were GDScript tests.
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{result, Check};
use crate::bots::SurvivalSearch;
use crate::setups::Setups;

/// C# `Checks.deaths(search)`: "{cause: n, ...}" in first-seen order.
pub fn deaths(search: &SurvivalSearch) -> String {
    let parts: Vec<String> = search.last_deaths.iter().map(|(k, v)| format!("{}: {}", k, v)).collect();
    format!("{{{}}}", parts.join(", "))
}

/// How far the best line of a search must get.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Through {
    Alive,
    PortalTaken,
    #[allow(dead_code)]
    ExactlyOnePortal,
    PastStart,
}

/// C# `Searches.S`: one SurvivalSearch case.
pub struct S {
    pub label: String,
    pub make: Box<dyn Fn() -> GameSim + Send + Sync>,
    pub ticks: i64,
    pub through: Through,
    pub quick: bool,
}

impl S {
    fn new(label: String, make: Box<dyn Fn() -> GameSim + Send + Sync>, ticks: i64, through: Through, quick: bool) -> S {
        S { label, make, ticks, through, quick }
    }
}

/// C# `Searches.run(n)` for one case.
pub fn run_search(c: &S) -> Value {
    let sim = (c.make)();
    let mut search = SurvivalSearch::new();
    let ok = if c.quick { search.run_quick(&sim, c.ticks) } else { search.run(&sim, c.ticks) };
    let mut fails: Vec<String> = Vec::new();
    if !ok {
        fails.push(format!("{}: all died at tick {} ({})", c.label, search.ticks_survived, deaths(&search)));
        return result(fails, json!({}));
    }
    let got = search.best.as_ref().map(|b| b.state.room_index).unwrap_or(0);
    let through = match c.through {
        Through::PortalTaken => got >= 1,
        Through::ExactlyOnePortal => got == 1,
        Through::PastStart => got > sim.state.room_index,
        Through::Alive => true,
    };
    if !through {
        fails.push(format!("{}: nobody got through the portal (room {})", c.label, got));
    }
    result(fails, json!({}))
}

/// C# `Searches.summary`.
fn searches_summary(results: &[Value]) -> String {
    format!("{} searches", results.len())
}

/// The searches of tests/sim/test_crawl_passable.gd: through the first portal on the seeds where
/// a crawler once covered the way.
#[derive(Default)]
pub struct Crawl {
    _cases: OnceLock<Vec<S>>,
}

impl Crawl {
    pub const SEARCH_TICKS: i64 = 1000;
    pub const SEARCH_CASES: [(&'static str, i64); 3] = [("crawl", 22), ("crawl", 64), ("crabs", 89)];

    fn cases(&self) -> &Vec<S> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<S> {
        let mut out_ = Vec::new();
        for (id, seed) in Self::SEARCH_CASES {
            let index = RoomCatalog::index_of(id);
            out_.push(S::new(
                format!("{} seed {}", id, seed),
                Box::new(move || GameSim::with(seed, RoomCatalog::all()[index as usize].season, index, "")),
                Self::SEARCH_TICKS,
                Through::PortalTaken,
                false,
            ));
        }
        out_
    }
}

impl Check for Crawl {
    fn name(&self) -> &'static str {
        "crawl"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_crawl_passable.gd:test_search_gets_past_the_first_portal"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }
    fn run(&self, n: usize) -> Value {
        run_search(&self.cases()[n])
    }
    fn summary(&self, results: &[Value]) -> String {
        searches_summary(results)
    }
}

/// The searches of tests/sim/test_gates_passable.gd: the once unreachable portals and the quick
/// runs from just before an exit is planned (more seeds here).
#[derive(Default)]
pub struct Gates {
    _cases: OnceLock<Vec<S>>,
}

impl Gates {
    pub const ONCE_IMPOSSIBLE: [(i64, i64); 2] = [(141, 960), (144, 960)];
    pub const SEEDS: i64 = 14;
    pub const QUICK_TICKS: i64 = 290;
    /// More quick-run seeds per variant.
    pub const MORE_SEEDS: i64 = 42;

    fn cases(&self) -> &Vec<S> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<S> {
        let mut out_ = Vec::new();
        for (seed, ticks) in Self::ONCE_IMPOSSIBLE {
            out_.push(S::new(
                format!("seed {}", seed),
                Box::new(move || Setups::practice("gates", seed, "classic")),
                ticks,
                Through::PortalTaken,
                false,
            ));
        }
        let every = SimConfig::POINTS_PER_ROOM;
        let quick = |out_: &mut Vec<S>, seed_value: i64, variant: &'static str, ghost: bool| {
            out_.push(S::new(
                format!("{} seed {} ({})", variant, seed_value, if ghost { "ghost" } else { "open" }),
                Box::new(move || {
                    let mut sim = Setups::practice("gates", seed_value, variant);
                    sim.state.score += every - if ghost { 2 } else { 1 };
                    sim
                }),
                Self::QUICK_TICKS,
                Through::PastStart,
                false,
            ));
        };
        for i in 0..Self::SEEDS * 2 {
            quick(&mut out_, 500 + i * 37, if i < Self::SEEDS { "classic" } else { "single" }, i % 4 != 3);
        }
        for variant in ["classic", "single"] {
            for k in 0..Self::MORE_SEEDS {
                quick(&mut out_, 3000 + k * 41, variant, k % 4 != 3);
            }
        }
        out_
    }
}

impl Check for Gates {
    fn name(&self) -> &'static str {
        "gates"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_gates_passable.gd:test_the_portal_is_reachable"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }
    fn run(&self, n: usize) -> Value {
        run_search(&self.cases()[n])
    }
    fn summary(&self, results: &[Value]) -> String {
        searches_summary(results)
    }
}

/// The searches of tests/sim/test_isles_passable.gd: Floating Isles and Egg Hunt in every variant
/// through the portal from just before an exit is planned (more seeds here).
#[derive(Default)]
pub struct Isles {
    _cases: OnceLock<Vec<S>>,
}

impl Isles {
    pub const ISLES_SEEDS: [i64; 5] = [1, 322, 7, 2024, 31337];
    pub const EGGS_SEEDS: [i64; 2] = [3, 58];
    pub const NEAR_EXIT: i64 = 28;
    pub const PORTAL_TICKS: i64 = 450;
    pub const ISLES_VARIANTS: [&'static str; 3] = ["classic", "drifting", "one-big"];
    pub const EGGS_VARIANTS: [&'static str; 3] = ["classic", "drifting", "golden"];
    /// More seeds for every room variant.
    pub const MORE_SEEDS: i64 = 12;

    fn cases(&self) -> &Vec<S> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<S> {
        let mut out_ = Vec::new();
        let portal = |out_: &mut Vec<S>, id: &'static str, seed: i64, v: &'static str| {
            out_.push(S::new(
                format!("{} {} seed {}", id, v, seed),
                Box::new(move || {
                    let mut sim = Setups::practice(id, seed, v);
                    sim.state.score = Self::NEAR_EXIT;
                    sim
                }),
                Self::PORTAL_TICKS,
                Through::PortalTaken,
                true,
            ));
        };
        let more: Vec<i64> = (0..Self::MORE_SEEDS).map(|k| 400 + k * 53).collect();
        for v in Self::ISLES_VARIANTS {
            for &s in Self::ISLES_SEEDS.iter().chain(more.iter()) {
                portal(&mut out_, "isles", s, v);
            }
        }
        for v in Self::EGGS_VARIANTS {
            for &s in Self::EGGS_SEEDS.iter().chain(more.iter()) {
                portal(&mut out_, "eggs", s, v);
            }
        }
        out_
    }
}

impl Check for Isles {
    fn name(&self) -> &'static str {
        "isles"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_isles_passable.gd:test_isles_lead_through_the_portal"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }
    fn run(&self, n: usize) -> Value {
        run_search(&self.cases()[n])
    }
    fn summary(&self, results: &[Value]) -> String {
        searches_summary(results)
    }
}

/// tests/sim/test_rooms_survivable.gd: rooms SurvivalSearch once proved impossible stay
/// survivable, and the search finds no way for a dead bird. A case is a search, or None for
/// C#'s "dead".
#[derive(Default)]
pub struct Rescued {
    _cases: OnceLock<Vec<Option<S>>>,
}

impl Rescued {
    pub const CASES: [(&'static str, i64, i64); 3] = [
        // Gravity Flip (the search itself used to mix up flipped speeds).
        ("flip", 1000, 300),
        // Saw Ring: wide rings left no way to the wall gap.
        ("sawring", 1000, 600),
        ("sawring", 1154, 900),
    ];

    fn cases(&self) -> &Vec<Option<S>> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<Option<S>> {
        let mut out_ = Vec::new();
        for (id, seed, ticks) in Self::CASES {
            let index = RoomCatalog::index_of(id);
            out_.push(Some(S::new(
                format!("{} seed {}", id, seed),
                Box::new(move || GameSim::with(seed, RoomCatalog::all()[index as usize].season, index, "")),
                ticks,
                Through::Alive,
                false,
            )));
        }
        out_.push(None);
        out_
    }
}

impl Check for Rescued {
    fn name(&self) -> &'static str {
        "rescued"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_rooms_survivable.gd"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }
    fn run(&self, n: usize) -> Value {
        if let Some(c) = &self.cases()[n] {
            return run_search(c);
        }
        // A sim that is already over has no way to survive.
        let mut sim = GameSim::new(1);
        sim.step(true);
        sim.kill(DeathCause::CEILING);
        let found = SurvivalSearch::new().run(&sim, 10);
        let fails = if found {
            vec!["a dead bird cannot survive, but the search found a way".to_string()]
        } else {
            Vec::new()
        };
        result(fails, json!({}))
    }
    fn summary(&self, results: &[Value]) -> String {
        format!("{} searches and a dead bird", results.len() as i64 - 1)
    }
}
