//! Port of Checks.cs (`fastsim check [names] [--filter x]`): the check's bot tests, for the
//! checks that are ported (passable, arrival, yardstick, sight, blind_seeds). Same cases,
//! thresholds, messages and output lines as C#. C# shares the cases out over worker processes
//! (--jobs); here they run on the rayon pool (--jobs is global), results kept by case index.
//!   fastsim-rs check [all|passable,arrival,yardstick,sight,blind_seeds] [--filter x] [--jobs N]
//! Not ported (left out of the list): points, revive, pairs, keys, crawl, gates, isles, rescued,
//! runs, rlbot, exits, reach, mpcbot, sameseed.
use std::cmp::Ordering;
use std::sync::OnceLock;
use std::time::Instant;

use rayon::prelude::*;
use serde_json::{json, Value};

use crate::speed::Opts;

pub mod arrival;
pub mod honesty;
pub mod passable;
pub mod sight;
pub mod reach;
pub mod keys;
pub mod points;
pub mod revive;
pub mod pairs;
pub mod searches;
pub mod runs;
pub mod exits;
pub mod sameseed;

/// One check (C# `Checks.Check`).
pub trait Check: Sync + Send {
    fn name(&self) -> &'static str;
    /// The GDScript test it replaced ("path:method"), for -TestFilter.
    fn test(&self) -> &'static str;
    fn count(&self) -> usize;
    /// One case: {fails: [...], plus whatever combine needs}.
    fn run(&self, n: usize) -> Value;
    /// Failures over every case together.
    fn combine(&self, _results: &[Value]) -> Vec<String> {
        Vec::new()
    }
    fn summary(&self, results: &[Value]) -> String;
    /// Rust only: the case flips a global switch (BlindPlanner statics), so it runs alone,
    /// after the others (C# runs every case of a worker process one after another).
    fn exclusive(&self) -> bool {
        false
    }
}

/// C# `Checks.result(fails, extra)`.
pub fn result(fails: Vec<String>, extra: Value) -> Value {
    let mut o = match extra {
        Value::Object(m) => m,
        _ => serde_json::Map::new(),
    };
    o.insert("fails".to_string(), Value::Array(fails.into_iter().map(Value::String).collect()));
    Value::Object(o)
}

pub fn i(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|x| x as i64)).unwrap_or(0)
}

/// C# `string.CompareTo` under the current culture (ICU on .NET 5+), for the few orders the
/// output shows (sorted keys): punctuation before digits before letters, letters compared
/// without case first (then lower case first). Exact for the ASCII names these checks sort.
pub fn culture_cmp(a: &str, b: &str) -> Ordering {
    // FastSim.csproj sets InvariantGlobalization: culture compares are ordinal.
    a.cmp(b)
}

/// Checks.Yardstick (Yardstick/YardstickCheck.cs), on the port in yardstick/check.rs.
pub struct Yardstick;

impl Check for Yardstick {
    fn name(&self) -> &'static str {
        "yardstick"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim-rs/fastsim/src/yardstick/check.rs"
    }
    fn count(&self) -> usize {
        1
    }
    fn run(&self, _n: usize) -> Value {
        let (fails, extra) = crate::yardstick::check::run();
        result(fails, extra)
    }
    fn summary(&self, results: &[Value]) -> String {
        match results.first() {
            Some(r) => crate::yardstick::check::summary(r),
            None => crate::yardstick::check::summary(&json!({})),
        }
    }
}

/// C# `Checks.ALL`, the ported ones in the same order.
pub fn all() -> &'static Vec<Box<dyn Check>> {
    static ALL: OnceLock<Vec<Box<dyn Check>>> = OnceLock::new();
    ALL.get_or_init(|| {
        vec![
            // C#'s Checks.ALL order, without the checks of the frozen RL and MPC bots.
            Box::new(passable::Passable::default()),
            Box::new(arrival::Arrival::default()),
            Box::new(points::Points::default()),
            Box::new(revive::Revive::default()),
            Box::new(pairs::Pairs::default()),
            Box::new(keys::Keys::default()),
            Box::new(searches::Crawl::default()),
            Box::new(searches::Gates::default()),
            Box::new(searches::Isles::default()),
            Box::new(searches::Rescued::default()),
            Box::new(runs::Runs::default()),
            Box::new(exits::Exits::default()),
            Box::new(reach::Reach::default()),
            Box::new(Yardstick),
            Box::new(sameseed::SameSeedRevive::default()),
            Box::new(sight::SightCheck::default()),
            Box::new(honesty::BlindSeeds),
            Box::new(crate::boss::check::BossFair),
            Box::new(crate::difficulty::DifficultyCheck),
        ]
    })
}

/// `fastsim-rs check [names] [--filter x]` (Checks.run).
pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let pos = if pos.first().map(|s| s.as_str()) == Some("check") { &pos[1..] } else { pos };
    let names = pos.first().map(|s| s.as_str()).unwrap_or("all");
    let filter = opts.get("filter").map(|s| s.as_str()).unwrap_or("");
    let picked = match pick(names, filter) {
        Some(p) => p,
        None => return 2,
    };
    if picked.is_empty() {
        println!("fastsim check: no check matches the filter");
        return 0;
    }
    // Every (check, case), interleaved so heavy and light cases mix.
    let mut flat: Vec<(usize, usize)> = Vec::new();
    let most = picked.iter().map(|&c| all()[c].count()).max().unwrap_or(0);
    for n in 0..most {
        for &c in &picked {
            if n < all()[c].count() {
                flat.push((c, n));
            }
        }
    }

    let clock = Instant::now();
    let run_one = |&(c, n): &(usize, usize)| -> Value {
        let mut r = all()[c].run(n);
        if let Value::Object(m) = &mut r {
            m.insert("check".to_string(), json!(all()[c].name()));
            m.insert("n".to_string(), json!(n));
        }
        r
    };
    let mut results: Vec<Option<Value>> = vec![None; flat.len()];
    let shared: Vec<usize> = (0..flat.len()).filter(|&k| !all()[flat[k].0].exclusive()).collect();
    let done: Vec<(usize, Value)> = shared.par_iter().map(|&k| (k, run_one(&flat[k]))).collect();
    for (k, v) in done {
        results[k] = Some(v);
    }
    for k in 0..flat.len() {
        if results[k].is_none() {
            results[k] = Some(run_one(&flat[k]));
        }
    }
    let results: Vec<Value> = results.into_iter().map(|r| r.expect("every case ran")).collect();

    let mut bad = 0;
    for &c in &picked {
        let check = &all()[c];
        let mut mine: Vec<Value> = results.iter().filter(|r| r["check"].as_str() == Some(check.name())).cloned().collect();
        mine.sort_by_key(|r| i(&r["n"]));
        let mut fails: Vec<String> = Vec::new();
        if mine.len() != check.count() {
            fails.push(format!("only {} of {} cases ran", mine.len(), check.count()));
        }
        for r in &mine {
            if let Some(a) = r["fails"].as_array() {
                for f in a {
                    fails.push(f.as_str().unwrap_or("").to_string());
                }
            }
        }
        fails.extend(check.combine(&mine));
        let head = format!("fastsim check {} ({}): {}", check.name(), check.test(), check.summary(&mine));
        if fails.is_empty() {
            println!("{}  ok", head);
        } else {
            bad += 1;
            println!("{}  FAIL", head);
            for f in fails.iter().take(40) {
                println!("      {}", f);
            }
            if fails.len() > 40 {
                println!("      ... and {} more", fails.len() - 40);
            }
        }
    }
    let workers = rayon::current_num_threads().min(flat.len());
    println!(
        "fastsim check: {} of {} checks pass, {} cases in {} s ({} workers)",
        picked.len() - bad,
        picked.len(),
        flat.len(),
        crate::human::fmt_f(clock.elapsed().as_secs_f64(), 1),
        workers
    );
    if bad == 0 {
        0
    } else {
        1
    }
}

/// The checks named ("all" or a comma list) that match `filter` (a check name, or part of the
/// GD test it replaced ("path:method"), as tools/check.ps1 -TestFilter). None on an unknown name.
fn pick(names: &str, filter: &str) -> Option<Vec<usize>> {
    let mut out_: Vec<usize> = Vec::new();
    for name in names.split(',') {
        if name == "all" {
            out_.extend(0..all().len());
            continue;
        }
        match all().iter().position(|x| x.name() == name) {
            Some(c) => out_.push(c),
            None => {
                let list: Vec<&str> = all().iter().map(|x| x.name()).collect();
                eprintln!("unknown check '{}': {}", name, list.join(", "));
                return None;
            }
        }
    }
    let mut distinct: Vec<usize> = Vec::new();
    for c in out_ {
        if !distinct.contains(&c) {
            distinct.push(c);
        }
    }
    if filter.is_empty() || filter == "fastsim" {
        return Some(distinct);
    }
    Some(distinct.into_iter().filter(|&c| all()[c].name() == filter || all()[c].test().contains(filter)).collect())
}
