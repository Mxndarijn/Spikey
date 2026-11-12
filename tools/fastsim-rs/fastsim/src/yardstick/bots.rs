//! Port of Yardstick/Bots.cs: the bots the yardstick knows.
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, OnceLock};

use sim::prelude::*;

use crate::bots::{BlindPlanner, PlannerBot, SimBots, SurvivalSearch};

/// A fresh decide function for one run: called once per tick, before sim.step(), it returns
/// whether to tap. It must not step or change the sim (clone it to look ahead).
pub type Decide = Box<dyn FnMut(&GameSim) -> bool + Send>;
/// `make(seed)`.
pub type Make = Arc<dyn Fn(i64) -> Decide + Send + Sync>;

/// C# record BotSpec(name, about, copies, make).
#[derive(Clone)]
pub struct BotSpec {
    pub name: String,
    pub about: String,
    pub copies: &'static str,
    pub make: Make,
}

impl BotSpec {
    pub fn peeks(&self) -> bool {
        self.copies == Copies::REAL
    }
}

pub struct Copies;
impl Copies {
    pub const REAL: &'static str = "real";
    pub const SCRAMBLED: &'static str = "scrambled";
    pub const NONE: &'static str = "none";
    /// Scrambled copies that still leak some hidden draws.
    pub const LEAKY: &'static str = "scrambled (leaky)";
}

/// The bots the yardstick knows (C# static class Bots). A new bot family plugs in from its own
/// file: C# uses a ModuleInitializer calling `Bots.add`; here `builtins()` calls the family's
/// `yardstick_bots()` (`crate::human::yardstick_bots`). A family with levels adds one name per
/// level ("human:good").
///
/// Not ported (left out of the registry): `honest-v1` (HonestBot.cs), WorldBots.cs and the RL
/// policy tiers (`add_rl`, tools/rlbot).
pub struct Bots;

struct Registry {
    all: BTreeMap<String, BotSpec>,
    builtins: bool,
}

fn registry() -> &'static Mutex<Registry> {
    static R: OnceLock<Mutex<Registry>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(Registry { all: BTreeMap::new(), builtins: false }))
}

impl Bots {
    pub fn add(b: BotSpec) {
        registry().lock().unwrap().all.insert(b.name.clone(), b);
    }

    /// Every bot, by name (C# OrderBy(name); here ordinal order).
    pub fn all() -> Vec<BotSpec> {
        Self::builtins();
        registry().lock().unwrap().all.values().cloned().collect()
    }

    pub fn find(name: &str) -> Option<BotSpec> {
        Self::builtins();
        registry().lock().unwrap().all.get(name).cloned()
    }

    /// `rl:all` and other `family:all` names: every bot of that family, in
    /// tier order when the names are tiers.
    pub fn pick(list: &str) -> Result<Vec<BotSpec>, String> {
        let mut out_ = Vec::new();
        for raw in list.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()) {
            if raw.ends_with(":all") {
                let fam = &raw[..raw.len() - 3];
                let mut group: Vec<BotSpec> = Self::all().into_iter().filter(|b| b.name.starts_with(fam)).collect();
                group.sort_by_key(|b| Self::tier_order(&b.name));
                out_.extend(group);
                continue;
            }
            match Self::find(raw) {
                Some(spec) => out_.push(spec),
                None => {
                    let known: Vec<String> = Self::all().into_iter().map(|b| b.name).collect();
                    return Err(format!("no bot '{}' (known: {})", raw, known.join(", ")));
                }
            }
        }
        Ok(out_)
    }

    /// Tiers.NAMES (RL/Tiers.cs).
    pub const TIER_NAMES: [&'static str; 5] = ["beginner", "normal", "good", "expert", "beast"];

    fn tier_order(name: &str) -> i32 {
        let last = match name.rfind(':') {
            Some(i) => &name[i + 1..],
            None => name,
        };
        match Self::TIER_NAMES.iter().position(|t| *t == last) {
            Some(i) => i as i32,
            None => 99,
        }
    }

    fn builtins() {
        {
            let mut r = registry().lock().unwrap();
            if r.builtins {
                return;
            }
            r.builtins = true;
        }
        // C# ModuleInitializers (MotorPlayer.Register) add these before the builtins.
        for b in crate::human::yardstick_bots() {
            Self::add(b);
        }
        Self::add(spec(
            "gap",
            "SimBots.gap_seeker: aims at the biggest gap of the wall ahead, no look-ahead",
            Copies::NONE,
            |seed| {
                let mut rng = SimRng::new(seed);
                Box::new(move |sim: &GameSim| SimBots::gap_seeker(sim, &mut rng))
            },
        ));
        Self::add(spec(
            "planner",
            "PlannerBot: 4 random rollouts of 120 ticks on a copy of the real sim",
            Copies::REAL,
            |seed| {
                let mut b = PlannerBot::new(seed, 120, 4);
                Box::new(move |sim: &GameSim| b.decide(sim))
            },
        ));
        Self::add(spec(
            "search",
            "SurvivalSearch every 30 ticks, 240 ticks ahead on a copy of the real sim (an oracle)",
            Copies::REAL,
            |_seed| {
                let mut b = SearchBot::new();
                Box::new(move |sim: &GameSim| b.decide(sim))
            },
        ));
        Self::add(spec(
            "honest",
            "review's BlindPlanner (651f45d): beam on one copy with every hidden draw replaced, horizon 200, \
             110 past the bounce, margin 10, re-plan every 4",
            Copies::SCRAMBLED,
            |seed| {
                let mut b = BlindPlanner::new(seed);
                b.horizon = 200;
                b.past = 110;
                b.margin = 10;
                Box::new(move |sim: &GameSim| b.decide(sim))
            },
        ));
        // Not ported: "honest-v1" (HonestBot.cs, Copies::LEAKY) and add_rl() (the RL tiers).
    }
}

fn spec(name: &str, about: &str, copies: &'static str, make: impl Fn(i64) -> Decide + Send + Sync + 'static) -> BotSpec {
    BotSpec { name: name.to_string(), about: about.to_string(), copies, make: Arc::new(make) }
}

/// SurvivalSearch as a player: searches `AHEAD` ticks on a copy of the real
/// sim and plays the first `EVERY` taps of the best line, then searches again.
/// It sees the future, so it is the ceiling a planner can reach.
pub struct SearchBot {
    _plan: Vec<u8>,
    _at: i32,
}

impl Default for SearchBot {
    fn default() -> Self {
        Self::new()
    }
}

impl SearchBot {
    pub const EVERY: i64 = 30;
    pub const AHEAD: i64 = 240;

    pub fn new() -> SearchBot {
        SearchBot { _plan: Vec::new(), _at: 0 }
    }

    pub fn decide(&mut self, sim: &GameSim) -> bool {
        if !sim.state.started {
            return true;
        }
        if self._at as usize >= self._plan.len() || self._at as i64 >= Self::EVERY {
            let mut s = SurvivalSearch::new();
            self._plan = if s.run_quick(sim, Self::AHEAD) { s.best_inputs.clone() } else { Vec::new() };
            self._at = 0;
        }
        if (self._at as usize) < self._plan.len() {
            let v = self._plan[self._at as usize];
            self._at += 1;
            v == 1
        } else {
            false
        }
    }
}
