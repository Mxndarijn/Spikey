//! Port of RL/Review.cs `horizon` and `honest`.
//!   horizon  how far ahead a player must see: a peeking search that only ever looks `h` ticks
//!            ahead (re-planned every `k` ticks), with --cut 1 never past the next bounce
//!            (+8 ticks).
//!   honest   the BlindPlanner on full runs: deaths per 100 points by score band, and how the
//!            last look before each death ended.
use std::collections::VecDeque;
use std::time::Instant;

use rayon::prelude::*;
use sim::prelude::*;

use super::{configure, dbl, pct, room_name};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::speed::Opts;
use super::fixed;

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

/// C# `GroupBy(key)` then `OrderByDescending(g => g.Count())`: groups in first-appearance order,
/// a stable sort by size.
pub fn groups_by_count<T, K: PartialEq + Clone>(xs: &[T], key: impl Fn(&T) -> K) -> Vec<(K, Vec<&T>)> {
    let mut gs = groups(xs, key);
    gs.sort_by(|a, b| b.1.len().cmp(&a.1.len()));
    gs
}

/// C# `GroupBy(key)`: groups in first-appearance order.
pub fn groups<T, K: PartialEq + Clone>(xs: &[T], key: impl Fn(&T) -> K) -> Vec<(K, Vec<&T>)> {
    let mut gs: Vec<(K, Vec<&T>)> = Vec::new();
    for x in xs {
        let k = key(x);
        match gs.iter_mut().find(|g| g.0 == k) {
            Some(g) => g.1.push(x),
            None => gs.push((k, vec![x])),
        }
    }
    gs
}

/// C# `{x,n}`: right-aligned in `n` characters (left-aligned for a negative `n`).
pub fn pad(s: impl ToString, n: i32) -> String {
    let s = s.to_string();
    if n < 0 {
        format!("{:<w$}", s, w = (-n) as usize)
    } else {
        format!("{:>w$}", s, w = n as usize)
    }
}

pub fn horizon(h: i64, k: i32, cut: bool, seeds: i32, cap: i64) {
    let clock = Instant::now();
    let res: Vec<(i64, i64, bool, String)> = (0..seeds as i64)
        .into_par_iter()
        .map(|i| {
            let mut sim = GameSim::new(i + 1);
            let mut plan: VecDeque<bool> = VecDeque::new();
            let mut since = k;
            let mut n: i64 = 0;
            while !sim.is_over() && n < cap {
                if !sim.state.started {
                    sim.step(true);
                    n += 1;
                    continue;
                }
                if since >= k || plan.is_empty() {
                    let mut want = h;
                    if cut {
                        want = h.min(sim.steps_to_wall(if sim.state.vx > 0 { 1 } else { 0 }) + 8);
                    }
                    let mut found: Option<Vec<u8>> = None;
                    // The longest look that still finds a way to live.
                    let mut t = want;
                    while t >= 2 && found.is_none() {
                        let mut s = SurvivalSearch::new();
                        s.max_level = 0;
                        if s.run(&sim, t) {
                            found = Some(s.best_inputs.clone());
                        }
                        t = t * 3 / 4;
                    }
                    plan.clear();
                    if let Some(f) = found {
                        for b in f {
                            plan.push_back(b != 0);
                        }
                    }
                    since = 0;
                }
                let tap = !plan.is_empty() && plan.pop_front().unwrap();
                sim.step(tap);
                since += 1;
                n += 1;
            }
            (sim.state.score, n, sim.is_over(), sim.room.def().id.to_string())
        })
        .collect();
    let pts: i64 = res.iter().map(|r| r.0).sum();
    let deaths = res.iter().filter(|r| r.2).count() as i64;
    let ticks: i64 = res.iter().map(|r| r.1).sum();
    // Constant death rate per point d: median = ln 2 / d.
    let med = if deaths == 0 {
        format!("> {} (no deaths; 95% bound)", fixed(pts as f64 * 0.69 / 3.0, 0))
    } else {
        fixed(0.693 * pts as f64 / deaths as f64, 0)
    };
    let dead: Vec<&(i64, i64, bool, String)> = res.iter().filter(|r| r.2).collect();
    let rooms: Vec<String> =
        groups_by_count(&dead, |r| r.3.clone()).iter().take(4).map(|g| format!("{} {}", g.0, g.1.len())).collect();
    println!(
        "horizon {} ticks{}: {} deaths in {} points ({} ticks, {} runs) -> median about {}  [{}]  {} s",
        pad(h, 3),
        if cut { ", cut at the bounce" } else { "" },
        deaths,
        pts,
        ticks,
        seeds,
        med,
        rooms.join(", "),
        fixed(clock.elapsed().as_secs_f64(), 0)
    );
}

struct Res {
    points: i64,
    ticks: i64,
    dead: bool,
    room: String,
    look: i32,
    cause: String,
    seed: i64,
    /// Ticks since the run last scored (a run alive at the cap that stopped scoring is stuck).
    since_score: i64,
}

/// The BlindPlanner (Bots/BlindPlanner.cs) on full runs: deaths per 100 points by score band,
/// and how the last look before each death ended.
pub fn honest(opts: &Opts, seeds: i32, cap: i64) {
    let first = l(opts, "first", 0);
    let threads = rayon::current_num_threads();
    let clock = Instant::now();
    let setup = {
        let mut b = BlindPlanner::new(first + 1);
        configure(&mut b, opts)
    };
    let runs: Vec<(Res, [i64; 5])> = (0..seeds as i64)
        .into_par_iter()
        .map(|i| {
            let mut sim = GameSim::new(first + i + 1);
            let mut bot = BlindPlanner::new(first + i + 1);
            configure(&mut bot, opts);
            let mut ticks: i64 = 0;
            let (mut last_score, mut scored_at) = (sim.state.score, 0i64);
            while !sim.is_over() && ticks < cap {
                let tap = bot.decide(&sim);
                sim.step(tap);
                ticks += 1;
                if sim.state.score != last_score {
                    last_score = sim.state.score;
                    scored_at = ticks;
                }
            }
            let r = Res {
                points: sim.state.score,
                ticks,
                dead: sim.is_over(),
                room: room_name(&sim),
                look: bot.last_look,
                seed: first + i + 1,
                since_score: ticks - scored_at,
                cause: if sim.is_over() {
                    DeathCause::NAMES[sim.state.death_cause as usize].to_string()
                } else {
                    String::new()
                },
            };
            (r, [bot.looks, bot.fine_looks, bot.short_looks, bot.no_looks, bot.steps])
        })
        .collect();
    let (mut looks, mut fine, mut shorter, mut none, mut psteps) = (0i64, 0i64, 0i64, 0i64, 0i64);
    for (_, c) in &runs {
        looks += c[0];
        fine += c[1];
        shorter += c[2];
        none += c[3];
        psteps += c[4];
    }
    let res: Vec<Res> = runs.into_iter().map(|(r, _)| r).collect();
    let pts: i64 = res.iter().map(|r| r.points).sum();
    let deaths = res.iter().filter(|r| r.dead).count() as i64;
    let all: i64 = res.iter().map(|r| r.ticks).sum();
    let secs = clock.elapsed().as_secs_f64();
    let points: Vec<i64> = res.iter().map(|r| r.points).collect();
    println!(
        "blind planner [{}], seeds {}..{}, cap {}: {} deaths in {} points = {} per 100; median of the runs {}, {} alive at the cap; {} ticks/s per thread, {} search steps per tick, {} s",
        setup,
        first + 1,
        first + seeds as i64,
        cap,
        deaths,
        pts,
        fixed(100.0 * deaths as f64 / 1.max(pts) as f64, 3),
        dbl(pct(&points, 0.5)),
        res.iter().filter(|r| !r.dead).count(),
        fixed(all as f64 / secs / threads as f64, 0),
        psteps / 1.max(all),
        fixed(secs, 0)
    );
    if opts.contains_key("scores") {
        println!(
            "  scores: {}",
            res.iter().map(|r| format!("{}{}", r.points, if r.dead { "" } else { "+" })).collect::<Vec<_>>().join(" ")
        );
    }
    // `--ends 1`: where each run alive at the cap ended, and how long since it last scored.
    if opts.contains_key("ends") {
        for r in res.iter().filter(|r| !r.dead) {
            println!("  end seed {} points {} room {} ticks since the last point {}", r.seed, r.points, r.room, r.since_score);
        }
    }
    for (lo, hi) in [(0i64, 40i64), (40, 100000)] {
        let played: i64 = res.iter().map(|r| (r.points - lo).clamp(0, hi - lo)).sum();
        let died = res.iter().filter(|r| r.dead && r.points >= lo && r.points < hi).count() as i64;
        println!(
            "  score {}+: {} deaths in {} points = {} per 100",
            lo,
            died,
            played,
            fixed(100.0 * died as f64 / 1.max(played) as f64, 3)
        );
    }
    println!(
        "  looks {}: fine {}%, shorter {}%, none {}%",
        looks,
        fixed(100.0 * fine as f64 / looks as f64, 2),
        fixed(100.0 * shorter as f64 / looks as f64, 2),
        fixed(100.0 * none as f64 / looks as f64, 3)
    );
    let kinds = ["surprise (had a full line)", "after a fine look", "after a shorter look", "no line"];
    let dead: Vec<&Res> = res.iter().filter(|r| r.dead).collect();
    let mut by_look = groups(&dead, |r| r.look);
    by_look.sort_by_key(|g| g.0);
    println!(
        "  deaths by last look: {}",
        by_look.iter().map(|g| format!("{} {}", kinds[g.0 as usize], g.1.len())).collect::<Vec<_>>().join(", ")
    );
    println!(
        "  deaths by cause: {}",
        groups_by_count(&dead, |r| r.cause.clone())
            .iter()
            .map(|g| format!("{} {}", g.0, g.1.len()))
            .collect::<Vec<_>>()
            .join(", ")
    );
    println!(
        "  deaths by room: {}   (! = surprise)",
        groups_by_count(&dead, |r| format!("{}{}", r.room, if r.look == 0 { "!" } else { "" }))
            .iter()
            .take(16)
            .map(|g| format!("{} {}", g.0, g.1.len()))
            .collect::<Vec<_>>()
            .join(", ")
    );
}
