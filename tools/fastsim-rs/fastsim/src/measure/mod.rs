//! Port of Measure/MeasureMain.cs: `fastsim measure <bank|trials|estimate|confirm|runs|report|median|leak|visibility|check>`
//! (tools/yardstick.ps1 -Mode quick|confirm|report|leakrun, docs/BOT_TESTING.md).
//!
//! The files (`*.bank.json`, `*.trials.tsv`) are the C# ones byte for byte (but for the CPU
//! times), so either tool reads the other's. Doubles are computed in the C# order, dictionaries
//! C# enumerates keep their insertion order (`OrdMap`), allocation uses .NET's PriorityQueue
//! (`PriorityQueue` here) and `System.Random` is `DotnetRandom` with the same seeds.
//! `--threads` is read but not used: every mode runs on rayon's global pool (`--jobs N`).
//! `measure visibility` (visibility.rs) rebuilds visible.tsv from the GDScript painters as C# does.
//! fields.rs and methods.rs are generated from the Rust sim's sources by gen/rs_fields.py and
//! gen/rs_methods.py (gen/README.md): regenerate when a sim type gains or loses a field or a
//! no-argument method.
pub mod bank;
pub mod fields;
pub mod leak_run;
pub mod methods;
pub mod strat;
pub mod tier;
pub mod visibility;

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::Hash;
use std::time::Instant;

use serde_json::{json, Value};
use sim::prelude::*;

use crate::dotnet_random::DotnetRandom;
use crate::speed::Opts;
use crate::yardstick::bots::{BotSpec, Bots};
use crate::yardstick::fmt_num;
use crate::yardstick::json_pretty;
use crate::yardstick::stats::{jf, round, Stats};
use crate::yardstick::survival::{self, Obs, Set};
use bank::{Bank, BankRun, MBots, SeedSets, Visit};
use leak_run::LeakRun;
use strat::{Est, Pools, Strat, Trial};
use tier::Tier;

// ---------------------------------------------------------------- helpers

/// A dictionary that enumerates in insertion order, as a C# `Dictionary` without removals does
/// (`GroupBy`, `ToDictionary` and the plan of `allocate` are enumerated in that order).
#[derive(Clone, Debug)]
pub struct OrdMap<K, V> {
    items: Vec<(K, V)>,
    at: HashMap<K, usize>,
}

impl<K: Clone + Eq + Hash, V> Default for OrdMap<K, V> {
    fn default() -> Self {
        Self::new()
    }
}

impl<K: Clone + Eq + Hash, V> OrdMap<K, V> {
    pub fn new() -> Self {
        OrdMap { items: Vec::new(), at: HashMap::new() }
    }

    /// `d[k] = v`: a new key goes last, an old one keeps its place.
    pub fn insert(&mut self, k: K, v: V) {
        match self.at.get(&k) {
            Some(&i) => self.items[i].1 = v,
            None => {
                self.at.insert(k.clone(), self.items.len());
                self.items.push((k, v));
            }
        }
    }

    pub fn entry_or(&mut self, k: K, d: impl FnOnce() -> V) -> &mut V {
        let i = match self.at.get(&k) {
            Some(&i) => i,
            None => {
                self.at.insert(k.clone(), self.items.len());
                self.items.push((k, d()));
                self.items.len() - 1
            }
        };
        &mut self.items[i].1
    }

    pub fn get<Q>(&self, k: &Q) -> Option<&V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        self.at.get(k).map(|&i| &self.items[i].1)
    }

    pub fn contains_key<Q>(&self, k: &Q) -> bool
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        self.at.contains_key(k)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&K, &V)> {
        self.items.iter().map(|(k, v)| (k, v))
    }

    pub fn keys(&self) -> impl Iterator<Item = &K> {
        self.items.iter().map(|(k, _)| k)
    }

    pub fn values(&self) -> impl Iterator<Item = &V> {
        self.items.iter().map(|(_, v)| v)
    }

    pub fn into_vec(self) -> Vec<(K, V)> {
        self.items
    }
}

impl<K: Clone + Eq + Hash + std::borrow::Borrow<Q>, Q: Hash + Eq + ?Sized, V> std::ops::Index<&Q> for OrdMap<K, V> {
    type Output = V;
    fn index(&self, k: &Q) -> &V {
        self.get(k).expect("OrdMap: no such key")
    }
}

/// `Comparer<double>.Default.Compare` (double.CompareTo): NaN below everything.
pub fn dotnet_cmp(a: f64, b: f64) -> Ordering {
    if a < b {
        Ordering::Less
    } else if a > b {
        Ordering::Greater
    } else if a == b {
        Ordering::Equal
    } else if a.is_nan() {
        if b.is_nan() {
            Ordering::Equal
        } else {
            Ordering::Less
        }
    } else {
        Ordering::Greater
    }
}

/// `Math.Max(double, double)`: NaN if either is NaN.
pub fn nmax(a: f64, b: f64) -> f64 {
    if a.is_nan() || b.is_nan() {
        f64::NAN
    } else if a > b {
        a
    } else {
        b
    }
}

/// .NET's `PriorityQueue<T, double>` (a 4-ary min-heap, not stable): the same element comes
/// out for the same sequence of calls, ties included.
pub struct PriorityQueue<T> {
    nodes: Vec<(T, f64)>,
}

impl<T> Default for PriorityQueue<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> PriorityQueue<T> {
    const LOG2_ARITY: usize = 2;
    const ARITY: usize = 4;

    pub fn new() -> Self {
        PriorityQueue { nodes: Vec::new() }
    }

    pub fn count(&self) -> usize {
        self.nodes.len()
    }

    pub fn enqueue(&mut self, element: T, priority: f64) {
        let mut index = self.nodes.len();
        self.nodes.push((element, priority));
        // MoveUpDefaultComparer
        while index > 0 {
            let parent = (index - 1) >> Self::LOG2_ARITY;
            if dotnet_cmp(priority, self.nodes[parent].1) == Ordering::Less {
                self.nodes.swap(index, parent);
                index = parent;
            } else {
                break;
            }
        }
    }

    pub fn dequeue(&mut self) -> T {
        let last = self.nodes.len() - 1;
        self.nodes.swap(0, last);
        let (element, _) = self.nodes.pop().unwrap();
        if last > 0 {
            // MoveDownDefaultComparer(lastNode, 0)
            let size = self.nodes.len();
            let mut node_index = 0;
            loop {
                let mut i = (node_index << Self::LOG2_ARITY) + 1;
                if i >= size {
                    break;
                }
                let mut min_index = i;
                let upper = (i + Self::ARITY).min(size);
                i += 1;
                while i < upper {
                    if dotnet_cmp(self.nodes[i].1, self.nodes[min_index].1) == Ordering::Less {
                        min_index = i;
                    }
                    i += 1;
                }
                if dotnet_cmp(self.nodes[node_index].1, self.nodes[min_index].1) != Ordering::Greater {
                    break;
                }
                self.nodes.swap(node_index, min_index);
                node_index = min_index;
            }
        }
        element
    }
}

/// `Math.Round(x, d)` as a JSON number (null for NaN and infinities, where C# would throw).
pub fn jr(x: f64, d: i32) -> Value {
    jf(round(x, d))
}

/// C# `(long)node`: a JSON integer (a whole-number double is accepted too).
pub fn as_i64(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| v.as_f64().filter(|x| x.fract() == 0.0).map(|x| x as i64))
}

pub fn as_f64(v: &Value) -> Option<f64> {
    v.as_f64()
}

/// A double as System.Text.Json writes it: the shortest round-trip text ("R"), whole numbers
/// without ".0", exponents as .NET writes them (1E-05, 1E+16).
fn json_double(x: f64) -> String {
    if x.fract() == 0.0 && x.abs() < 1e15 {
        return format!("{}", x as i64);
    }
    let a = x.abs();
    if (1e-5..1e15).contains(&a) {
        return format!("{}", x);
    }
    let e = format!("{:e}", x);
    let (m, ex) = e.split_once('e').unwrap();
    let ex: i32 = ex.parse().unwrap();
    format!("{}E{}{:02}", m, if ex < 0 { '-' } else { '+' }, ex.abs())
}

/// A JSON string as Utf8JsonWriter escapes it (the default encoder).
fn json_str(s: &str, out_: &mut String) {
    out_.push('"');
    for c in s.chars() {
        match c {
            '\n' => out_.push_str("\\n"),
            '\r' => out_.push_str("\\r"),
            '\t' => out_.push_str("\\t"),
            '\u{8}' => out_.push_str("\\b"),
            '\u{C}' => out_.push_str("\\f"),
            '\\' => out_.push_str("\\\\"),
            ' '..='~' if !matches!(c, '"' | '&' | '\'' | '+' | '<' | '>' | '`') => out_.push(c),
            _ => {
                let mut buf = [0u16; 2];
                for u in c.encode_utf16(&mut buf) {
                    out_.push_str(&format!("\\u{:04X}", u));
                }
            }
        }
    }
    out_.push('"');
}

fn json_write(v: &Value, out_: &mut String) {
    match v {
        Value::Null => out_.push_str("null"),
        Value::Bool(b) => out_.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => match (n.as_i64(), n.as_u64(), n.as_f64()) {
            (Some(i), _, _) => out_.push_str(&i.to_string()),
            (None, Some(u), _) => out_.push_str(&u.to_string()),
            (None, None, Some(x)) => out_.push_str(&json_double(x)),
            _ => out_.push_str(&n.to_string()),
        },
        Value::String(s) => json_str(s, out_),
        Value::Array(a) => {
            out_.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out_.push(',');
                }
                json_write(x, out_);
            }
            out_.push(']');
        }
        Value::Object(m) => {
            out_.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out_.push(',');
                }
                json_str(k, out_);
                out_.push(':');
                json_write(x, out_);
            }
            out_.push('}');
        }
    }
}

/// `node.ToJsonString()` (compact, the default encoder): the bank file.
pub fn json_compact(v: &Value) -> String {
    let mut s = String::new();
    json_write(v, &mut s);
    s
}

/// `Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)))`.
pub fn create_parent(path: &str) -> Result<(), String> {
    let full = std::path::absolute(path).map_err(|e| format!("{}: {}", path, e))?;
    if let Some(d) = full.parent() {
        std::fs::create_dir_all(d).map_err(|e| format!("{}: {}", d.display(), e))?;
    }
    Ok(())
}

/// `Path.ChangeExtension(path, null)`: the path without its extension.
fn no_ext(path: &str) -> String {
    let start = path.rfind(['/', '\\', ':']).map(|i| i + 1).unwrap_or(0);
    match path[start..].rfind('.') {
        Some(i) => path[..start + i].to_string(),
        None => path.to_string(),
    }
}

/// `Path.ChangeExtension(bank, null).Replace(".bank", "") + suffix`.
fn beside_bank(bank: &str, suffix: &str) -> String {
    no_ext(bank).replace(".bank", "") + suffix
}

/// `long.Parse` / `int.Parse` / `double.Parse` of an option (a bad number ends the program, as in C#).
pub fn parse<T: std::str::FromStr>(v: &str, k: &str) -> T {
    match v.trim().parse() {
        Ok(x) => x,
        Err(_) => panic!("measure: --{} '{}' is not a number", k, v),
    }
}

fn log_line(s: &str) {
    eprintln!("{}", s);
}

// ------------------------------------------------------------- MeasureMain

/// Pocock bound for 5 equally spaced looks, two-sided 5%; and the sample
/// size inflation of that design over one fixed look (80% power).
pub const LOOKS: i32 = 5;
pub const POCOCK: f64 = 2.413;
pub const POCOCK_INFLATION: f64 = 1.207;

/// `fastsim-rs measure <what> [options]` (MeasureMain.run). `pos` is the words after
/// `measure` (a leading "measure" is skipped too, as C# gets it).
pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let pos = if pos.first().map(|s| s.as_str()) == Some("measure") { &pos[1..] } else { pos };
    let what = pos.first().map(|s| s.as_str()).unwrap_or("");
    let o_ = |k: &str, d: &str| opts.get(k).cloned().unwrap_or_else(|| d.to_string());
    // C# Math.Clamp(int.Parse(threads), 1, 64): the batch size of `median`'s first rooms.
    let threads: i32 = parse::<i32>(&o_("threads", "16"), "threads").clamp(1, 64);
    let res: Result<i32, String> = (|| match what {
        "bank" => {
            let bot = MBots::find(&o_("bot", "blind"))?;
            let first: i64 = parse(&o_("first", &SeedSets::DEV.to_string()), "first");
            let b = Bank::make(
                &bot,
                first,
                parse(&o_("seeds", "100"), "seeds"),
                parse(&o_("cap", &crate::speed::RUN_CAP.to_string()), "cap"),
                parse(&o_("points", "400"), "points"),
                true,
            );
            let path = o_("out", &format!("{}.bank.json", bot.name.replace(':', "-")));
            b.save(&path)?;
            println!(
                "bank {}: {} runs, {} visits, {} s",
                path,
                b.runs.len(),
                b.runs.iter().map(|r| r.visits.len()).sum::<usize>(),
                fmt_num(b.seconds, "F0")
            );
            print_bank(&b);
            Ok(0)
        }
        "trials" => trials(opts),
        "estimate" => estimate(opts),
        "confirm" => confirm(opts),
        "runs" => late_runs(opts),
        "report" => report(opts),
        "median" => median(opts, threads),
        "leak" => {
            let bot = MBots::find(&o_("bot", "blind"))?;
            let o = LeakRun::check(&bot, opts, true)?;
            println!("{}", json_pretty(&o));
            if let Some(p) = opts.get("json") {
                std::fs::write(p, json_pretty(&o) + "\n").map_err(|e| format!("{}: {}", p, e))?;
            }
            Ok(if o["leaks"].as_str() == Some("no") { 0 } else { 1 })
        }
        "visibility" => {
            // Rebuilds tools/fastsim-rs/data/visible.tsv from game/run (the painters) and the sim's sources.
            visibility::run(opts.get("root"), opts.contains_key("write"))
        }
        "check" => {
            let errs = self_test();
            for e in &errs {
                println!("FAIL {}", e);
            }
            if errs.is_empty() {
                println!("measure self-test ok");
            } else {
                println!("measure self-test: {} failures", errs.len());
            }
            Ok(if errs.is_empty() { 0 } else { 1 })
        }
        _ => {
            eprintln!("measure: bank, trials, estimate, confirm, runs, report, median, leak, check");
            Ok(2)
        }
    })();
    match res {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            2
        }
    }
}

fn need<'a>(opts: &'a Opts, k: &str) -> Result<&'a String, String> {
    opts.get(k).ok_or_else(|| format!("The given key '{}' was not present in the dictionary.", k))
}

fn print_bank(b: &Bank) {
    let set = b.as_set(None);
    let d = survival::describe(&set, 500);
    println!("{}", survival::text(&d));
    let full = full_plateau(b);
    println!(
        "full runs, plateau 40..{}: {} [{}, {}] per 100, {} deaths, {} CPU s ({} CPU s per plateau death)",
        if b.point_cap > 0 { b.point_cap.to_string() } else { "cap".to_string() },
        fmt_num(full.q, "F4"),
        fmt_num(full.lo, "F4"),
        fmt_num(full.hi, "F4"),
        full.deaths,
        fmt_num(full.cpu_s, "F0"),
        fmt_num(full.cpu_per_death, "F0")
    );
}

/// Plain full-run numbers on the bank's plateau visits: deaths / points, and the CPU it took
/// (all of it, ramp included). (C# record Full.)
#[derive(Clone, Copy, Debug)]
#[allow(dead_code)]
pub struct Full {
    pub q: f64,
    pub lo: f64,
    pub hi: f64,
    pub deaths: i32,
    pub points: i64,
    pub cpu_s: f64,
    pub cpu_per_death: f64,
}

pub fn full_plateau(b: &Bank) -> Full {
    let vis: Vec<&Visit> =
        b.runs.iter().flat_map(|r| r.visits.iter()).filter(|v| Strat::plateau(&v.key) && !v.censored).collect();
    let d = vis.iter().filter(|v| v.died).count() as i32;
    let pts: i64 = vis.iter().map(|v| v.points + if v.died { 1 } else { 0 }).sum();
    let (lo, hi) = survival::poisson_ci(d);
    let mut ms = 0.0;
    for r in &b.runs {
        ms += r.ms;
    }
    let cpu = ms / 1000.0;
    let p = 1.max(pts) as f64;
    Full {
        q: 100.0 * d as f64 / p,
        lo: 100.0 * lo / p,
        hi: 100.0 * hi / p,
        deaths: d,
        points: pts,
        cpu_s: cpu,
        cpu_per_death: cpu / 1.max(d) as f64,
    }
}

fn bots_of(opts: &Opts) -> String {
    opts.get("bots").or_else(|| opts.get("bot")).cloned().unwrap_or_else(|| "blind".to_string())
}

fn find_bots(list: &str) -> Result<Vec<BotSpec>, String> {
    list.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).map(MBots::find).collect()
}

fn prior_pl(bank: &Bank) -> HashMap<String, (f64, f64)> {
    Strat::bank_prior(bank).into_iter().map(|(k, v)| (k, (v.0, v.1))).collect()
}

/// `trials --bank B --bots a,b --budget S --out T.tsv`: S CPU seconds more of
/// trials (per bot), allocated by Neyman over the strata, the same jobs for every bot (paired).
fn trials(opts: &Opts) -> Result<i32, String> {
    let bank_path = need(opts, "bank")?;
    let bank = Bank::load(bank_path)?;
    let range = opts.get("range").cloned().unwrap_or_else(|| "plateau".to_string());
    let path = opts.get("out").cloned().unwrap_or_else(|| beside_bank(bank_path, ".trials.tsv"));
    let bots = find_bots(&bots_of(opts))?;
    let budget: f64 = parse::<f64>(opts.get("budget").map(|s| s.as_str()).unwrap_or("600"), "budget") * 1000.0;
    let mut pools = Pools::new(&bank, &range);
    let have = load_arms(&path, &bank, &bots);
    for t in have.iter().flatten() {
        pools.mark_used(t.seed, t.tick, t.k);
    }
    pools.grow(8);
    let arms = batch(&bank, &range, &bots, have, &mut pools, budget * bots.len() as f64, &path)?;
    for ts in &arms {
        print_est(&bank, ts, &range);
    }
    if bots.len() > 1 {
        print_ratios(&bank, &bots, &arms, &range);
    }
    Ok(0)
}

/// Trials so far of each bot in `path`, plus the bank's own visits for the bank's bot.
fn load_arms(path: &str, bank: &Bank, bots: &[BotSpec]) -> Vec<Vec<Trial>> {
    let all = Strat::load(path);
    bots.iter()
        .map(|b| {
            let mut l: Vec<Trial> = all.iter().filter(|t| t.bot == b.name).cloned().collect();
            if b.name == bank.bot {
                l.extend(Strat::bank_trials(bank));
            }
            l
        })
        .collect()
}

fn batch(
    bank: &Bank,
    range: &str,
    bots: &[BotSpec],
    arms: Vec<Vec<Trial>>,
    pools: &mut Pools,
    budget_ms: f64,
    path: &str,
) -> Result<Vec<Vec<Trial>>, String> {
    let prior = Strat::bank_prior(bank);
    // budget_ms is for all arms together (each job is played by every arm).
    let mut plan = Strat::allocate(bank, range, &arms, budget_ms, &prior);
    let strata = plan.values().filter(|&&v| v > 0).count();
    let seed: i32 = arms.iter().map(|a| a.len() as i32).sum::<i32>() + 17;
    let jobs = Strat::jobs(pools, &mut plan, &mut DotnetRandom::new(seed));
    log_line(&format!(
        "batch: {} trials per bot over {} strata (pool: {} redraws, k < {})",
        jobs.len(),
        strata,
        pools.redraws,
        pools.tried_k
    ));
    let mut res = Vec::new();
    for (i, mut arm) in arms.into_iter().enumerate() {
        let got = Strat::run_trials(&bots[i], "room", bank, &jobs, bank.cap, true);
        Strat::append(path, &got)?;
        arm.extend(got);
        res.push(arm);
    }
    Ok(res)
}

/// Prints an estimate and its cost. Information = 1 / se_log^2 (= deaths for a plain
/// Poisson count); full runs give one unit per plateau death at the bank's CPU per death
/// (ramp included), so the speedup is the ratio of CPU per unit of information.
fn print_est(bank: &Bank, ts: &[Trial], range: &str) -> Est {
    let prior = prior_pl(bank);
    let e = Strat::estimate(bank, ts, range, Some(&prior));
    let cpu = e.ms / 1000.0;
    let per_info = cpu * e.se_log * e.se_log;
    let full = full_plateau(bank);
    println!("{}", e.text());
    println!(
        "    CPU per unit of information: {} s here, {} s with full runs ({}x){}",
        fmt_num(per_info, "F0"),
        fmt_num(full.cpu_per_death, "F0"),
        fmt_num(full.cpu_per_death / nmax(1e-9, per_info), "F2"),
        if ts.iter().any(|t| t.k < 0) { "; the bank's visits are counted in" } else { "; the shared bank not counted" }
    );
    let k: Vec<String> =
        strat::killers(&e.cells).into_iter().take(6).map(|c| format!("{} {}/{}", c.key, c.d, c.n)).collect();
    println!("    killers: {}", k.join(", "));
    e
}

fn ratio_line(name_b: &str, name_a: &str, r: &strat::Ratio, word: &str) -> String {
    format!(
        "{} / {}: {} [{}, {}], z {}, {} {} (rho {})",
        name_b,
        name_a,
        fmt_num(r.r, "F3"),
        fmt_num(r.lo, "F3"),
        fmt_num(r.hi, "F3"),
        fmt_num(r.z, "F2"),
        word,
        r.paired,
        fmt_num(r.rho, "F2")
    )
}

fn print_ratios(bank: &Bank, bots: &[BotSpec], arms: &[Vec<Trial>], range: &str) {
    let prior = prior_pl(bank);
    let ea = Strat::estimate(bank, &arms[0], range, Some(&prior));
    for i in 1..bots.len() {
        let eb = Strat::estimate(bank, &arms[i], range, Some(&prior));
        let r = Strat::ratio(&ea, &eb, bank);
        println!("{}", ratio_line(&bots[i].name, &bots[0].name, &r, "paired trials"));
    }
}

/// `estimate --bank B --trials T [--bots a,b]`: estimates from saved files only.
fn estimate(opts: &Opts) -> Result<i32, String> {
    let bank = Bank::load(need(opts, "bank")?)?;
    let range = opts.get("range").cloned().unwrap_or_else(|| "plateau".to_string());
    print_bank(&bank);
    let all: Vec<Trial> = match opts.get("trials") {
        Some(t) => t.split(',').flat_map(Strat::load).collect(),
        None => Vec::new(),
    };
    let names: Vec<String> = match opts.get("bots") {
        Some(b) => b.split(',').map(|s| s.to_string()).collect(),
        None => {
            // all.Select(bot).Distinct().Prepend(bank.bot).Distinct()
            let mut n: Vec<String> = vec![bank.bot.clone()];
            for t in &all {
                if !n.contains(&t.bot) {
                    n.push(t.bot.clone());
                }
            }
            n
        }
    };
    let arms: Vec<Vec<Trial>> = names
        .iter()
        .map(|n| {
            let mut l: Vec<Trial> = all.iter().filter(|t| t.bot == *n).cloned().collect();
            if *n == bank.bot && !opts.contains_key("no-bank") {
                l.extend(Strat::bank_trials(&bank));
            }
            l
        })
        .collect();
    let mut json_a: Vec<Value> = Vec::new();
    let prior = prior_pl(&bank);
    for a in &arms {
        if a.is_empty() {
            continue;
        }
        json_a.push(print_est(&bank, a, &range).json());
    }
    let ests: Vec<Est> = arms.iter().map(|a| Strat::estimate(&bank, a, &range, Some(&prior))).collect();
    let mut cmp: Vec<Value> = Vec::new();
    for i in 1..names.len() {
        if arms[i].is_empty() || arms[0].is_empty() {
            continue;
        }
        let r = Strat::ratio(&ests[0], &ests[i], &bank);
        println!("{}", ratio_line(&names[i], &names[0], &r, "paired"));
        cmp.push(json!({
            "a": names[0], "b": names[i], "ratio": jr(r.r, 4), "lo": jr(r.lo, 4),
            "hi": jr(r.hi, 4), "z": jr(r.z, 3), "paired": r.paired, "rho": jr(r.rho, 3),
        }));
    }
    if let Some(p) = opts.get("json") {
        let o = json!({ "estimates": json_a, "compare": cmp });
        std::fs::write(p, json_pretty(&o) + "\n").map_err(|e| format!("{}: {}", p, e))?;
    }
    Ok(0)
}

/// `confirm --bank B --bots base,new --ratio 0.8 --out T.tsv`: a sequential
/// comparison. The plan is fixed before the first trial: the information
/// (1 / se^2 of the log rate ratio) that gives 80% power for `ratio` at
/// 5% with Pocock's 5 looks. Look j comes when 1/se^2 reaches j/5 of it; the
/// test stops at the first look with |z| > 2.413. Sized by information
/// (deaths), not by seeds.
fn confirm(opts: &Opts) -> Result<i32, String> {
    let bank_path = need(opts, "bank")?;
    let bank = Bank::load(bank_path)?;
    let range = opts.get("range").cloned().unwrap_or_else(|| "plateau".to_string());
    let bots = find_bots(&bots_of(opts))?;
    if bots.len() != 2 {
        return Err("confirm compares two bots: --bots base,new".into());
    }
    let rmin: f64 = parse(opts.get("ratio").map(|s| s.as_str()).unwrap_or("0.8"), "ratio");
    let path = opts.get("out").cloned().unwrap_or_else(|| beside_bank(bank_path, ".confirm.tsv"));
    let max_cpu: f64 = parse(opts.get("max-cpu").map(|s| s.as_str()).unwrap_or("1e9"), "max-cpu");
    let z_ab = 1.96 + 0.8416;
    let i_max = POCOCK_INFLATION * (z_ab / rmin.ln()).powf(2.0);
    println!(
        "plan: ratio {} (80% power, 5% two-sided), {} looks, stop at |z| > {}; information at the last look {} (deaths-equivalent per arm about {})",
        rmin,
        LOOKS,
        POCOCK,
        fmt_num(i_max, "F0"),
        fmt_num(2.0 * i_max, "F0")
    );
    let mut pools = Pools::new(&bank, &range);
    let mut arms = load_arms(&path, &bank, &bots);
    for t in arms.iter().flatten() {
        pools.mark_used(t.seed, t.tick, t.k);
    }
    pools.grow(8);
    let prior = prior_pl(&bank);
    let _clock = Instant::now();
    let mut decision = "no difference shown at the planned size".to_string();
    let trial_ms = |arms: &Vec<Vec<Trial>>| -> f64 {
        let mut s = 0.0;
        for a in arms {
            let mut x = 0.0;
            for t in a.iter().filter(|t| t.k >= 0) {
                x += t.ms;
            }
            s += x;
        }
        s
    };
    let mut look = 1;
    while look <= LOOKS {
        let want = i_max * look as f64 / LOOKS as f64;
        let mut r: Option<strat::Ratio> = None;
        let mut stopped = false;
        for _round in 0..12 {
            let ea = Strat::estimate(&bank, &arms[0], &range, Some(&prior));
            let eb = Strat::estimate(&bank, &arms[1], &range, Some(&prior));
            let rr = Strat::ratio(&ea, &eb, &bank);
            r = Some(rr);
            let info = 1.0 / (rr.se_log * rr.se_log);
            if info >= want * 0.97 {
                break;
            }
            // CPU so far per unit of information, times what is missing (at least a minute, at most double).
            let spent = (ea.ms + eb.ms) / 1000.0;
            let mut need_s = if spent > 0.0 && info > 0.0 { spent * (want / info - 1.0) } else { 600.0 };
            need_s = clamp(need_s * 1.1, 60.0, nmax(120.0, spent));
            if spent + need_s > max_cpu {
                decision = "stopped: --max-cpu reached".to_string();
                stopped = true;
                break;
            }
            arms = batch(&bank, &range, &bots, arms, &mut pools, need_s * 1000.0, &path)?;
        }
        if stopped {
            break;
        }
        let r = r.unwrap();
        let cpu = trial_ms(&arms) / 1000.0;
        println!(
            "look {}: {} / {} = {} [{}, {}], z {}, information {} of {}, rho {}, {} CPU s of trials",
            look,
            bots[1].name,
            bots[0].name,
            fmt_num(r.r, "F3"),
            fmt_num(r.lo, "F3"),
            fmt_num(r.hi, "F3"),
            fmt_num(r.z, "F2"),
            fmt_num(1.0 / (r.se_log * r.se_log), "F0"),
            fmt_num(want, "F0"),
            fmt_num(r.rho, "F2"),
            fmt_num(cpu, "F0")
        );
        if r.z.abs() > POCOCK {
            decision = if r.z < 0.0 {
                format!("{} dies less (stopped at look {})", bots[1].name, look)
            } else {
                format!("{} dies more (stopped at look {})", bots[1].name, look)
            };
            break;
        }
        // Futility: the gain hoped for is outside the interval (Pocock-adjusted).
        let hi_p = (r.r.ln() + POCOCK * r.se_log).exp();
        let lo_p = (r.r.ln() - POCOCK * r.se_log).exp();
        if look < LOOKS && hi_p < 1.0 / rmin && lo_p > rmin {
            decision = format!("no change as big as {} either way (futility at look {})", rmin, look);
            break;
        }
        look += 1;
    }
    println!("decision: {}", decision);
    for a in &arms {
        print_est(&bank, a, &range);
    }
    {
        // What full runs would have cost for the same certainty: two independent arms of D
        // plateau deaths each give a log-ratio information of D / 2, at the bank's CPU per death.
        let ea = Strat::estimate(&bank, &arms[0], &range, Some(&prior));
        let eb = Strat::estimate(&bank, &arms[1], &range, Some(&prior));
        let r = Strat::ratio(&ea, &eb, &bank);
        let info = 1.0 / (r.se_log * r.se_log);
        let trial_cpu = trial_ms(&arms) / 1000.0;
        let full = full_plateau(&bank);
        // Each arm at its own speed: the bank's CPU per death times the arm's CPU on the
        // paired trials relative to the bank bot's (the same jobs for both).
        let arm_ms = |a: &Vec<Trial>| {
            let mut x = 0.0;
            for t in a.iter().filter(|t| t.k >= 0) {
                x += t.ms;
            }
            x
        };
        let ms_a = arm_ms(&arms[0]);
        let ms_b = arm_ms(&arms[1]);
        let speed_b = if ms_a > 0.0 { ms_b / ms_a } else { 1.0 };
        let full_cpu = (2.0 * info) * full.cpu_per_death * (1.0 + speed_b);
        println!(
            "cost: information {} on the log ratio for {} CPU s of trials (+{} s for the shared bank); full runs for the same: {} plateau deaths per arm, {} CPU s: {}x, {}x with the bank",
            fmt_num(info, "F0"),
            fmt_num(trial_cpu, "F0"),
            fmt_num(full.cpu_s, "F0"),
            fmt_num(2.0 * info, "F0"),
            fmt_num(full_cpu, "F0"),
            fmt_num(full_cpu / trial_cpu, "F2"),
            fmt_num(full_cpu / (trial_cpu + full.cpu_s), "F2")
        );
    }
    Ok(0)
}

/// `Math.Clamp(x, lo, hi)` (C# throws when lo > hi; here hi >= 120 > 60).
fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo {
        lo
    } else if x > hi {
        hi
    } else {
        x
    }
}

/// `runs --bank B --bot X --from 100 --n 50 --out T.tsv`: plateau runs that
/// start late. Each starts from a bank entry at or past `from` points (the
/// first per bank run), with the spine replaced, so the rest of the run is
/// new; it plays to death or the cap. Gives the plateau rate and the
/// survival past `from` for strong bots without replaying the first rooms.
fn late_runs(opts: &Opts) -> Result<i32, String> {
    let bank_path = need(opts, "bank")?;
    let bank = Bank::load(bank_path)?;
    let bot = MBots::find(opts.get("bot").unwrap_or(&bank.bot))?;
    let from: i64 = parse(opts.get("from").map(|s| s.as_str()).unwrap_or("100"), "from");
    let n: i32 = parse(opts.get("n").map(|s| s.as_str()).unwrap_or("50"), "n");
    let cap: i64 = parse(&opts.get("cap").cloned().unwrap_or_else(|| crate::speed::RUN_CAP.to_string()), "cap");
    let path = opts.get("out").cloned().unwrap_or_else(|| beside_bank(bank_path, &format!(".from{}.tsv", from)));
    let mut starts: Vec<strat::Job> = Vec::new();
    for (i, r) in bank.runs.iter().enumerate() {
        if let Some(v) = r.visits.iter().find(|v| v.score >= from) {
            starts.push((i, v.tick, v.tap, 0));
        }
    }
    if starts.is_empty() {
        return Err(format!("no bank run reaches {} points", from));
    }
    let sl = starts.len() as i32;
    let jobs: Vec<strat::Job> = (0..n)
        .map(|j| {
            let s = starts[(j % sl) as usize];
            (s.0, s.1, s.2, (1000 + j / sl) as i64)
        })
        .collect();
    let got = Strat::run_trials(&bot, "run", &bank, &jobs, cap, true);
    Strat::append(&path, &got)?;
    let all: Vec<Trial> = Strat::load(&path).into_iter().filter(|t| t.kind == "run" && t.bot == bot.name).collect();
    let set = Set {
        name: format!("{} from {}", bot.name, from),
        source: String::new(),
        cap,
        runs: all.iter().map(|t| Obs::new(t.seed, t.points, t.died)).collect(),
        approx: false,
    };
    let d = set.deaths();
    let pts: i64 = set.runs.iter().map(|r| r.points).sum();
    let (lo, hi) = survival::poisson_ci(d);
    let p = 1.max(pts) as f64;
    let mut ms = 0.0;
    for t in &all {
        ms += t.ms;
    }
    println!(
        "{}, {} runs from {} points: {} [{}, {}] per 100 past {}, {} deaths in {} points, {} alive at the cap, {} CPU s",
        bot.name,
        all.len(),
        from,
        fmt_num(100.0 * d as f64 / p, "F4"),
        fmt_num(100.0 * lo / p, "F4"),
        fmt_num(100.0 * hi / p, "F4"),
        from,
        d,
        pts,
        set.alive(),
        fmt_num(ms / 1000.0, "F0")
    );
    println!("{}", survival::text(&survival::describe(&set, 500)));
    Ok(0)
}

/// The score bands of the median model: the ramp's four classes, then the plateau.
pub const BANDS: [(&str, i64, i64); 5] =
    [("@b0", 0, 10), ("@b10", 10, 20), ("@b20", 20, 30), ("@b30", 30, 40), ("plateau", 40, i64::MAX)];

/// The score where a run with these death rates per 100 points (one per band) is
/// alive with chance 1/2: survival exp(-sum of rate x points in each band).
pub fn median_of(per100: &[f64]) -> f64 {
    let mut h = 2f64.ln();
    for (i, b) in BANDS.iter().enumerate() {
        let rate = nmax(1e-9, per100[i] / 100.0);
        let span = (b.2 - b.1) as f64;
        if rate * span >= h {
            return b.1 as f64 + h / rate;
        }
        h -= rate * span;
    }
    f64::INFINITY
}

/// One band's estimate in `median` (C#'s tuple: q, se_log, trials, deaths, imputed, pts).
#[derive(Clone, Copy, Debug)]
struct BandEst {
    q: f64,
    se_log: f64,
    trials: i32,
    deaths: i32,
    imputed: f64,
    pts: i64,
}

/// `median --bank B --bot X --budget S [--out T.tsv] [--json J]`: the KM median a bot
/// would get on full runs, from trials (docs/BOT_TESTING.md, "Tier calibration").
/// S more CPU seconds, an equal share per score band: the first room (0..10 points,
/// which no room entry starts) from fresh runs on their own seeds, played until the
/// first room change; the other ramp bands and the plateau from room trials of their
/// strata (Neyman inside each band). The death rate per band, then the median of the
/// piecewise constant survival those rates give; its interval from 4000 draws of the
/// rates (each lognormal by its own CI). Trials pile up in T (and T.start.tsv for the
/// first room), so a second call refines.
fn median(opts: &Opts, threads: i32) -> Result<i32, String> {
    let bank_path = need(opts, "bank")?;
    let bank = Bank::load(bank_path)?;
    let bot = MBots::find(opts.get("bot").map(|s| s.as_str()).unwrap_or("blind"))?;
    let path = opts.get("out").cloned().unwrap_or_else(|| beside_bank(bank_path, ".median.tsv"));
    let budget: f64 = parse::<f64>(opts.get("budget").map(|s| s.as_str()).unwrap_or("300"), "budget") * 1000.0;
    let bots = vec![bot.clone()];
    let mut arms = load_arms(&path, &bank, &bots);
    let prior = prior_pl(&bank);
    let share = budget / BANDS.len() as f64;
    // The first room: fresh runs.
    let start_path = no_ext(&path) + ".start.tsv";
    let mut starts = load_starts(&start_path, &bot.name);
    if budget > 0.0 {
        starts = first_rooms(&bot, starts, share, threads, &start_path)?;
    }
    // The rest: room trials per band.
    let mut b = 1;
    while b < BANDS.len() && budget > 0.0 {
        let mut pools = Pools::new(&bank, BANDS[b].0);
        for t in arms.iter().flatten() {
            pools.mark_used(t.seed, t.tick, t.k);
        }
        pools.grow(8);
        arms = batch(&bank, BANDS[b].0, &bots, arms, &mut pools, share, &path)?;
        b += 1;
    }
    let mut est: Vec<BandEst> = Vec::with_capacity(BANDS.len());
    {
        let d = starts.iter().filter(|x| x.died).count() as i32;
        let pts: i64 = starts.iter().map(|x| x.points).sum();
        est.push(BandEst {
            q: 100.0 * d as f64 / 1.max(pts) as f64,
            se_log: 1.0 / nmax(0.5, d as f64).sqrt(),
            trials: starts.len() as i32,
            deaths: d,
            imputed: 0.0,
            pts,
        });
    }
    for band in BANDS.iter().skip(1) {
        let e = Strat::estimate(&bank, &arms[0], band.0, Some(&prior));
        let se = if e.se_log.is_finite() && e.se_log > 0.0 { e.se_log } else { 1.0 };
        let pts: i64 = arms[0]
            .iter()
            .filter(|t| t.kind == "room" && !t.censored && Strat::in_range(&t.key, band.0))
            .map(|t| t.points)
            .sum();
        est.push(BandEst {
            q: if e.q.is_finite() { e.q } else { 0.0 },
            se_log: se,
            trials: e.trials,
            deaths: e.deaths,
            imputed: e.imputed_share,
            pts,
        });
    }
    let med = median_of(&est.iter().map(|e| e.q).collect::<Vec<f64>>());
    let mut rng = DotnetRandom::new(4711);
    let mut draws: Vec<f64> = Vec::with_capacity(4000);
    for _ in 0..4000 {
        let q: Vec<f64> = est
            .iter()
            .map(|e| {
                let u = 1.0 - rng.next_double();
                let v = rng.next_double();
                let g = (-2.0 * u.ln()).sqrt() * (2.0 * std::f64::consts::PI * v).cos();
                // A band with no deaths yet: drawn around the half-death level of its points (Jeffreys).
                if e.deaths == 0 {
                    return 100.0 * 0.5 / 1.max(e.pts) as f64 * (g * 1.4 - 0.98).exp();
                }
                e.q * (g * e.se_log).exp()
            })
            .collect();
        draws.push(median_of(&q));
    }
    draws.sort_by(|a, b| dotnet_cmp(*a, *b));
    let lo = draws[(0.025 * draws.len() as f64) as usize];
    let hi = draws[(0.975 * draws.len() as f64) as usize - 1];
    let mut arm_ms = 0.0;
    for t in arms[0].iter().filter(|t| t.k >= 0) {
        arm_ms += t.ms;
    }
    let mut start_ms = 0.0;
    for x in &starts {
        start_ms += x.ms;
    }
    let cpu = (arm_ms + start_ms) / 1000.0;
    let r = |v: f64, digits: i32| -> Value { if v.is_finite() { jf(round(v, digits)) } else { Value::Null } };
    let trials = arms[0].iter().filter(|t| t.k >= 0).count() as i32 + starts.len() as i32;
    let deaths =
        arms[0].iter().filter(|t| t.k >= 0 && t.died).count() as i32 + starts.iter().filter(|x| x.died).count() as i32;
    let bands: Vec<Value> = BANDS
        .iter()
        .zip(est.iter())
        .map(|(b, e)| {
            json!({
                "range": b.0, "per100": r(e.q, 4), "se_log": r(e.se_log, 3),
                "trials": e.trials, "deaths": e.deaths, "imputed_share": r(e.imputed, 3),
            })
        })
        .collect();
    let o = json!({
        "bot": bot.name, "about": bot.about, "median": r(med, 1), "lo": r(lo, 1), "hi": r(hi, 1),
        "trials": trials, "deaths": deaths, "cpu_s": jf(round(cpu, 0)),
        "bank": bank_path, "gameplay_version": SimConfig::GAMEPLAY_VERSION,
        "bands": bands,
    });
    let f = |v: f64| -> String { if v.is_finite() { fmt_num(v, "F0") } else { "inf".to_string() } };
    println!(
        "{}: median {} [{}, {}], {} trials, {} deaths, {} CPU s",
        bot.name,
        f(med),
        f(lo),
        f(hi),
        trials,
        deaths,
        fmt_num(cpu, "F0")
    );
    for (b, e) in BANDS.iter().zip(est.iter()) {
        println!(
            "  {:<8} {} per 100 (+-{}%), {} trials, {} deaths, imputed {}%",
            b.0,
            fmt_num(e.q, "F4"),
            fmt_num(100.0 * 1.96 * e.se_log, "F0"),
            e.trials,
            e.deaths,
            fmt_num(100.0 * e.imputed, "F0")
        );
    }
    if let Some(p) = opts.get("json") {
        let nl = if cfg!(windows) { "\r\n" } else { "\n" };
        std::fs::write(p, json_pretty(&o) + nl).map_err(|e| format!("{}: {}", p, e))?;
    }
    Ok(0)
}

/// One fresh run of `first_rooms` (C# record Start).
#[derive(Clone, Debug)]
pub struct Start {
    pub bot: String,
    pub seed: i64,
    pub died: bool,
    pub points: i64,
    pub ms: f64,
}

fn load_starts(path: &str, bot: &str) -> Vec<Start> {
    let text = match std::fs::read_to_string(path) {
        Ok(t) => t,
        Err(_) => return Vec::new(),
    };
    let num = |s: &str| -> i64 { s.parse().unwrap_or_else(|_| panic!("{}: bad number '{}'", path, s)) };
    text.trim_start_matches('\u{feff}')
        .lines()
        .skip(1)
        .map(|l| l.split('\t').collect::<Vec<&str>>())
        .filter(|c| c.len() >= 5 && c[0] == bot)
        .map(|c| Start {
            bot: c[0].to_string(),
            seed: num(c[1]),
            died: c[2] == "1",
            points: num(c[3]),
            ms: c[4].parse().unwrap_or_else(|_| panic!("{}: bad number '{}'", path, c[4])),
        })
        .collect()
}

/// Fresh runs on seeds of their own (dev seeds from 60 001), each to its first room
/// change or its death, until `budget_ms` more CPU is spent.
fn first_rooms(
    bot: &BotSpec,
    have: Vec<Start>,
    budget_ms: f64,
    threads: i32,
    path: &str,
) -> Result<Vec<Start>, String> {
    use rayon::prelude::*;
    use std::io::Write;
    let mut all = have;
    let mut next: i64 =
        if all.is_empty() { 0 } else { all.iter().map(|x| x.seed).max().unwrap() - (SeedSets::DEV + 50_000) };
    let mut spent = 0.0;
    if !std::path::Path::new(path).exists() {
        std::fs::write(path, "bot\tseed\tdied\tpoints\tms\n").map_err(|e| format!("{}: {}", path, e))?;
    }
    let nl = if cfg!(windows) { "\r\n" } else { "\n" };
    while spent < budget_ms {
        let n = threads * 4;
        let got: Vec<Start> = (0..n)
            .into_par_iter()
            .map(|i| {
                let seed = SeedSets::DEV + 50_000 + next + 1 + i as i64;
                let clock = Instant::now();
                let mut sim = GameSim::new(seed);
                let mut decide = (bot.make)(seed);
                let mut ticks: i64 = 0;
                while !sim.is_over() && sim.state.room_index == 0 && ticks < 20_000 {
                    let tap = decide(&sim);
                    sim.step(tap);
                    ticks += 1;
                }
                Start {
                    bot: bot.name.clone(),
                    seed,
                    died: sim.is_over(),
                    points: sim.state.score.min(10),
                    ms: clock.elapsed().as_secs_f64() * 1000.0,
                }
            })
            .collect();
        next += n as i64;
        let mut s = 0.0;
        for x in &got {
            s += x.ms;
        }
        spent += s;
        let mut text = String::new();
        for x in &got {
            text.push_str(&format!(
                "{}\t{}\t{}\t{}\t{}{}",
                x.bot,
                x.seed,
                if x.died { "1" } else { "0" },
                x.points,
                fmt_num(x.ms, "F1"),
                nl
            ));
        }
        all.extend(got);
        let mut f =
            std::fs::OpenOptions::new().append(true).create(true).open(path).map_err(|e| format!("{}: {}", path, e))?;
        f.write_all(text.as_bytes()).map_err(|e| format!("{}: {}", path, e))?;
    }
    log_line(&format!("first room: {} fresh runs, {} deaths", all.len(), all.iter().filter(|x| x.died).count()));
    Ok(all)
}

/// `report --bot X [--fair F] [--claimed tier]`: the holdout (seeds 1..400,
/// the bots' cap), run once per release candidate. KM median with CI and
/// the tier verdict; beast and infinite by the plateau rate and the share
/// of finishable runs finished.
fn report(opts: &Opts) -> Result<i32, String> {
    let bot = MBots::find(opts.get("bot").map(|s| s.as_str()).unwrap_or("blind"))?;
    let seeds: i32 = parse(&opts.get("seeds").cloned().unwrap_or_else(|| SeedSets::HOLDOUT_N.to_string()), "seeds");
    let cap: i64 = parse(&opts.get("cap").cloned().unwrap_or_else(|| crate::speed::RUN_CAP.to_string()), "cap");
    let path = opts.get("out").cloned().unwrap_or_else(|| format!("{}.holdout.bank.json", bot.name.replace(':', "-")));
    let mut bank: Option<Bank> = if std::path::Path::new(&path).is_file() && !opts.contains_key("again") {
        Some(Bank::load(&path)?)
    } else {
        None
    };
    if bank.as_ref().map(|b| b.bot != bot.name).unwrap_or(true) {
        let b = Bank::make(&bot, SeedSets::HOLDOUT, seeds, cap, 0, true);
        b.save(&path)?;
        bank = Some(b);
    }
    let bank = bank.unwrap();
    let fair = match opts.get("fair") {
        Some(f) => Some(Tier::load_fair(f)?),
        None => None,
    };
    let claimed = opts.get("claimed").cloned().unwrap_or_else(|| Stats::claimed_tier(&bot.name));
    let mut v = Tier::verdict(&bank.as_set(Some(&format!("{}_holdout", bot.name))), &claimed, fair.as_ref(), 2000)?;
    {
        let o = v.as_object_mut().unwrap();
        o.insert("bot".into(), bot.name.clone().into());
        o.insert("seeds".into(), format!("{}..{}", SeedSets::HOLDOUT + 1, SeedSets::HOLDOUT + seeds as i64).into());
        o.insert("gameplay_version".into(), SimConfig::GAMEPLAY_VERSION.into());
    }
    println!("{}", survival::text(&survival::describe(&bank.as_set(None), 1000)));
    println!("{}", json_pretty(&v));
    if let Some(p) = opts.get("json") {
        std::fs::write(p, json_pretty(&v) + "\n").map_err(|e| format!("{}: {}", p, e))?;
    }
    Ok(0)
}

// ------------------------------------------------------------ self-test

/// Checks the estimator on made-up trials with known answers, the file
/// round trips, and that a redraw from a bank entry enters a room.
pub fn self_test() -> Vec<String> {
    let mut errs: Vec<String> = Vec::new();
    // A bank with two strata: A (share 0.75, p 0.02) and B (share 0.25, p 0.2), 10 points a visit.
    let mut bank = Bank { bot: "t".into(), cap: 1000, ..Bank::default() };
    let mut run = BankRun { seed: 1, ..BankRun::default() };
    for i in 0..300 {
        run.visits.push(Visit::new(i, false, 50, "A@p", false, false, 10, 100, 1.0));
    }
    for i in 0..100 {
        run.visits.push(Visit::new(1000 + i, false, 50, "B@p", false, false, 10, 100, 1.0));
    }
    bank.runs.push(run);
    let mut rng = DotnetRandom::new(5);
    let mut trials_: Vec<Trial> = Vec::new();
    for i in 0..4000 {
        trials_.push(Trial::new("x", "room", 1, i, 0, "A@p", rng.next_double() < 0.02, false, 10, 100, 1.0));
    }
    for i in 0..4000 {
        trials_.push(Trial::new("x", "room", 1, i, 1, "B@p", rng.next_double() < 0.2, false, 10, 100, 1.0));
    }
    // Died visits score fewer points; here they score 10 too, so Q = 100 * (0.75*0.02 + 0.25*0.2) / 10 = 0.65.
    let e = Strat::estimate(&bank, &trials_, "plateau", None);
    if (e.q - 0.65).abs() > 0.05 {
        errs.push(format!("stratified estimate {}, want 0.65", fmt_num(e.q, "F3")));
    }
    if !(e.lo < 0.65 && e.hi > 0.65) {
        errs.push(format!("interval [{}, {}] misses 0.65", fmt_num(e.lo, "F3"), fmt_num(e.hi, "F3")));
    }
    // Coverage of the interval over repeated samples (should be near 95%).
    let mut cover = 0;
    for rep in 0..200 {
        let mut r2 = DotnetRandom::new(100 + rep);
        let mut ts: Vec<Trial> = Vec::new();
        for i in 0..300 {
            ts.push(Trial::new("x", "room", 1, i, 0, "A@p", r2.next_double() < 0.02, false, 10, 100, 1.0));
        }
        for i in 0..200 {
            ts.push(Trial::new("x", "room", 1, i, 1, "B@p", r2.next_double() < 0.2, false, 10, 100, 1.0));
        }
        let e2 = Strat::estimate(&bank, &ts, "plateau", None);
        if e2.lo < 0.65 && e2.hi > 0.65 {
            cover += 1;
        }
    }
    if !(180..=198).contains(&cover) {
        errs.push(format!("interval coverage {}/200, want about 190", cover));
    }
    // Neyman: B (p 0.2) must get more trials per visit share than A.
    let mut prior: HashMap<String, (f64, f64, f64)> = HashMap::new();
    prior.insert("A@p".into(), (0.02, 10.0, 1.0));
    prior.insert("B@p".into(), (0.2, 10.0, 1.0));
    let plan = Strat::allocate(&bank, "plateau", &[Vec::new()], 1000.0, &prior);
    let pa = plan.get("A@p").copied().unwrap_or(0);
    let pb = plan.get("B@p").copied().unwrap_or(0);
    let ra = pa as f64 / 0.75;
    let rb = pb as f64 / 0.25;
    if !(rb > ra * 2.0) {
        errs.push(format!("allocation A {} B {}: the deadly stratum should get more per share", pa, pb));
    }
    // Ratio of an arm with itself is 1 and fully paired.
    let rr = Strat::ratio(&e, &e, &bank);
    if (rr.r - 1.0).abs() > 1e-9 || rr.rho < 0.999 {
        errs.push(format!("self ratio {} rho {}", rr.r, rr.rho));
    }
    // Trial file round trip.
    let tmp = std::env::temp_dir().join(format!("measure_selftest_{}.tsv", std::process::id()));
    let tmp_s = tmp.to_string_lossy().to_string();
    let _ = std::fs::remove_file(&tmp);
    match Strat::append(&tmp_s, &trials_[..5]) {
        Ok(()) => {
            let back = Strat::load(&tmp_s);
            if back.len() != 5 || back[3] != trials_[3] {
                errs.push("trials file round trip".into());
            }
        }
        Err(e) => errs.push(format!("trials file round trip: {}", e)),
    }
    let _ = std::fs::remove_file(&tmp);
    // A real bank: a short run of the gap seeker, saved and loaded, then a redraw from an entry.
    let gap = Bots::find("gap").expect("the gap bot");
    let b = Bank::make(&gap, 0, 3, 6000, 0, false);
    let bp = std::env::temp_dir().join(format!("measure_selftest_{}.bank.json", std::process::id()));
    let bp_s = bp.to_string_lossy().to_string();
    let ok = b.save(&bp_s).and_then(|_| Bank::load(&bp_s));
    match ok {
        Ok(b2) => {
            if b2.runs.len() != 3
                || b2.runs[1].taps.len() != b.runs[1].taps.len()
                || b2.runs[1].visits.len() != b.runs[1].visits.len()
            {
                errs.push("bank file round trip".into());
            }
        }
        Err(e) => errs.push(format!("bank file round trip: {}", e)),
    }
    let _ = std::fs::remove_file(&bp);
    match b.runs.iter().find(|r| !r.visits.is_empty()) {
        None => errs.push("gap seeker entered no room in 6000 ticks".into()),
        Some(r0) => {
            let v = &r0.visits[0];
            let pre = Bank::replay(r0, v.tick);
            let mut real = pre.clone_deep();
            real.step(v.tap);
            if Bank::key(&real) != v.key {
                errs.push(format!("replayed entry is {}, bank says {}", Bank::key(&real), v.key));
            }
            let mut entered = 0;
            let mut keys: std::collections::HashSet<String> = std::collections::HashSet::new();
            for k in 0..20 {
                if let Some(c) = Strat::redraw(&pre, v.tap, Strat::spine_seed(r0.seed, v.tick, k)) {
                    entered += 1;
                    keys.insert(Bank::key(&c));
                }
            }
            if entered < 20 {
                errs.push(format!("only {}/20 redraws entered a room", entered));
            }
            if keys.len() < 3 {
                errs.push(format!("20 redraws gave only {} different rooms", keys.len()));
            }
        }
    }
    // The visible list matches the drawing code (rebuild: measure visibility --write).
    let root = visibility::default_root();
    if root.join("game").join("run").is_dir() {
        match visibility::generate(&root) {
            Ok(want) => {
                let have: Vec<String> = std::fs::read_to_string(leak_run::Visibility::file())
                    .map(|t| {
                        t.trim_start_matches('\u{feff}')
                            .lines()
                            .filter(|l| !l.starts_with('#') && !l.is_empty())
                            .map(|l| l.to_string())
                            .collect()
                    })
                    .unwrap_or_default();
                if want != have {
                    errs.push("tools/fastsim-rs/data/visible.tsv is stale: run `fastsim measure visibility --write`".into());
                }
            }
            Err(e) => errs.push(format!("visible list: {}", e)),
        }
    }
    // The whole-run leak check, calibrated: the gap seeker sees only the screen
    // (no leak), PlannerBot steps copies of the real sim (it must leak).
    let mut leak_opts: Opts = HashMap::new();
    for (k, v) in [("seeds", "2"), ("forks", "6"), ("cap", "5000"), ("points", "60")] {
        leak_opts.insert(k.to_string(), v.to_string());
    }
    match LeakRun::check(&gap, &leak_opts, false) {
        Ok(lg) => {
            if lg["leaks"].as_str() != Some("no") {
                errs.push(format!(
                    "leak check on the gap seeker: {} ({})",
                    crate::yardstick::node_str(&lg["leaks"]),
                    crate::yardstick::node_str(&lg["example"])
                ));
            }
        }
        Err(e) => errs.push(format!("leak check on the gap seeker: {}", e)),
    }
    match LeakRun::check(&Bots::find("planner").expect("the planner bot"), &leak_opts, false) {
        Ok(lp) => {
            if lp["leaks"].as_str() != Some("yes") {
                errs.push(format!("leak check on PlannerBot (real copies) found no leak: {}", json_compact(&lp)));
            }
        }
        Err(e) => errs.push(format!("leak check on PlannerBot: {}", e)),
    }
    // Tier bands.
    let (blo, bhi) = Tier::band("normal");
    if (blo - 42.4).abs() > 0.1 || (bhi - 84.9).abs() > 0.1 {
        errs.push(format!("normal band [{}, {})", blo, bhi));
    }
    errs
}
