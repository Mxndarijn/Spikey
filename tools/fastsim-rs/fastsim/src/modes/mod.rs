//! Program.cs: the modes search, searchruns, rooms, runs, reaction, odds and scan (the mode
//! dispatch, Targets with --variant, Summary.print, the JSON report and --out). C# splits the
//! seeds over worker processes and merges their JSON in seed order; here one rayon pool plays
//! every (room, seed) and keeps the results in index order, so the report is the same.
//!   fastsim-rs search [seeds] [room] [ticks]        can anyone survive each room?
//!   fastsim-rs searchruns [seeds] [ticks]           full runs through the portals
//!   fastsim-rs rooms [seeds] [room]                 PlannerBot per room
//!   fastsim-rs runs [seeds]                         PlannerBot full runs
//!   fastsim-rs reaction [arrivals] [room] [delays]  portal arrivals, slow vs instant reaction
//!   fastsim-rs odds [runs] [delays]                 real runs, every arrival at each reaction
//!   fastsim-rs scan [room] [delay] [seeds]          entry heights with no way to live
//! Options: --out <file.json>, --first <n>, --variant <id>|all, --priority (printed only).
mod reaction;
pub mod variants;

use std::time::Instant;

use rayon::prelude::*;
use serde_json::{json, Map, Value};
use sim::prelude::*;

use crate::bots::{PlannerBot, SurvivalSearch};
use crate::setups::Reaction;
use crate::speed::Opts;
use crate::yardstick::{fmt_num, json_pretty};

pub fn run(mode: &str, pos: &[String], opts: &Opts) -> i32 {
    // C#'s pos holds the mode word first: P(i, d) is pos[i - 1] here.
    let p = |i: usize, d: &str| -> String { pos.get(i - 1).cloned().unwrap_or_else(|| d.to_string()) };
    let priority = opts.get("priority").map(|s| s.to_lowercase()).unwrap_or_else(|| "belownormal".to_string());
    let jobs = rayon::current_num_threads() as i64;
    let first: i64 = opts.get("first").map(|v| v.parse().expect("--first")).unwrap_or(0);
    RoomCatalog::all();
    RoomCatalog::first_index();
    let targets = Targets { variant: opts.get("variant").cloned().unwrap_or_default() };
    if targets.variant != "" {
        if mode != "search" && mode != "rooms" && mode != "reaction" && mode != "scan" {
            eprintln!("--variant works with the search, rooms, reaction and scan modes only");
            return 2;
        }
        let filter = if mode == "scan" { p(1, "*") } else { p(2, "*") };
        if targets.pick(&filter, mode == "reaction").is_empty() {
            eprintln!("no room matching '{}' has a variant '{}'", filter, targets.variant);
            for d in RoomCatalog::all() {
                if !d.variants.is_empty() && Targets::matches(d, &filter, mode == "reaction") {
                    let ids: Vec<&str> = d.variants.iter().map(|v| v.id).collect();
                    eprintln!("  {}: {}", d.id, ids.join(", "));
                }
            }
            return 2;
        }
    }

    let clock = Instant::now();
    if mode == "scan" {
        return Reaction::scan(&targets, &p(1, "ghostdoors"), p(2, "45").parse().expect("delay"), p(3, "4").parse().expect("seeds"));
    }
    let seeds: i64 = p(
        1,
        if mode == "search" || mode == "searchruns" {
            "64"
        } else if mode == "reaction" {
            "60"
        } else {
            "4"
        },
    )
    .parse()
    .expect("seeds");
    let mut report = match mode {
        "search" => Modes::search_rooms(&targets, seeds, &p(2, "*"), p(3, "1500").parse().expect("ticks"), first),
        "searchruns" => Modes::search_runs(seeds, p(2, "16000").parse().expect("ticks"), first),
        "rooms" => Modes::planner_rooms(&targets, seeds, &p(2, "*"), first),
        "runs" => Modes::planner_runs(seeds, first),
        "reaction" => Reaction::rooms(&targets, seeds, &p(2, "*"), &p(3, ""), first),
        "odds" => Reaction::odds(seeds, &p(2, ""), first),
        _ => {
            eprintln!("unknown mode {}", mode);
            return 2;
        }
    };
    let secs = clock.elapsed().as_secs_f64();
    report["seconds"] = json!((secs * 10.0).round_ties_even() / 10.0);
    if let Some(out_path) = opts.get("out") {
        if let Err(e) = std::fs::write(out_path, json_pretty(&report)) {
            eprintln!("cannot write {}: {}", out_path, e);
            return 2;
        }
    }
    let exit = if mode == "reaction" || mode == "odds" { Reaction::print(&targets, &report) } else { Summary::print(&targets, &report) };
    println!(
        "fastsim {}: {} seeds in {:.1} s ({} workers, {} priority)",
        mode,
        seeds,
        clock.elapsed().as_secs_f64(),
        jobs.min(seeds),
        priority
    );
    exit
}

/// .NET `{x,w}` (right-aligned) for any displayable value.
pub(crate) fn pad_left(s: &str, w: usize) -> String {
    format!("{:>w$}", s, w = w)
}

/// The rooms a per-room mode plays, and with --variant, which variant of each.
pub struct Targets {
    /// "" (the drawn variant), a variant id, or "all".
    pub variant: String,
}

impl Targets {
    /// Room label width in the report lines (wider for "room/variant").
    pub fn width(&self) -> usize {
        if self.variant == "" {
            11
        } else {
            20
        }
    }

    pub fn matches(def: &RoomDef, filter: &str, exact: bool) -> bool {
        filter == "*" || filter == "" || (if exact { def.id == filter } else { def.id.contains(filter) })
    }

    /// [index, def, forced variant id ("" = drawn), report label].
    pub fn pick(&self, filter: &str, exact: bool) -> Vec<(i64, &'static RoomDef, &'static str, String)> {
        let mut out_ = Vec::new();
        let all = RoomCatalog::all();
        for index in 0..all.len() {
            let def = &all[index];
            if !Self::matches(def, filter, exact) {
                continue;
            }
            if self.variant == "" {
                out_.push((index as i64, def, "", def.id.to_string()));
            } else {
                for v in &def.variants {
                    if self.variant == "all" || v.id == self.variant {
                        out_.push((index as i64, def, v.id, format!("{}/{}", def.id, v.id)));
                    }
                }
            }
        }
        out_
    }

    pub fn room(label: &str, def: &RoomDef, v: &str, runs: Vec<Value>) -> Value {
        let mut o = Map::new();
        o.insert("id".into(), json!(label));
        o.insert("group".into(), json!(def.group));
        o.insert("from".into(), json!(def.from_score));
        if v != "" {
            o.insert("variant".into(), json!(v));
        }
        o.insert("runs".into(), Value::Array(runs));
        Value::Object(o)
    }
}

/// Plays `f(target, seed index)` for every target and seed on the pool; per target the
/// results in seed order.
pub(crate) fn per_room<T: Sync, F>(targets: &[T], seeds: i64, f: F) -> Vec<Vec<Value>>
where
    F: Fn(&T, i64) -> Value + Sync + Send,
{
    let n = seeds.max(0);
    let all: Vec<Value> = (0..targets.len() as i64 * n)
        .into_par_iter()
        .map(|k| f(&targets[(k / n) as usize], k % n))
        .collect();
    let mut out_: Vec<Vec<Value>> = (0..targets.len()).map(|_| Vec::new()).collect();
    for (k, v) in all.into_iter().enumerate() {
        out_[k / n as usize].push(v);
    }
    out_
}

/// The same report lines as tools/sweep.ps1. Returns 1 when something failed.
pub struct Summary;

impl Summary {
    pub fn print(targets: &Targets, report: &Value) -> i32 {
        let mode = report["mode"].as_str().unwrap();
        let mut bad_total = 0;
        if report.get("rooms").is_some() {
            for room in report["rooms"].as_array().unwrap() {
                let runs = room["runs"].as_array().unwrap();
                let mut bad: Vec<i64> = Vec::new();
                let mut points = 0.0f64;
                let mut fine = 0;
                for r in runs {
                    points += r["points"].as_f64().unwrap();
                    let is_bad = if mode == "search" { !r["ok"].as_bool().unwrap() } else { r["dead"].as_bool().unwrap() };
                    if is_bad {
                        bad.push(r["seed"].as_i64().unwrap());
                    }
                    if mode == "search" && r["level"].as_i64().unwrap() > 0 {
                        fine += 1;
                    }
                }
                let label = if mode == "search" { "impossible" } else { "died" };
                let id = room["id"].as_str().unwrap();
                let mut line = format!(
                    "{:<w$} {} {:>4} / {:<4} avg points {}",
                    id,
                    label,
                    bad.len(),
                    runs.len(),
                    pad_left(&fmt_num(points / (1.max(runs.len())) as f64, "F1"), 5),
                    w = targets.width()
                );
                if fine > 0 {
                    line += &format!("  (narrow: {})", fine);
                }
                if !bad.is_empty() {
                    let s: Vec<String> = bad.iter().map(|b| b.to_string()).collect();
                    line += &format!("  seeds {}", s.join(","));
                }
                println!("{}", line);
                if mode == "search" {
                    bad_total += bad.len();
                }
            }
        } else {
            let runs = report["runs"].as_array().unwrap();
            let mut good = 0;
            for r in runs {
                let ok = if mode == "searchruns" { r["ok"].as_bool().unwrap() } else { !r["dead"].as_bool().unwrap() };
                if ok {
                    good += 1;
                    continue;
                }
                let where_ = match &r["died_in"] {
                    Value::Array(a) => a.iter().map(|x| x.as_str().unwrap()).collect::<Vec<_>>().join("/"),
                    x => x.as_str().unwrap().to_string(),
                };
                println!("seed {}: ended at tick {} in {}", r["seed"].as_i64().unwrap(), r["ticks"].as_i64().unwrap(), where_);
            }
            println!("{} of {} runs made it", good, runs.len());
            if mode == "searchruns" {
                bad_total = runs.len() - good;
            }
        }
        if bad_total > 0 {
            1
        } else {
            0
        }
    }
}

pub struct Modes;

impl Modes {
    const ROOM_TICKS: i64 = 3600;
    const ROOM_POINTS: i64 = 25;
    const RUN_TICKS: i64 = 9000;
    const ARRIVAL_TICKS: i64 = 90;

    pub fn search_rooms(targets: &Targets, seeds: i64, filter: &str, ticks: i64, first: i64) -> Value {
        let picked = targets.pick(filter, false);
        let all = per_room(&picked, seeds, |(index, def, v, _), s| {
            let seed_value = 1000 + (first + s) * 77;
            let sim = GameSim::with(seed_value, def.season, *index, v);
            let mut search = SurvivalSearch::new();
            let ok = search.run(&sim, ticks);
            json!({
                "seed": seed_value, "ok": ok, "ticks": search.ticks_survived,
                "width": search.peak_width, "level": search.level,
                "points": if ok { search.best.as_ref().unwrap().state.score - sim.state.score } else { 0 },
            })
        });
        let mut rooms = Vec::new();
        for ((_, def, v, label), runs) in picked.iter().zip(all) {
            rooms.push(Targets::room(label, def, v, runs));
        }
        json!({ "mode": "search", "seeds": seeds, "ticks": ticks, "rooms": rooms })
    }

    pub fn search_runs(seeds: i64, ticks: i64, first: i64) -> Value {
        let runs: Vec<Value> = (0..seeds.max(0))
            .into_par_iter()
            .map(|s| {
                let seed_value = 5000 + (first + s) * 131;
                let sim = GameSim::new(seed_value);
                let mut search = SurvivalSearch::new();
                let ok = search.run(&sim, ticks);
                let mut run = Map::new();
                run.insert("seed".into(), json!(seed_value));
                run.insert("ok".into(), json!(ok));
                run.insert("ticks".into(), json!(search.ticks_survived));
                if ok {
                    let mut rooms = vec![json!("open")];
                    let mut replay = GameSim::new(seed_value);
                    for &tap in &search.best_inputs {
                        replay.step(tap == 1);
                        if replay.events.contains(&Event::ROOM_CHANGE) {
                            rooms.push(json!(RoomCatalog::all()[replay.state.room_kind as usize].id));
                        }
                    }
                    run.insert("rooms".into(), Value::Array(rooms));
                    run.insert("score".into(), json!(replay.state.score));
                } else {
                    let died: Vec<Value> =
                        search.last_rooms.iter().map(|&k| json!(RoomCatalog::all()[k as usize].id)).collect();
                    run.insert("died_in".into(), Value::Array(died));
                    let mut deaths = Map::new();
                    for &(why, n) in &search.last_deaths {
                        deaths.insert(why.to_string(), json!(n));
                    }
                    run.insert("deaths".into(), Value::Object(deaths));
                }
                Value::Object(run)
            })
            .collect();
        json!({ "mode": "searchruns", "runs": runs })
    }

    pub fn planner_rooms(targets: &Targets, seeds: i64, filter: &str, first: i64) -> Value {
        let picked = targets.pick(filter, false);
        let all = per_room(&picked, seeds, |(index, def, v, _), s| {
            let seed_value = 1000 + (first + s) * 77;
            let mut sim = GameSim::with(seed_value, def.season, *index, v);
            let mut bot = PlannerBot::new(seed_value, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
            let start_score = sim.state.score;
            let mut since_room = 0;
            while !sim.is_over() && sim.state.tick < Self::ROOM_TICKS {
                let tap = bot.decide(&sim);
                sim.step(tap);
                since_room += 1;
                if sim.events.contains(&Event::ROOM_CHANGE) {
                    since_room = 0;
                }
                if sim.state.score - start_score >= Self::ROOM_POINTS {
                    break;
                }
            }
            let dead = sim.is_over();
            json!({
                "seed": seed_value, "points": sim.state.score - start_score, "ticks": sim.state.tick,
                "dead": dead, "cause": if dead { DeathCause::NAMES[sim.state.death_cause as usize] } else { "" },
                "after_exit": dead && since_room < Self::ARRIVAL_TICKS && sim.state.room_index > 0,
                "y": sim.state.y / SimConfig::SUB, "x": sim.state.x / SimConfig::SUB,
            })
        });
        let mut rooms = Vec::new();
        for ((_, def, v, label), runs) in picked.iter().zip(all) {
            rooms.push(Targets::room(label, def, v, runs));
        }
        json!({ "mode": "rooms", "seeds": seeds, "rooms": rooms })
    }

    pub fn planner_runs(seeds: i64, first: i64) -> Value {
        let runs: Vec<Value> = (0..seeds.max(0))
            .into_par_iter()
            .map(|s| {
                let seed_value = 5000 + (first + s) * 131;
                let mut sim = GameSim::new(seed_value);
                let mut bot = PlannerBot::new(seed_value, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
                let mut rooms = vec![json!("open")];
                let mut last = "open";
                let mut since_room = 0i64;
                let mut forks = 0i64;
                while !sim.is_over() && sim.state.tick < Self::RUN_TICKS {
                    let tap = bot.decide(&sim);
                    sim.step(tap);
                    since_room += 1;
                    if sim.events.contains(&Event::EXIT_OPEN) && sim.state.exit_b_kind != 0 {
                        forks += 1;
                    }
                    if sim.events.contains(&Event::ROOM_CHANGE) {
                        since_room = 0;
                        last = RoomCatalog::all()[sim.state.room_kind as usize].id;
                        rooms.push(json!(last));
                    }
                }
                let dead = sim.is_over();
                let n_rooms = rooms.len();
                json!({
                    "seed": seed_value, "score": sim.state.score, "coins": sim.state.coins,
                    "ticks": sim.state.tick, "rooms": rooms, "forks": forks, "route": sim.state.route,
                    "dead": dead, "cause": if dead { DeathCause::NAMES[sim.state.death_cause as usize] } else { "" },
                    "died_in": last, "arrival_death": dead && since_room < Self::ARRIVAL_TICKS && n_rooms > 1,
                    "ticks_in_room": since_room,
                })
            })
            .collect();
        json!({ "mode": "runs", "runs": runs })
    }
}
