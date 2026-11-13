//! Port of Measure/Bank.cs: the bots of `fastsim measure`, the seed sets, and the snapshot
//! bank (`*.bank.json`, format `flapjaw_bank` 1, docs/BOT_TESTING.md "Files").
use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Instant;

use rayon::prelude::*;
use serde_json::{json, Map, Value};
use sim::prelude::*;

use super::{as_f64, as_i64, json_compact, strat::Strat};
use crate::bots::BlindPlanner;
use crate::human::motor_player::{MotorPlayer, MotorTiers};
use crate::speed::Opts;
use crate::yardstick::bots::{BotSpec, Bots, Copies, Decide};
use crate::yardstick::runs::Run;
use crate::yardstick::stats::round;
use crate::yardstick::survival::{Obs, Set};

/// Bots for `fastsim measure`: every yardstick bot, plus `blind` (the
/// BlindPlanner as `rl review atlas` plays it) with knobs after a colon:
/// `blind:fine=0,lines=4` sets the knobs `rl review atlas --fine 0 --lines 4` sets. Knobs may
/// also be joined with `+` (`blind:fine=0+lines=4`), so a bot list `a,b` can hold such bots.
pub struct MBots;

impl MBots {
    pub fn find(name: &str) -> Result<BotSpec, String> {
        if name == "blind" || name.starts_with("blind:") {
            let mut knobs: Opts = HashMap::new();
            if name.len() > 6 {
                for kv in name[6..].split([',', '+']).map(|s| s.trim()).filter(|s| !s.is_empty()) {
                    let p: Vec<&str> = kv.split('=').collect();
                    if p.len() != 2 {
                        return Err(format!("bad knob '{}' in '{}' (want key=value)", kv, name));
                    }
                    knobs.insert(p[0].to_string(), p[1].to_string());
                }
            }
            // configure() also sets a static (know_exits): run it once here, the same for every run.
            let about = crate::review::configure(&mut BlindPlanner::new(1), &knobs);
            let knobs = Arc::new(knobs);
            return Ok(BotSpec {
                name: name.to_string(),
                about: format!("BlindPlanner [{}]", about),
                copies: Copies::SCRAMBLED,
                make: Arc::new(move |seed: i64| -> Decide {
                    let mut b = BlindPlanner::new(seed);
                    crate::review::configure(&mut b, &knobs);
                    Box::new(move |sim: &GameSim| b.decide(sim))
                }),
            });
        }
        if let Some(rest) = name.strip_prefix("tier:") {
            // A human tier at given knobs: tier:react=R,level=L (human/motor_player.rs, MotorTiers::shared).
            let mut react: f64 = 17.0;
            let mut level: i32 = MotorTiers::DEFAULT_LEVEL;
            for kv in rest.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()) {
                let p: Vec<&str> = kv.split('=').collect();
                if p.len() != 2 {
                    return Err(format!("bad knob '{}' in '{}' (want react=R,level=L)", kv, name));
                }
                if p[0] == "react" {
                    react = super::parse(p[1], "react");
                } else if p[0] == "level" {
                    level = super::parse(p[1], "level");
                } else {
                    return Err(format!("unknown knob '{}' in '{}' (react, level)", p[0], name));
                }
            }
            if level < 0 || level as usize >= MotorTiers::LEVELS.len() {
                return Err(format!("search level {}: 0..{}", level, MotorTiers::LEVELS.len() - 1));
            }
            let m = MotorTiers::shared(react, level);
            return Ok(BotSpec {
                name: name.to_string(),
                about: format!(
                    "MotorPlayer, shared human rules, {}, search level {} ({})",
                    m,
                    level,
                    MBots::level_text(level)
                ),
                copies: Copies::SCRAMBLED,
                make: Arc::new(move |seed: i64| -> Decide {
                    let mut mp = MotorPlayer::new(m, seed, None);
                    Box::new(move |sim: &GameSim| mp.decide(sim))
                }),
            });
        }
        Bots::find(name).ok_or_else(|| {
            format!("no bot '{}' (blind[:k=v,...], tier:react=R,level=L or a yardstick bot)", name)
        })
    }

    /// C# `MotorTiers.level_text(l)`: "16 px x 3", ", free taps" for free tap timing.
    pub fn level_text(l: i32) -> String {
        let (px, speeds, tap_free) = MotorTiers::LEVELS[l as usize];
        format!("{} px x {}{}", px, speeds, if tap_free { ", free taps" } else { "" })
    }
}

/// Seed sets of the protocol (docs/BOT_TESTING.md). Tune on dev, report once
/// on the holdout, check leaks on their own seeds.
pub struct SeedSets;

impl SeedSets {
    pub const DEV: i64 = 10_000;
    pub const HOLDOUT: i64 = 0;
    pub const LEAK: i64 = 900_000;
    pub const HOLDOUT_N: i32 = 400;
}

/// One room visit seen in a run: the tick whose step entered the room (the
/// state before that step is the entry snapshot), the stratum, and how the
/// visit ended. (C# record Visit.)
#[derive(Clone, Debug, PartialEq)]
pub struct Visit {
    pub tick: i64,
    pub tap: bool,
    pub score: i64,
    pub key: String,
    pub died: bool,
    pub censored: bool,
    pub points: i64,
    pub ticks: i64,
    pub ms: f64,
}

impl Visit {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        tick: i64,
        tap: bool,
        score: i64,
        key: &str,
        died: bool,
        censored: bool,
        points: i64,
        ticks: i64,
        ms: f64,
    ) -> Visit {
        Visit { tick, tap, score, key: key.to_string(), died, censored, points, ticks, ms }
    }
}

/// One bank run: the bot's taps (so any port can rebuild every state by
/// replaying them), its outcome and its room visits.
#[derive(Clone, Debug, Default)]
pub struct BankRun {
    pub seed: i64,
    pub season: i64,
    pub points: i64,
    pub ticks: i64,
    pub dead: bool,
    pub ms: f64,
    pub taps: Vec<i64>,
    pub visits: Vec<Visit>,
    pub room: String,
}

/// The snapshot bank (`*.bank.json`, format `flapjaw_bank` 1). Full runs of
/// one bot to death, a point cap or a tick cap, with every room entry.
/// Everything in it is plain data: seed, taps, entry ticks. Rebuilding a
/// state is "new GameSim(seed, season), step(taps contains tick) until the
/// tick", so the C# tool and this port read and write the same file.
#[derive(Clone, Debug)]
pub struct Bank {
    pub bot: String,
    pub about: String,
    pub cap: i64,
    pub point_cap: i64,
    pub gameplay: i64,
    pub first: i64,
    pub runs: Vec<BankRun>,
    pub seconds: f64,
}

impl Default for Bank {
    fn default() -> Self {
        Bank {
            bot: String::new(),
            about: String::new(),
            cap: 0,
            point_cap: 0,
            gameplay: SimConfig::GAMEPLAY_VERSION,
            first: 0,
            runs: Vec::new(),
            seconds: 0.0,
        }
    }
}

fn ms_since(clock: &Instant) -> f64 {
    clock.elapsed().as_secs_f64() * 1000.0
}

impl Bank {
    pub const FORMAT: &'static str = "flapjaw_bank";
    pub const VERSION: i32 = 1;

    /// Stratum of the room the sim just entered: room/variant, plus the score
    /// class. Below PLATEAU the band of ten (spikes still grow), boss rooms
    /// their tier, everything else "p" (the plateau: same rules at any score).
    pub fn key(sim: &GameSim) -> String {
        let name = Run::room_name(sim);
        let s = sim.room.entry_score;
        if sim.room.def().boss {
            return format!("{}@t{}", name, SimConfig::boss_tier(s));
        }
        if s < Strat::PLATEAU {
            return format!("{}@b{}", name, s / 10 * 10);
        }
        format!("{}@p", name)
    }

    /// Plays one run of `bot` and records its visits. Stops at death, `cap`
    /// ticks or the first room entry at or past `point_cap` points (0 = none).
    pub fn play(bot: &BotSpec, seed: i64, cap: i64, point_cap: i64) -> BankRun {
        let mut decide = (bot.make)(seed);
        let mut sim = GameSim::new(seed);
        let mut taps: Vec<i64> = Vec::new();
        let mut r = BankRun { seed, season: sim.season, ..BankRun::default() };
        let clock = Instant::now();
        let mut v_tick: i64 = -1;
        let mut v_score: i64 = 0;
        let mut v_start: i64 = 0;
        let mut v_tap = false;
        let mut v_key: Option<String> = None;
        let mut v_ms: f64 = 0.0;
        while sim.state.tick < cap && !sim.is_over() {
            let t = sim.state.tick;
            let tap = decide(&sim);
            if tap {
                taps.push(t);
            }
            let ri = sim.state.room_index;
            sim.step(tap);
            if sim.state.room_index != ri {
                let now = ms_since(&clock);
                if let Some(k) = &v_key {
                    r.visits.push(Visit::new(
                        v_tick,
                        v_tap,
                        v_score,
                        k,
                        false,
                        false,
                        sim.state.score - v_score,
                        t + 1 - v_start,
                        now - v_ms,
                    ));
                }
                v_tick = t;
                v_tap = tap;
                v_score = sim.state.score;
                v_start = t + 1;
                v_key = Some(Self::key(&sim));
                v_ms = now;
                if point_cap > 0 && sim.state.score >= point_cap {
                    v_key = None;
                    break;
                }
            }
        }
        if let Some(k) = &v_key {
            let now = ms_since(&clock);
            r.visits.push(Visit::new(
                v_tick,
                v_tap,
                v_score,
                k,
                sim.is_over(),
                !sim.is_over(),
                sim.state.score - v_score,
                sim.state.tick - v_start,
                now - v_ms,
            ));
        }
        r.taps = taps;
        r.points = sim.state.score;
        r.ticks = sim.state.tick;
        r.dead = sim.is_over();
        r.room = Run::room_name(&sim);
        r.ms = ms_since(&clock);
        r
    }

    /// C# `make(bot, first, seeds, cap, point_cap, threads, log)`: the runs on rayon's
    /// global pool (`--jobs`), in seed order; `log` prints each finished run to stderr.
    pub fn make(bot: &BotSpec, first: i64, seeds: i32, cap: i64, point_cap: i64, log: bool) -> Bank {
        let mut b = Bank { bot: bot.name.clone(), about: bot.about.clone(), cap, point_cap, first, ..Bank::default() };
        let clock = Instant::now();
        let done = AtomicUsize::new(0);
        let res: Vec<BankRun> = (0..seeds)
            .into_par_iter()
            .map(|i| {
                let r = Self::play(bot, first + i as i64 + 1, cap, point_cap);
                let d = done.fetch_add(1, Ordering::SeqCst) + 1;
                if log {
                    eprintln!(
                        "[{}/{}] seed {}: {} points{}, {} s",
                        d,
                        seeds,
                        first + i as i64 + 1,
                        r.points,
                        if r.dead { "" } else { " (alive)" },
                        crate::yardstick::fmt_num(r.ms / 1000.0, "F0")
                    );
                }
                r
            })
            .collect();
        b.runs = res;
        b.seconds = clock.elapsed().as_secs_f64();
        b
    }

    /// `new GameSim(r.seed, r.season)`.
    fn fresh(r: &BankRun) -> GameSim {
        GameSim::with(r.seed, r.season, -1, "")
    }

    /// Rebuilds the state before the step at `tick` of run `r`.
    pub fn replay(r: &BankRun, tick: i64) -> GameSim {
        let mut sim = Self::fresh(r);
        let set: HashSet<i64> = r.taps.iter().copied().collect();
        while sim.state.tick < tick {
            let tap = set.contains(&sim.state.tick);
            sim.step(tap);
        }
        sim
    }

    /// The states before each of `ticks` of run `r`, in one replay.
    pub fn replay_all(r: &BankRun, ticks: impl IntoIterator<Item = i64>) -> HashMap<i64, GameSim> {
        let want: BTreeSet<i64> = ticks.into_iter().collect();
        let mut res = HashMap::new();
        let mut sim = Self::fresh(r);
        let set: HashSet<i64> = r.taps.iter().copied().collect();
        for t in want {
            while sim.state.tick < t {
                let tap = set.contains(&sim.state.tick);
                sim.step(tap);
            }
            res.insert(t, sim.clone_deep());
        }
        res
    }

    // ----------------------------------------------------------------- files

    pub fn to_json(&self) -> Value {
        let mut runs: Vec<Value> = Vec::new();
        for r in &self.runs {
            let mut vis: Vec<Value> = Vec::new();
            for v in &r.visits {
                let end = if v.died {
                    1
                } else if v.censored {
                    2
                } else {
                    0
                };
                vis.push(json!([
                    v.tick,
                    if v.tap { 1 } else { 0 },
                    v.score,
                    v.key,
                    end,
                    v.points,
                    v.ticks,
                    round(v.ms, 1)
                ]));
            }
            let mut o = Map::new();
            o.insert("seed".into(), r.seed.into());
            o.insert("season".into(), r.season.into());
            o.insert("points".into(), r.points.into());
            o.insert("dead".into(), r.dead.into());
            o.insert("ticks".into(), r.ticks.into());
            o.insert("room".into(), r.room.clone().into());
            o.insert("ms".into(), round(r.ms, 1).into());
            o.insert("taps".into(), Value::Array(r.taps.iter().map(|&t| Value::from(t)).collect()));
            o.insert("visits".into(), Value::Array(vis));
            runs.push(Value::Object(o));
        }
        let mut o = Map::new();
        o.insert("format".into(), Self::FORMAT.into());
        o.insert("version".into(), Self::VERSION.into());
        o.insert("gameplay_version".into(), self.gameplay.into());
        o.insert("bot".into(), self.bot.clone().into());
        o.insert("about".into(), self.about.clone().into());
        o.insert("cap".into(), self.cap.into());
        o.insert("point_cap".into(), self.point_cap.into());
        o.insert("first_seed".into(), (self.first + 1).into());
        o.insert("seeds".into(), (self.runs.len() as i64).into());
        o.insert("seconds".into(), round(self.seconds, 1).into());
        o.insert(
            "visit_columns".into(),
            "tick (state before this tick's step is the entry snapshot), tap at that tick, score after entry, stratum, \
             end (0 lived, 1 died, 2 cut by the cap), points, ticks, ms"
                .into(),
        );
        o.insert("runs".into(), Value::Array(runs));
        Value::Object(o)
    }

    pub fn save(&self, path: &str) -> Result<(), String> {
        super::create_parent(path)?;
        std::fs::write(path, json_compact(&self.to_json()) + "\n").map_err(|e| format!("{}: {}", path, e))
    }

    pub fn load(path: &str) -> Result<Bank, String> {
        if !std::path::Path::new(path).is_file() {
            return Err(format!("no bank {}", path));
        }
        let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {}", path, e))?;
        let o: Value =
            serde_json::from_str(text.trim_start_matches('\u{feff}')).map_err(|e| format!("{}: {}", path, e))?;
        if o["format"].as_str() != Some(Self::FORMAT) {
            return Err(format!("{}: not a {} file", path, Self::FORMAT));
        }
        let bad = |k: &str| format!("{}: bad or missing '{}'", path, k);
        let s = |v: &Value| v.as_str().unwrap_or("").to_string();
        let mut b = Bank {
            bot: s(&o["bot"]),
            about: s(&o["about"]),
            cap: as_i64(&o["cap"]).ok_or_else(|| bad("cap"))?,
            point_cap: as_i64(&o["point_cap"]).ok_or_else(|| bad("point_cap"))?,
            gameplay: as_i64(&o["gameplay_version"]).ok_or_else(|| bad("gameplay_version"))?,
            first: as_i64(&o["first_seed"]).ok_or_else(|| bad("first_seed"))? - 1,
            seconds: as_f64(&o["seconds"]).unwrap_or(0.0),
            runs: Vec::new(),
        };
        if b.gameplay != SimConfig::GAMEPLAY_VERSION {
            eprintln!("warning: {} is gameplay {}, this build is {}", path, b.gameplay, SimConfig::GAMEPLAY_VERSION);
        }
        let empty = Vec::new();
        for rn in o["runs"].as_array().ok_or_else(|| bad("runs"))? {
            let mut r = BankRun {
                seed: as_i64(&rn["seed"]).ok_or_else(|| bad("seed"))?,
                season: as_i64(&rn["season"]).ok_or_else(|| bad("season"))?,
                points: as_i64(&rn["points"]).ok_or_else(|| bad("points"))?,
                dead: rn["dead"].as_bool().ok_or_else(|| bad("dead"))?,
                ticks: as_i64(&rn["ticks"]).ok_or_else(|| bad("ticks"))?,
                room: s(&rn["room"]),
                ms: as_f64(&rn["ms"]).unwrap_or(0.0),
                taps: rn["taps"]
                    .as_array()
                    .ok_or_else(|| bad("taps"))?
                    .iter()
                    .map(|t| as_i64(t).ok_or_else(|| bad("taps")))
                    .collect::<Result<Vec<i64>, String>>()?,
                visits: Vec::new(),
            };
            for vn in rn["visits"].as_array().unwrap_or(&empty) {
                let v = vn.as_array().ok_or_else(|| bad("visits"))?;
                let n = |i: usize| v.get(i).and_then(as_i64).ok_or_else(|| bad("visits"));
                let end = n(4)?;
                r.visits.push(Visit::new(
                    n(0)?,
                    n(1)? == 1,
                    n(2)?,
                    v.get(3).and_then(|x| x.as_str()).ok_or_else(|| bad("visits"))?,
                    end == 1,
                    end == 2,
                    n(5)?,
                    n(6)?,
                    v.get(7).and_then(as_f64).ok_or_else(|| bad("visits"))?,
                ));
            }
            b.runs.push(r);
        }
        Ok(b)
    }

    /// The runs as a survival set (Survival.describe), points from 0.
    /// C# default: name = bot + "_bank".
    pub fn as_set(&self, name: Option<&str>) -> Set {
        Set {
            name: name.map(|s| s.to_string()).unwrap_or_else(|| format!("{}_bank", self.bot)),
            source: "bank".to_string(),
            cap: self.cap,
            runs: self.runs.iter().map(|r| Obs::new(r.seed, r.points, r.dead)).collect(),
            approx: false,
        }
    }
}
