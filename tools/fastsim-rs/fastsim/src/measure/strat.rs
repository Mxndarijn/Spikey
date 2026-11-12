//! Port of Measure/Strat.cs: the room-stratified estimator (docs/BOT_TESTING.md).
//!
//! The rooms a run meets come from the spine, an RNG of its own, so how
//! often each room comes up per visit (pi_s) is a property of the game, not
//! of the bot: it is counted once from the bank's visits. The death rate per
//! 100 points on a score range is then
//!     Q = 100 * sum_s pi_s p_s / sum_s pi_s l_s
//! with p_s the chance to die in a visit of stratum s and l_s the points a
//! visit gives. p_s and l_s come from trials: the bank's entry snapshot of a
//! visit, the spine replaced (so the room and everything it will draw is new,
//! drawn the way the game draws it, arrival checks included), then the bot
//! from that tick to the next room. Trials go where they buy the most
//! precision per CPU second (Neyman allocation: n_s ~ pi_s sd_s / sqrt(cost_s)),
//! so the rooms that kill get most of them and the safe rooms only a few.
//!
//! Doubles are summed in the C# (LINQ) order; dictionaries that C# enumerates keep
//! their insertion order here (`OrdMap`), and allocation uses a port of .NET's
//! PriorityQueue, so plans, jobs and numbers match the C# ones.
use std::collections::{HashMap, HashSet};
use std::io::Write;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

use rayon::prelude::*;
use serde_json::{json, Value};
use sim::prelude::*;

use super::bank::{Bank, Visit};
use super::{jr, nmax, OrdMap, PriorityQueue};
use crate::dotnet_random::DotnetRandom;
use crate::yardstick::bots::BotSpec;
use crate::yardstick::fmt_num;

/// One trial: a bot plays one room (kind "room") or the rest of a run (kind
/// "run") from a bank entry snapshot, with the room drawn again. `k` names the
/// redraw: the trial's spine is `new SimRng(Strat.spine_seed(seed, tick, k))`
/// and its bot seed `Strat.bot_seed(...)`; k = -1 is the bank run's own visit
/// (real spine, real bot). Rows of `*.trials.tsv` (format `flapjaw_trials` 1).
#[derive(Clone, Debug, PartialEq)]
pub struct Trial {
    pub bot: String,
    pub kind: String,
    pub seed: i64,
    pub tick: i64,
    pub k: i64,
    pub key: String,
    pub died: bool,
    pub censored: bool,
    pub points: i64,
    pub ticks: i64,
    pub ms: f64,
}

impl Trial {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        bot: &str,
        kind: &str,
        seed: i64,
        tick: i64,
        k: i64,
        key: &str,
        died: bool,
        censored: bool,
        points: i64,
        ticks: i64,
        ms: f64,
    ) -> Trial {
        Trial {
            bot: bot.to_string(),
            kind: kind.to_string(),
            seed,
            tick,
            k,
            key: key.to_string(),
            died,
            censored,
            points,
            ticks,
            ms,
        }
    }
}

/// A trial job: (bank run, tick, tap, k).
pub type Job = (usize, i64, bool, i64);

pub struct Strat;

/// LINQ `Sum` over doubles: left to right from 0.
fn sum(xs: impl Iterator<Item = f64>) -> f64 {
    let mut s = 0.0;
    for x in xs {
        s += x;
    }
    s
}

/// LINQ `Average` over doubles (callers guard the empty case, as in C#).
fn avg(xs: impl Iterator<Item = f64>) -> f64 {
    let mut s = 0.0;
    let mut n = 0i64;
    for x in xs {
        s += x;
        n += 1;
    }
    s / n as f64
}

impl Strat {
    pub const PLATEAU: i64 = 40;
    pub const FORMAT: &'static str = "flapjaw_trials";
    pub const VERSION: i32 = 1;
    /// Strata with a smaller visit share are not tried; their p comes from the
    /// bank (`imputed` in the estimate says how much of pi that is).
    pub const MIN_SHARE: f64 = 0.002;
    pub const MIN_TRIALS: i32 = 3;
    pub const SHRINK: f64 = 2.0;

    pub fn spine_seed(seed: i64, tick: i64, k: i64) -> i64 {
        SimHash::mix(SimHash::mix(SimHash::mix(SimHash::SEED, seed), tick), k)
    }

    pub fn bot_seed(seed: i64, tick: i64, k: i64) -> i64 {
        SimHash::mix(Self::spine_seed(seed, tick, k), 0x5EED)
    }

    pub fn plateau(key: &str) -> bool {
        !key.contains("@b")
    }

    pub fn in_range(key: &str, range: &str) -> bool {
        match range {
            "plateau" => Self::plateau(key),
            "ramp" => !Self::plateau(key),
            // One score class ("@b0", "@b10", "@b20", "@b30", "@p", "@t1"...).
            _ if range.starts_with('@') => key.ends_with(range),
            _ => true,
        }
    }

    // ------------------------------------------------------------- playing

    /// The entry state with the room drawn again: None when the step did not enter a room.
    pub fn redraw(pre: &GameSim, tap: bool, x: i64) -> Option<GameSim> {
        let mut c = pre.clone_deep();
        c._spine = SimRng::new(x);
        let ri = c.state.room_index;
        c.step(tap);
        if c.state.room_index != ri && !c.is_over() {
            Some(c)
        } else {
            None
        }
    }

    /// Plays one trial from an entry state (after the entry step).
    pub fn play(bot: &BotSpec, kind: &str, mut sim: GameSim, seed: i64, tick: i64, k: i64, cap: i64) -> Trial {
        let key = Bank::key(&sim);
        let mut decide = (bot.make)(Self::bot_seed(seed, tick, k));
        let ri = sim.state.room_index;
        let s0 = sim.state.score;
        let t0 = sim.state.tick;
        let clock = Instant::now();
        let mut left = false;
        while sim.state.tick < cap && !sim.is_over() {
            let tap = decide(&sim);
            sim.step(tap);
            if kind == "room" && sim.state.room_index != ri {
                left = true;
                break;
            }
        }
        let died = sim.is_over();
        Trial::new(
            &bot.name,
            kind,
            seed,
            tick,
            k,
            &key,
            died,
            !died && !left,
            sim.state.score - s0,
            sim.state.tick - t0,
            clock.elapsed().as_secs_f64() * 1000.0,
        )
    }

    /// Plays the trials `jobs` (bank run, tick, tap, k) for `bot`, in parallel (rayon's
    /// global pool), results in job order.
    pub fn run_trials(bot: &BotSpec, kind: &str, bank: &Bank, jobs: &[Job], cap: i64, log: bool) -> Vec<Trial> {
        // One replay per bank run gives every snapshot it needs; the trials then run one per thread.
        let mut by_run: OrdMap<usize, Vec<i64>> = OrdMap::new();
        for j in jobs {
            by_run.entry_or(j.0, Vec::new).push(j.1);
        }
        let groups: Vec<(usize, Vec<i64>)> = by_run.into_vec();
        let parts: Vec<(usize, HashMap<i64, GameSim>)> =
            groups.into_par_iter().map(|(run, ticks)| (run, Bank::replay_all(&bank.runs[run], ticks))).collect();
        let mut pre: HashMap<(usize, i64), GameSim> = HashMap::new();
        for (run, p) in parts {
            for (t, s) in p {
                pre.insert((run, t), s);
            }
        }
        let done = AtomicUsize::new(0);
        let n = jobs.len();
        let res: Vec<Option<Trial>> = (0..n)
            .into_par_iter()
            .map(|i| {
                let (run, tick, tap, k) = jobs[i];
                let seed = bank.runs[run].seed;
                let c = Self::redraw(&pre[&(run, tick)], tap, Self::spine_seed(seed, tick, k));
                let t = c.map(|c| Self::play(bot, kind, c, seed, tick, k, cap));
                let d = done.fetch_add(1, Ordering::SeqCst) + 1;
                if log && (d % 50 == 0 || d == n) {
                    eprintln!("  {}: {}/{} trials", bot.name, d, n);
                }
                t
            })
            .collect();
        res.into_iter().flatten().collect()
    }

    /// The bank's own visits as trials of the bank's bot (k = -1).
    pub fn bank_trials(bank: &Bank) -> Vec<Trial> {
        let mut res = Vec::new();
        for r in &bank.runs {
            for v in &r.visits {
                res.push(Trial::new(
                    &bank.bot, "room", r.seed, v.tick, -1, &v.key, v.died, v.censored, v.points, v.ticks, v.ms,
                ));
            }
        }
        res
    }

    // --------------------------------------------------------------- files

    pub const HEADER: &'static str = "bot\tkind\tseed\ttick\tk\tstratum\tdied\tcensored\tpoints\tticks\tms";

    pub fn append(path: &str, trials: &[Trial]) -> Result<(), String> {
        let fresh = !std::path::Path::new(path).exists();
        super::create_parent(path)?;
        let mut sb = String::new();
        if fresh {
            sb.push_str(&format!(
                "# {} {} gameplay {}\n{}\n",
                Self::FORMAT,
                Self::VERSION,
                SimConfig::GAMEPLAY_VERSION,
                Self::HEADER
            ));
        }
        for t in trials {
            sb.push_str(&format!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                t.bot,
                t.kind,
                t.seed,
                t.tick,
                t.k,
                t.key,
                if t.died { 1 } else { 0 },
                if t.censored { 1 } else { 0 },
                t.points,
                t.ticks,
                fmt_num(t.ms, "F1")
            ));
        }
        let mut f =
            std::fs::OpenOptions::new().create(true).append(true).open(path).map_err(|e| format!("{}: {}", path, e))?;
        f.write_all(sb.as_bytes()).map_err(|e| format!("{}: {}", path, e))
    }

    pub fn load(path: &str) -> Vec<Trial> {
        let mut res = Vec::new();
        let text = match std::fs::read_to_string(path) {
            Ok(t) => t,
            Err(_) => return res,
        };
        for raw in text.trim_start_matches('\u{feff}').lines() {
            if raw.starts_with('#') || raw.starts_with("bot\t") || raw.trim().is_empty() {
                continue;
            }
            let c: Vec<&str> = raw.split('\t').collect();
            let l = |i: usize| -> i64 {
                c[i].trim().parse().unwrap_or_else(|_| panic!("{}: bad number '{}' in '{}'", path, c[i], raw))
            };
            res.push(Trial::new(
                c[0],
                c[1],
                l(2),
                l(3),
                l(4),
                c[5],
                c[6] == "1",
                c[7] == "1",
                l(8),
                l(9),
                c[10].trim().parse().unwrap_or_else(|_| panic!("{}: bad number '{}' in '{}'", path, c[10], raw)),
            ));
        }
        res
    }

    // ------------------------------------------------------------ estimate

    /// Visit shares pi_s over `range` from the bank's visits (all bots' banks agree up to noise),
    /// in the order the strata first come up.
    pub fn shares(bank: &Bank, range: &str) -> (OrdMap<String, f64>, i32) {
        let mut n: OrdMap<String, i32> = OrdMap::new();
        let mut total: i32 = 0;
        for r in &bank.runs {
            for v in &r.visits {
                if Self::in_range(&v.key, range) {
                    *n.entry_or(v.key.clone(), || 0) += 1;
                    total += 1;
                }
            }
        }
        let mut pi = OrdMap::new();
        for (k, c) in n.iter() {
            pi.insert(k.clone(), *c as f64 / 1.max(total) as f64);
        }
        (pi, total)
    }

    /// Q with its interval from `trials` (one bot, kind "room") and the bank's shares.
    /// `prior`: per-stratum p for strata the bot has no trials in (None = the trials' pooled p).
    pub fn estimate(bank: &Bank, trials: &[Trial], range: &str, prior: Option<&HashMap<String, (f64, f64)>>) -> Est {
        let (pi, visits) = Self::shares(bank, range);
        let mut by: OrdMap<String, Vec<&Trial>> = OrdMap::new();
        for t in trials {
            if t.kind == "room" && !t.censored && Self::in_range(&t.key, range) {
                by.entry_or(t.key.clone(), Vec::new).push(t);
            }
        }
        let mut e = Est {
            range: range.to_string(),
            visits,
            bot: trials.first().map(|t| t.bot.clone()).unwrap_or_default(),
            ..Est::default()
        };
        let all: Vec<&Trial> = by.values().flat_map(|x| x.iter().copied()).collect();
        let n_all = all.len() as i32;
        let d_all = all.iter().filter(|t| t.died).count() as i32;
        let pooled_p = (d_all as f64 + 0.5) / (n_all as f64 + 1.0);
        let pooled_l =
            if !all.is_empty() { avg(all.iter().map(|t| t.points as f64)) } else { SimConfig::POINTS_PER_ROOM as f64 };
        for (key, share) in pi.iter() {
            let mut c = Cell { key: key.clone(), pi: *share, ..Cell::default() };
            if let Some(l) = by.get(key) {
                c.n = l.len() as i32;
                c.d = l.iter().filter(|t| t.died).count() as i32;
                c.pts = sum(l.iter().map(|t| t.points as f64));
                c.pts2 = sum(l.iter().map(|t| t.points as f64 * t.points as f64));
                c.ms = sum(l.iter().map(|t| t.ms));
            }
            e.cells.push(c);
        }
        let prior_of = |key: &str| prior.and_then(|p| p.get(key).copied());
        let mut num = 0.0;
        let mut den = 0.0;
        for c in e.cells.iter_mut() {
            let mut p = c.p();
            let mut l = c.l();
            if c.n == 0 {
                c.imputed = true;
                e.imputed_share += c.pi;
                (p, l) = prior_of(&c.key).unwrap_or((pooled_p, pooled_l));
            }
            num += c.pi * p;
            den += c.pi * l;
        }
        let qpt = num / nmax(1e-12, den);
        // The rate a stratum shrinks toward: its own bank rate when there is one, else the
        // visit-weighted rate (never the trials' pooled rate: allocation makes that the deadly rooms').
        let p_visit = qpt
            * sum(pi.iter().map(|(k, v)| {
                v * match by.get(k) {
                    Some(lv) if !lv.is_empty() => avg(lv.iter().map(|t| t.points as f64)),
                    _ => pooled_l,
                }
            }));
        let target = |key: &str| match prior_of(key) {
            Some(pr0) => pr0.0,
            None => p_visit,
        };
        // Delta method: Q - q ~ sum_s pi_s (p_s - q l_s) / den, plus the error in pi itself.
        let mut var = 0.0;
        let mut var_pi = 0.0;
        for c in &e.cells {
            if c.n == 0 {
                // Imputed from the bank (another bot's visits, about pi * visits of them): its error counts too.
                let (pp, _) = prior_of(&c.key).unwrap_or((pooled_p, pooled_l));
                let nb = nmax(1.0, c.pi * visits as f64);
                let pb = (pp * nb + Self::SHRINK * p_visit) / (nb + Self::SHRINK);
                var += c.pi * c.pi * pb * (1.0 - pb) / nb;
                continue;
            }
            // Shrunk toward the pooled rate (2 pseudo-visits): a stratum with no deaths yet is
            // not certain, but 118 strata must not add 59 phantom deaths either.
            let pt = (c.d as f64 + Self::SHRINK * target(&c.key)) / (c.n as f64 + Self::SHRINK);
            let mean_pts = c.l();
            let var_pts =
                if c.n > 1 { nmax(0.0, (c.pts2 - c.n as f64 * mean_pts * mean_pts) / (c.n - 1) as f64) } else { 0.0 };
            // died and points are tied (a death ends the visit early): cov from the data.
            let l = by.get(&c.key).unwrap();
            let cp = c.p();
            let cov = if c.n > 1 {
                sum(l.iter().map(|t| ((if t.died { 1 } else { 0 }) as f64 - cp) * (t.points as f64 - mean_pts)))
                    / (c.n - 1) as f64
            } else {
                0.0
            };
            let vz = pt * (1.0 - pt) + qpt * qpt * var_pts - 2.0 * qpt * cov;
            var += c.pi * c.pi * nmax(vz, pt * (1.0 - pt) * 0.25) / c.n as f64;
            let g = c.p() - qpt * c.l();
            var_pi += c.pi * g * g;
            let mut zs: OrdMap<(i64, i64, i64), f64> = OrdMap::new();
            for t in l {
                zs.insert((t.seed, t.tick, t.k), (if t.died { 1 } else { 0 }) as f64 - qpt * t.points as f64);
            }
            e.z.insert(c.key.clone(), zs);
        }
        var += var_pi / 1.max(visits) as f64;
        let se_pt = var.sqrt() / nmax(1e-12, den);
        e.q = 100.0 * qpt;
        e.se = 100.0 * se_pt;
        e.se_log = if qpt > 0.0 { se_pt / qpt } else { f64::INFINITY };
        e.lo = e.q * (-1.96 * e.se_log).exp();
        e.hi = e.q * (1.96 * e.se_log).exp();
        e.trials = n_all;
        e.deaths = d_all;
        e.ms = sum(by.values().flat_map(|x| x.iter()).map(|t| t.ms));
        e
    }

    /// b vs a: rate ratio b/a with its interval. Trials both bots played from
    /// the same (seed, tick, k) are paired: their covariance is used.
    pub fn ratio(a: &Est, b: &Est, _bank: &Bank) -> Ratio {
        let ra = a.q / 100.0;
        let rb = b.q / 100.0;
        let den_a = sum(a.cells.iter().map(|c| c.pi * if c.n > 0 { c.l() } else { 0.0 }));
        let den_b = sum(b.cells.iter().map(|c| c.pi * if c.n > 0 { c.l() } else { 0.0 }));
        let mut cov = 0.0;
        let mut sx = 0.0;
        let mut sy = 0.0;
        let mut sxy = 0.0;
        let mut paired: i32 = 0;
        for ca in &a.cells {
            let cb = match b.cells.iter().find(|c| c.key == ca.key) {
                Some(c) => c,
                None => continue,
            };
            let (za, zb) = match (a.z.get(&ca.key), b.z.get(&ca.key)) {
                (Some(za), Some(zb)) => (za, zb),
                _ => continue,
            };
            let both: Vec<(i64, i64, i64)> = za.keys().filter(|k| zb.contains_key(k)).copied().collect();
            if both.len() < 2 {
                continue;
            }
            let ma = avg(both.iter().map(|k| za[k]));
            let mb = avg(both.iter().map(|k| zb[k]));
            let cv = sum(both.iter().map(|k| (za[k] - ma) * (zb[k] - mb))) / (both.len() - 1) as f64;
            cov += ca.pi * ca.pi * cv * both.len() as f64 / (ca.n as f64 * cb.n as f64);
            sx += sum(both.iter().map(|k| (za[k] - ma) * (za[k] - ma)));
            sy += sum(both.iter().map(|k| (zb[k] - mb) * (zb[k] - mb)));
            sxy += sum(both.iter().map(|k| (za[k] - ma) * (zb[k] - mb)));
            paired += both.len() as i32;
        }
        let cov_log = if ra > 0.0 && rb > 0.0 { cov / (den_a * den_b * ra * rb) } else { 0.0 };
        let mut v = a.se_log * a.se_log + b.se_log * b.se_log - 2.0 * cov_log;
        v = nmax(v, 1e-12);
        let se = v.sqrt();
        let lr = (rb / ra).ln();
        let rho = if sx > 0.0 && sy > 0.0 { sxy / (sx * sy).sqrt() } else { 0.0 };
        Ratio {
            r: rb / ra,
            lo: (lr - 1.96 * se).exp(),
            hi: (lr + 1.96 * se).exp(),
            z: lr / se,
            se_log: se,
            rho,
            paired,
        }
    }

    // ---------------------------------------------------------- allocation

    /// The next `budget_ms` of trials: Neyman allocation, greedily, by the
    /// variance each trial removes per CPU ms. `arms`: the trials so far of
    /// each bot being measured together (paired: the same jobs for each).
    /// `prior` (the bank's p, l and cost per stratum) stands in for strata a bot has no trials in yet.
    pub fn allocate(
        bank: &Bank,
        range: &str,
        arms: &[Vec<Trial>],
        budget_ms: f64,
        prior: &HashMap<String, (f64, f64, f64)>,
    ) -> OrdMap<String, i32> {
        let (pi, _) = Self::shares(bank, range);
        let mut plan: OrdMap<String, i32> = OrdMap::new();
        let keys: Vec<String> = pi.iter().filter(|(_, v)| **v >= Self::MIN_SHARE).map(|(k, _)| k.clone()).collect();
        if keys.is_empty() {
            return plan;
        }
        let dflt = (0.01, SimConfig::POINTS_PER_ROOM as f64, 1000.0);
        // Per stratum and arm: trials so far, smoothed p (toward the prior), cost.
        let mut n: HashMap<String, Vec<i32>> = HashMap::new();
        let mut v: HashMap<String, f64> = HashMap::new();
        let mut cost: HashMap<String, f64> = HashMap::new();
        let mut q_prior = 0.0;
        let mut l_prior = 0.0;
        for k in &keys {
            let pr = prior.get(k).copied().unwrap_or(dflt);
            q_prior += pi[k] * pr.0;
            l_prior += pi[k] * pr.1;
        }
        let q = q_prior / nmax(1e-9, l_prior);
        for k in &keys {
            let pr = prior.get(k).copied().unwrap_or(dflt);
            let mut counts = vec![0i32; arms.len()];
            let mut vs = 0.0;
            let mut cs = 0.0;
            for a in 0..arms.len() {
                let mine: Vec<&Trial> =
                    arms[a].iter().filter(|t| t.key == *k && t.kind == "room" && !t.censored).collect();
                counts[a] = mine.len() as i32;
                const M: f64 = 4.0;
                let p = (mine.iter().filter(|t| t.died).count() as f64 + M * pr.0) / (mine.len() as f64 + M);
                // Relative variance (log scale), so arms with different rates weigh alike.
                vs += p * (1.0 - p) / nmax(1e-9, q * q);
                cs += if !mine.is_empty() { avg(mine.iter().map(|t| t.ms)) } else { pr.2 };
            }
            n.insert(k.clone(), counts);
            v.insert(k.clone(), vs);
            cost.insert(k.clone(), nmax(1.0, cs));
        }
        // Greedy: one trial (in every arm) at a time to the stratum that gains most per ms.
        let gain = |k: &str, plan: &OrdMap<String, i32>| -> f64 {
            let m = *n[k].iter().min().unwrap() + plan.get(k).copied().unwrap_or(0);
            let mut g = pi[k] * pi[k] * v[k] * if m == 0 { 1e6 } else { 1.0 / m as f64 - 1.0 / (m + 1) as f64 };
            if m < Self::MIN_TRIALS {
                g *= 1e3;
            }
            g / cost[k]
        };
        let mut pq: PriorityQueue<String> = PriorityQueue::new();
        for k in &keys {
            pq.enqueue(k.clone(), -gain(k, &plan));
        }
        let mut spent = 0.0;
        while spent < budget_ms && pq.count() > 0 {
            let k = pq.dequeue();
            *plan.entry_or(k.clone(), || 0) += 1;
            spent += cost[&k];
            let g = -gain(&k, &plan);
            pq.enqueue(k, g);
        }
        plan
    }

    /// The bank's own p, l and cost per stratum (a prior for allocation and imputation).
    pub fn bank_prior(bank: &Bank) -> HashMap<String, (f64, f64, f64)> {
        let mut res = HashMap::new();
        let all: Vec<&Visit> = bank.runs.iter().flat_map(|r| r.visits.iter()).filter(|v| !v.censored).collect();
        let p0 = (all.iter().filter(|v| v.died).count() as f64 + 0.5) / (all.len() as f64 + 1.0);
        let mut groups: OrdMap<String, Vec<&Visit>> = OrdMap::new();
        for v in &all {
            groups.entry_or(v.key.clone(), Vec::new).push(v);
        }
        for (key, g) in groups.iter() {
            let n = g.len() as f64;
            let d = g.iter().filter(|v| v.died).count() as f64;
            res.insert(
                key.clone(),
                (
                    (d + Self::SHRINK * p0) / (n + Self::SHRINK),
                    avg(g.iter().map(|v| v.points as f64)),
                    avg(g.iter().map(|v| v.ms)),
                ),
            );
        }
        res
    }

    /// Turns a plan (trials per stratum) into jobs from the pools, growing them when short.
    pub fn jobs(pools: &mut Pools, plan: &mut OrdMap<String, i32>, order: &mut DotnetRandom) -> Vec<Job> {
        let mut res = Vec::new();
        for _round in 0..6 {
            let mut short_: Vec<String> = Vec::new();
            let list: Vec<(String, i32)> = plan.iter().map(|(k, v)| (k.clone(), *v)).collect();
            for (key, want) in list {
                let mut got = 0;
                while got < want {
                    match pools.take(&key, order) {
                        Some(e) => {
                            res.push(e);
                            got += 1;
                        }
                        None => break,
                    }
                }
                if got < want {
                    short_.push(key.clone());
                }
                plan.insert(key, want - got);
            }
            if short_.is_empty() {
                break;
            }
            let more = 4.max(pools.tried_k);
            pools.grow(more);
        }
        res
    }
}

/// Redraws of bank entries that land in each stratum, found by trying
/// spine seeds k = 0, 1, ... on every entry (one step each, no bot). A
/// pool's members are used once each, so no two trials repeat.
pub struct Pools<'a> {
    _bank: &'a Bank,
    _range: String,
    pub by_key: HashMap<String, Vec<Job>>,
    pub tried_k: i32,
    pub redraws: i64,
    _used: HashSet<(i64, i64, i64)>,
}

impl<'a> Pools<'a> {
    pub fn new(bank: &'a Bank, range: &str) -> Pools<'a> {
        Pools {
            _bank: bank,
            _range: range.to_string(),
            by_key: HashMap::new(),
            tried_k: 0,
            redraws: 0,
            _used: HashSet::new(),
        }
    }

    /// Tries `more` further spine seeds on every entry whose class can give `range`.
    pub fn grow(&mut self, more: i32) {
        let bank = self._bank;
        let range = self._range.clone();
        let k0 = self.tried_k as i64;
        let found: Vec<Vec<(String, Job)>> = (0..bank.runs.len())
            .into_par_iter()
            .map(|i| {
                let mine: Vec<&Visit> =
                    bank.runs[i].visits.iter().filter(|v| Strat::in_range(&v.key, &range)).collect();
                let mut f = Vec::new();
                if mine.is_empty() {
                    return f;
                }
                let pre = Bank::replay_all(&bank.runs[i], mine.iter().map(|v| v.tick));
                for v in &mine {
                    for k in k0..k0 + more as i64 {
                        if let Some(c) =
                            Strat::redraw(&pre[&v.tick], v.tap, Strat::spine_seed(bank.runs[i].seed, v.tick, k))
                        {
                            f.push((Bank::key(&c), (i, v.tick, v.tap, k)));
                        }
                    }
                }
                f
            })
            .collect();
        for f in found {
            for (key, e) in f {
                if !Strat::in_range(&key, &self._range) {
                    continue;
                }
                self.by_key.entry(key).or_default().push(e);
                self.redraws += 1;
            }
        }
        self.tried_k += more;
    }

    /// The next unused member of `key`'s pool (members in a fixed shuffled order).
    pub fn take(&mut self, key: &str, order: &mut DotnetRandom) -> Option<Job> {
        let l = self.by_key.get_mut(key)?;
        for a in 0..l.len() {
            let j = a + order.next((l.len() - a) as i32) as usize;
            l.swap(a, j);
            let e = l[a];
            if self._used.insert((self._bank.runs[e.0].seed, e.1, e.3)) {
                return Some(e);
            }
        }
        None
    }

    pub fn mark_used(&mut self, seed: i64, tick: i64, k: i64) {
        self._used.insert((seed, tick, k));
    }
}

#[derive(Clone, Debug, Default)]
pub struct Cell {
    pub key: String,
    pub pi: f64,
    pub n: i32,
    pub d: i32,
    pub pts: f64,
    pub pts2: f64,
    pub ms: f64,
    pub imputed: bool,
}

impl Cell {
    pub fn p(&self) -> f64 {
        if self.n == 0 {
            0.0
        } else {
            self.d as f64 / self.n as f64
        }
    }
    pub fn l(&self) -> f64 {
        if self.n == 0 {
            0.0
        } else {
            self.pts / self.n as f64
        }
    }
    #[allow(dead_code)]
    pub fn cost(&self) -> f64 {
        if self.n == 0 {
            0.0
        } else {
            self.ms / self.n as f64
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Est {
    pub bot: String,
    pub range: String,
    pub q: f64,
    pub lo: f64,
    pub hi: f64,
    pub se: f64,
    pub se_log: f64,
    pub imputed_share: f64,
    pub trials: i32,
    pub deaths: i32,
    pub visits: i32,
    pub ms: f64,
    pub cells: Vec<Cell>,
    /// Linearized per-trial values z = died - q * points / 100 by stratum (for paired covariances).
    pub z: HashMap<String, OrdMap<(i64, i64, i64), f64>>,
}

/// `OrderByDescending(c => c.pi * c.p)` (a stable sort) over the cells with deaths.
pub fn killers(cells: &[Cell]) -> Vec<&Cell> {
    let mut top: Vec<&Cell> = cells.iter().filter(|c| c.d > 0).collect();
    top.sort_by(|a, b| super::dotnet_cmp(b.pi * b.p(), a.pi * a.p()));
    top
}

impl Est {
    pub fn json(&self) -> Value {
        let total = sum(self.cells.iter().map(|x| x.pi * x.p()));
        let top: Vec<Value> = killers(&self.cells)
            .into_iter()
            .take(12)
            .map(|c| {
                json!({
                    "stratum": c.key, "share": jr(c.pi, 4), "trials": c.n, "deaths": c.d,
                    "p": jr(c.p(), 4), "of_rate": jr(c.pi * c.p() / nmax(1e-12, total), 3),
                })
            })
            .collect();
        json!({
            "bot": self.bot, "range": self.range, "per100": jr(self.q, 4), "lo": jr(self.lo, 4), "hi": jr(self.hi, 4),
            "rel_halfwidth": jr(1.96 * self.se_log, 3), "trials": self.trials, "deaths": self.deaths,
            "cpu_s": jr(self.ms / 1000.0, 1), "strata": self.cells.iter().filter(|c| c.n > 0).count(),
            "imputed_share": jr(self.imputed_share, 4),
            "bank_visits": self.visits, "killers": top,
        })
    }

    pub fn text(&self) -> String {
        format!(
            "{:<28} {:<8} {} [{}, {}] per 100  (+-{}%, {} trials, {} deaths, {} CPU s, imputed {}% of visits)",
            self.bot,
            self.range,
            fmt_num(self.q, "F4"),
            fmt_num(self.lo, "F4"),
            fmt_num(self.hi, "F4"),
            fmt_num(100.0 * 1.96 * self.se_log, "F0"),
            self.trials,
            self.deaths,
            fmt_num(self.ms / 1000.0, "F0"),
            fmt_num(100.0 * self.imputed_share, "F1")
        )
    }
}

/// C# record Ratio(r, lo, hi, z, se_log, rho, paired).
#[derive(Clone, Copy, Debug)]
pub struct Ratio {
    pub r: f64,
    pub lo: f64,
    pub hi: f64,
    pub z: f64,
    pub se_log: f64,
    pub rho: f64,
    pub paired: i32,
}
