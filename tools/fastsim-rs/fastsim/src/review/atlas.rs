//! Port of RL/Review.cs `atlas`: `rl review atlas`, every death of the BlindPlanner with a verdict.
//!   last-chance: ticks before the death at which a search that sees the true future could last
//!     still save the run (binary search, at most BACK ticks; "never" = not even BACK ticks
//!     before: no player could).
//!   rescue: of RESCUES fresh planners (other guesses) started LEAD ticks before that last
//!     chance, how many live past the death.
//!   verdict: unfair (never), mistake (half or more rescues live: the planner could have known),
//!     hidden (savable only with luck or knowledge the screen does not give).
use std::path::Path;
use std::time::Instant;

use rayon::prelude::*;
use sim::prelude::*;

use super::honest::{groups, groups_by_count, pad};
use super::{configure, crate_drop, dbl, pct, room_name, NL};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::speed::Opts;
use super::fixed;

pub const BACK: i64 = 900;
pub const AFTER: i64 = 240;
pub const LEAD: i64 = 45;
pub const RESCUES: i32 = 8;

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

#[derive(Default)]
#[allow(dead_code)]
struct Res {
    points: i64,
    ticks: i64,
    dead: bool,
    room: String,
    verdict: String,
    chance: i64,
    rescued: i32,
    cause: String,
}

/// One run's results (C# `res[i]`, `rows[i]`, its share of `alt_saved`).
struct Out {
    res: Res,
    /// The planner's search steps and the run's ticks (C# psteps / pticks).
    steps: i64,
    ticks: i64,
    row: Option<String>,
    alt_ok: Vec<i64>,
}

/// How many of RESCUES fresh planners (setup `o`) started at `from` live past the death.
fn rescues(seed: i64, start: &GameSim, from: i64, o: &Opts) -> i32 {
    let mut ok = 0;
    for r in 0..RESCUES as i64 {
        let mut c = start.clone_deep();
        let mut b2 = BlindPlanner::new(seed * 1000 + r + 7);
        configure(&mut b2, o);
        let mut t = 0;
        while t < from + AFTER && !c.is_over() {
            let tap = b2.decide(&c);
            c.step(tap);
            t += 1;
        }
        if !c.is_over() {
            ok += 1;
        }
    }
    ok
}

pub fn atlas(opts: &Opts, seeds: i32, cap: i64) -> i32 {
    let first = l(opts, "first", 0);
    let out_path = opts.get("out").cloned().unwrap_or_default();
    let clock = Instant::now();
    // --alt "name:key=value,key=value;name2:...": the rescue runs again with each other setup (same starts).
    let mut alts: Vec<(String, Opts)> = Vec::new();
    for part in opts.get("alt").map(|s| s.as_str()).unwrap_or("").split(';').filter(|s| !s.is_empty()) {
        let mut o = opts.clone();
        let nv: Vec<&str> = part.split(':').collect();
        for kv in nv[1].split(',').filter(|s| !s.is_empty()) {
            let p: Vec<&str> = kv.split('=').collect();
            o.insert(p[0].to_string(), p[1].to_string());
        }
        alts.push((nv[0].to_string(), o));
    }
    let setup = {
        let mut b = BlindPlanner::new(first + 1);
        configure(&mut b, opts)
    };
    let outs: Vec<Out> = (0..seeds as i64)
        .into_par_iter()
        .map(|i| {
            let seed = first + i + 1;
            let mut sim = GameSim::new(seed);
            let mut bot = BlindPlanner::new(seed);
            configure(&mut bot, opts);
            let mut taps: Vec<bool> = Vec::new();
            let mut look: Vec<u8> = Vec::new();
            let (mut bounce_tick, mut entry_tick, mut drops, mut drop_tick) = (0i64, 0i64, -1i64, 0i64);
            while !sim.is_over() && (taps.len() as i64) < cap {
                let tap = bot.decide(&sim);
                taps.push(tap);
                look.push((bot.last_look * 10 + 9.min(bot.last_agree)) as u8);
                let (vx, ri) = (sim.state.vx, sim.state.room_index);
                sim.step(tap);
                if sim.state.vx != vx {
                    bounce_tick = taps.len() as i64;
                }
                if sim.state.room_index != ri {
                    entry_tick = taps.len() as i64;
                }
                // The tick a crate's column was last marked (its warning began).
                let dn = crate_drop(&sim).map(|cd| cd.drops).unwrap_or(-1);
                if dn != drops {
                    drops = dn;
                    drop_tick = taps.len() as i64;
                }
            }
            if let Some(dir) = opts.get("taps") {
                std::fs::create_dir_all(dir).expect("--taps");
                let bytes: Vec<u8> = taps.iter().map(|&b| if b { 1 } else { 0 }).collect();
                std::fs::write(Path::new(dir).join(format!("{seed}.taps")), bytes).expect("taps file");
            }
            let (psteps, pticks) = (bot.steps, taps.len() as i64);
            let room = room_name(&sim);
            if !sim.is_over() {
                return Out {
                    steps: psteps,
                    ticks: pticks,
                    res: Res { points: sim.state.score, ticks: taps.len() as i64, room, ..Default::default() },
                    row: None,
                    alt_ok: vec![0; alts.len()],
                };
            }
            let died = taps.len() as i64;
            let cause = DeathCause::NAMES[sim.state.death_cause as usize].to_string();
            // The state `back` ticks before the death.
            let at = |back: i64| -> GameSim {
                let mut c = GameSim::new(seed);
                for t in 0..(died - back) {
                    c.step(taps[t as usize]);
                }
                c
            };
            let savable = |back: i64| SurvivalSearch::new().run_quick(&at(back), back + AFTER);
            let max_back = BACK.min(died - 1);
            let mut chance: i64 = -1;
            if savable(max_back) {
                // Savable at lo, not at hi (the death tick itself is not).
                let (mut hi, mut lo) = (0i64, max_back);
                while lo - hi > 1 {
                    let mid = (lo + hi) / 2;
                    if savable(mid) {
                        lo = mid;
                    } else {
                        hi = mid;
                    }
                }
                chance = lo;
            }
            let mut rescued = 0;
            let mut seen: u8 = 0;
            if chance >= 0 {
                let from = max_back.min(chance + LEAD);
                seen = look[(died - chance) as usize];
                rescued = rescues(seed, &at(from), from, opts);
            }
            let mut alt_ok: Vec<i64> = Vec::new();
            for (_, ao) in &alts {
                let mut ok = 0;
                if chance >= 0 {
                    let from = max_back.min(chance + LEAD);
                    ok = rescues(seed, &at(from), from, ao);
                }
                alt_ok.push(ok as i64);
            }
            // Crates: `shown` = ticks before the death the last crate's column was marked.
            // A last chance before that means the run was lost before the player could see why.
            let shown = if crate_drop(&sim).is_some() { died - drop_tick } else { -1 };
            let verdict = if chance < 0 {
                "unfair"
            } else if rescued * 2 >= RESCUES {
                "mistake"
            } else if shown >= 0 && chance > shown {
                "unseen"
            } else {
                "hidden"
            };
            let row = format!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}/{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
                seed,
                sim.state.score,
                died,
                room,
                cause,
                verdict,
                chance,
                rescued,
                RESCUES,
                seen / 10,
                seen % 10,
                sim.state.x / SimConfig::SUB,
                sim.state.y / SimConfig::SUB,
                died - bounce_tick,
                died - entry_tick,
                shown
            );
            Out {
                steps: psteps,
                ticks: pticks,
                res: Res {
                    points: sim.state.score,
                    ticks: died,
                    dead: true,
                    room,
                    verdict: verdict.to_string(),
                    chance,
                    rescued,
                    cause,
                },
                row: Some(row),
                alt_ok,
            }
        })
        .collect();
    let mut alt_saved = vec![0i64; alts.len()];
    for o in &outs {
        for (a, ok) in o.alt_ok.iter().enumerate() {
            alt_saved[a] += ok;
        }
    }
    let res: Vec<&Res> = outs.iter().map(|o| &o.res).collect();
    let pts: i64 = res.iter().map(|r| r.points).sum();
    let deaths = res.iter().filter(|r| r.dead).count() as i64;
    let points: Vec<i64> = res.iter().map(|r| r.points).collect();
    let mut sb = String::new();
    let mut line = |s: String| {
        sb.push_str(&s);
        sb.push_str(NL);
    };
    line(format!(
        "death atlas, blind planner [{}], seeds {}..{}, cap {}, gameplay {}",
        setup,
        first + 1,
        first + seeds as i64,
        cap,
        SimConfig::GAMEPLAY_VERSION
    ));
    line(format!(
        "{} deaths in {} points = {} per 100; {} of {} alive at the cap; median {}; {} search steps per tick; {} s",
        deaths,
        pts,
        fixed(100.0 * deaths as f64 / 1.max(pts) as f64, 3),
        res.iter().filter(|r| !r.dead).count(),
        seeds,
        dbl(pct(&points, 0.5)),
        outs.iter().map(|o| o.steps).sum::<i64>() / 1.max(outs.iter().map(|o| o.ticks).sum::<i64>()),
        fixed(clock.elapsed().as_secs_f64(), 0)
    ));
    line(format!(
        "scores: {}",
        res.iter().map(|r| format!("{}{}", r.points, if r.dead { "" } else { "+" })).collect::<Vec<_>>().join(" ")
    ));
    if !alts.is_empty() {
        line(format!(
            "rescues (of {} per death): same setup {}, {}",
            RESCUES,
            res.iter().map(|r| r.rescued as i64).sum::<i64>(),
            alts.iter().enumerate().map(|(k, a)| format!("{} {}", a.0, alt_saved[k])).collect::<Vec<_>>().join(", ")
        ));
    }
    let dead: Vec<&Res> = res.iter().copied().filter(|r| r.dead).collect();
    line(format!(
        "verdicts: {}",
        groups_by_count(&dead, |r| r.verdict.clone())
            .iter()
            .map(|g| format!("{} {}", g.0, g.1.len()))
            .collect::<Vec<_>>()
            .join(", ")
    ));
    line("by room (deaths: mistake / hidden / unfair / unseen; median last chance in ticks before the death):".to_string());
    for (key, g) in groups_by_count(&dead, |r| r.room.clone()) {
        let ch: Vec<i64> = g.iter().filter(|r| r.chance >= 0).map(|r| r.chance).collect();
        let n = |v: &str| g.iter().filter(|r| r.verdict == v).count();
        line(format!(
            "  {} {}: {} / {} / {} / {}   last chance {}   causes {}",
            pad(&key, -26),
            pad(g.len(), 3),
            n("mistake"),
            n("hidden"),
            n("unfair"),
            n("unseen"),
            if !ch.is_empty() { fixed(pct(&ch, 0.5), 0) } else { "-".to_string() },
            groups(&g, |r| r.cause.clone()).iter().map(|c| format!("{} {}", c.0, c.1.len())).collect::<Vec<_>>().join(" ")
        ));
    }
    line("seed\tscore\ttick\troom\tcause\tverdict\tlast_chance\trescued\tlook\tagree\tx\ty\tsince_bounce\tsince_entry\tcrate_shown".to_string());
    for o in &outs {
        if let Some(r) = &o.row {
            line(r.clone());
        }
    }
    let text = sb;
    if !out_path.is_empty() {
        std::fs::write(&out_path, &text).expect("--out");
        let head: Vec<&str> = text.split('\n').take_while(|l| !l.starts_with("seed\t")).collect();
        print!("{}\n", head.join("\n"));
    } else {
        print!("{}", text);
    }
    0
}
