//! Checks.Arrival (Checks.cs), was tests/sim/test_arrival_reaction.gd (ArrivalBench): out of a
//! portal a 0.75 s reaction is never killed by the room, and at 1 s at most MAX_NO_WAY arrivals
//! leave no way to live; every room and every variant on its own. Plus the parts of Reaction.cs
//! it uses (`Reaction::arrival` is in setups.rs).
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{i, result, Check};
use crate::bots::{PlannerBot, SurvivalSearch};
use crate::setups::Reaction;

/// Reaction.cs: the benchmark thresholds, `play` and `forced`.
impl Reaction {
    #[allow(dead_code)]
    pub const AFTER: i64 = 120;
    /// The benchmark, as ArrivalBench: at EARLY_DELAY (0.75 s) no arrival may leave no way to
    /// live; at SimConfig.ARRIVAL_BLIND (1 s) at most MAX_EXTRA_PCT of all arrivals may die that
    /// an instant reaction survives, and in no room may more than MAX_EXTRA_PCT leave no way to live.
    pub const EARLY_DELAY: i64 = 45;
    #[allow(dead_code)]
    pub const MAX_EXTRA_PCT: i64 = 2;
    pub const MAX_NO_WAY: i64 = 0;

    /// For `delay` ticks the player only holds its height, then `bot` plays on, to `cap` ticks.
    /// (-1, "") when the bird lives.
    pub fn play(mut sim: GameSim, delay: i64, bot: &mut PlannerBot, cap: i64) -> (i64, String) {
        let y0 = sim.state.y;
        let mut n = 0;
        while n < cap && !sim.is_over() {
            let tap = if n < delay {
                let g = sim.room.gravity;
                (sim.state.y - y0) * g > 0 && sim.state.vy * g >= 0
            } else {
                bot.decide(&sim)
            };
            sim.step(tap);
            n += 1;
        }
        if !sim.is_over() {
            return (-1, String::new());
        }
        (
            n,
            DeathCause::NAMES[sim.state.death_cause as usize].to_string() + if n <= delay { "@blind" } else { "@play" },
        )
    }

    /// Whether a death after holding `delay` ticks was forced: SurvivalSearch finds no way to
    /// live to `cap` from the moment the player reacts (or the bird already died while holding).
    pub fn forced(at_arrival: &GameSim, delay: i64, cap: i64) -> bool {
        let mut c = at_arrival.clone_deep();
        let y0 = c.state.y;
        for _ in 0..delay {
            let g = c.room.gravity;
            let tap = (c.state.y - y0) * g > 0 && c.state.vy * g >= 0;
            c.step(tap);
            if c.is_over() {
                return true;
            }
        }
        !SurvivalSearch::new().run(&c, cap - delay)
    }
}

#[derive(Default)]
pub struct Arrival {
    _cases: OnceLock<Vec<(i64, &'static str)>>,
}

impl Arrival {
    /// Arrivals per room variant (the GD test played 8).
    pub const COUNT: i64 = 32;
    /// test_arrival_reaction.gd: the lighter PlannerBot. Only its deaths are searched, and a
    /// death with no way to live kills every bot, so the result does not hang on the bot.
    pub const AFTER: i64 = 120;
    pub const HORIZON: i64 = 45;
    pub const ROLLOUTS: i64 = 2;

    fn cases(&self) -> &Vec<(i64, &'static str)> {
        self._cases.get_or_init(Self::make)
    }

    /// ArrivalBench.cases(): each variant of a room on its own, or just the room ("") when it has none.
    fn make() -> Vec<(i64, &'static str)> {
        let mut out_ = Vec::new();
        let rooms = RoomCatalog::all();
        for index in 0..rooms.len() {
            if rooms[index].variants.is_empty() {
                out_.push((index as i64, ""));
            }
            for v in &rooms[index].variants {
                out_.push((index as i64, v.id));
            }
        }
        out_
    }

    /// ArrivalBench.play(..., check_forced = true) at EARLY_DELAY and at
    /// SimConfig.ARRIVAL_BLIND: arrivals the bot dies in with no way to live.
    fn forced(index: i64, variant: &str, delay: i64) -> i64 {
        let mut n = 0;
        for i in 0..Self::COUNT {
            let at = Reaction::arrival(index, i, variant);
            let mut bot = PlannerBot::new(i + 1, Self::HORIZON, Self::ROLLOUTS);
            let (tick, _) = Reaction::play(at.clone_deep(), delay, &mut bot, delay + Self::AFTER);
            if tick >= 0 && Reaction::forced(&at, delay, delay + Self::AFTER) {
                n += 1;
            }
        }
        n
    }
}

impl Check for Arrival {
    fn name(&self) -> &'static str {
        "arrival"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_arrival_reaction.gd:test_every_room_allows_a_slow_reaction_out_of_a_portal"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (index, variant) = self.cases()[n];
        let def = &RoomCatalog::all()[index as usize];
        let id = if variant.is_empty() { def.id.to_string() } else { format!("{}/{}", def.id, variant) };
        let early = Self::forced(index, variant, Reaction::EARLY_DELAY);
        let late = Self::forced(index, variant, SimConfig::ARRIVAL_BLIND);
        let mut fails = Vec::new();
        if early > 0 {
            fails.push(format!("a 0.75 s reaction is killed in: {} ({} of {})", id, early, Self::COUNT));
        }
        result(fails, json!({ "id": id, "total": Self::COUNT, "no_way": late }))
    }

    /// The 1 s benchmark over every room and variant together.
    fn combine(&self, results: &[Value]) -> Vec<String> {
        let total: i64 = results.iter().map(|r| i(&r["total"])).sum();
        let no_way: i64 = results.iter().map(|r| i(&r["no_way"])).sum();
        if no_way > Reaction::MAX_NO_WAY {
            let mut worst: Vec<&Value> = results.iter().filter(|r| i(&r["no_way"]) > 0).collect();
            // OrderByDescending is a stable sort.
            worst.sort_by(|a, b| i(&b["no_way"]).cmp(&i(&a["no_way"])));
            let worst: Vec<String> = worst
                .iter()
                .take(12)
                .map(|r| format!("{} {}", r["id"].as_str().unwrap_or(""), i(&r["no_way"])))
                .collect();
            return vec![format!(
                "a 1 s reaction leaves no way to live in {} of {} arrivals (most: {})",
                no_way,
                total,
                worst.join(", ")
            )];
        }
        Vec::new()
    }

    fn summary(&self, results: &[Value]) -> String {
        let total: i64 = results.iter().map(|r| i(&r["total"])).sum();
        let no_way: i64 = results.iter().map(|r| i(&r["no_way"])).sum();
        format!(
            "{} rooms/variants x {} arrivals, no way to live at 1 s in {} of {} ({}%, must be {}), the bird anywhere in the exit",
            results.len(),
            Self::COUNT,
            no_way,
            total,
            crate::human::fmt_f(100.0 * no_way as f64 / G::maxi(1, total) as f64, 2),
            Reaction::MAX_NO_WAY
        )
    }
}
