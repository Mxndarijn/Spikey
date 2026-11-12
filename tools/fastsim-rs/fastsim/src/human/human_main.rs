//! Port of Human/HumanMain.cs: `fastsim human <mode>` (docs/HUMAN_BOT.md):
//!   measure  --skill s | --tier name   play seeds, print scores + looks-human
//!   fit                                 bisect the skill knob for each tier's target median
//!   baseline --bot gap|search           the looks-human score of other bots
//!   deaths, atlas, motortrace
//! Common: --seeds n, --first n, --cap ticks, --bot motor|blind (threads: the global --jobs).
//! Not ported: --bot human (HumanBot.cs) and reflex (Reflex.cs), `reflextrace`,
//! `train-reflex`, `runfile` (RunFile), `baseline --bot rl`, and the HumanBot knobs.
use std::collections::{HashSet, VecDeque};
use std::fs::File;
use std::io::Write;
use std::sync::atomic::Ordering;
use std::time::Instant;

use rayon::prelude::*;
use sim::prelude::*;

use crate::bots::blind_planner::{BlindPlanner, BOSS_BLIND, KNOW_EXITS};
use crate::bots::{SimBots, SurvivalSearch};
use crate::human::atlas::Atlas;
use crate::human::motor_player::{Motor, MotorPlayer, MotorTiers, MASK_HAZARDS, MASK_SPIKES};
use crate::human::trace::{Humanness, Trace};
use crate::human::{fmt_f, group_count};
use crate::speed::{Opts, RUN_CAP};
use crate::yardstick::bots::Decide;

pub const TIERS: [&str; 5] = ["beginner", "normal", "good", "expert", "beast"];
pub const TARGETS: [f64; 5] = [30.0, 60.0, 120.0, 250.0, 500.0];
pub const FIT_SEED: i64 = 700_000;

/// The fitted skill knob of each tier (from `fastsim human fit`). C# HumanTiers.SKILL.
pub struct HumanTiers;
impl HumanTiers {
    pub const SKILL: [(&'static str, f64); 5] =
        [("beginner", 0.0), ("normal", 0.25), ("good", 0.5), ("expert", 0.75), ("beast", 1.0)];
}

fn opt(o: &Opts, k: &str, d: &str) -> String {
    o.get(k).cloned().unwrap_or_else(|| d.to_string())
}

fn num<T: std::str::FromStr>(o: &Opts, k: &str, d: &str) -> T {
    match opt(o, k, d).parse() {
        Ok(v) => v,
        Err(_) => panic!("--{k}: not a number"),
    }
}

/// The bots `decider` knows here.
fn ported(bot: &str) -> bool {
    bot == "blind" || bot == "motor"
}

pub fn run(pos: &[String], o: &Opts) -> i32 {
    // HumanBot.MIDPULL / FORESIGHT / BEAM / SPEEDS / WIDTH / ESCALATE / GAPMID / BMARGIN: HumanBot is not ported.
    KNOW_EXITS.store(opt(o, "knowexits", "0") == "1", Ordering::Relaxed);
    let mask = opt(o, "mask", "both");
    MASK_SPIKES.store(mask == "both" || mask == "spikes", Ordering::Relaxed);
    MASK_HAZARDS.store(mask == "both" || mask == "hazards", Ordering::Relaxed);
    let mode = if pos.len() > 1 { pos[1].as_str() } else { "measure" };
    let seeds: i64 = num(o, "seeds", "100");
    let first: i64 = num(o, "first", "0");
    let cap: i64 = num(o, "cap", &RUN_CAP.to_string());
    let bot = opt(o, "bot", "human");
    let sw = Instant::now();
    match mode {
        "measure" => {
            if !ported(&bot) {
                return not_ported(&format!("--bot {bot}"));
            }
            let s = skill_of(o, &opt(o, "tier", ""), num(o, "skill", "1"));
            let runs = play(o, &bot, s, first, seeds, cap);
            report(o, &format!("{bot} skill {}", fmt_f(s, 3)), &runs, &sw);
            if o.contains_key("out") {
                dump(&opt(o, "out", ""), &runs);
            }
            0
        }
        "fit" => {
            if !ported(&bot) {
                return not_ported(&format!("--bot {bot}"));
            }
            let fseeds: i64 = num(o, "seeds", "60");
            let mut floor = 0.0;
            for ti in 0..4 {
                let mut lo = floor;
                let mut hi = 1.0;
                let steps: i32 = num(o, "steps", "6");
                for _ in 0..steps {
                    let mid = (lo + hi) / 2.0;
                    let r = play(o, &bot, mid, FIT_SEED, fseeds, cap);
                    let pts: Vec<i64> = r.iter().map(|x| x.points).collect();
                    let m = Humanness::med(&pts);
                    println!(
                        "  {}: skill {} -> median {m}  ({}s)",
                        TIERS[ti],
                        fmt_f(mid, 3),
                        fmt_f(sw.elapsed().as_secs_f64(), 0)
                    );
                    if m < TARGETS[ti] {
                        lo = mid;
                    } else {
                        hi = mid;
                    }
                }
                println!("{} = {}", TIERS[ti], fmt_f((lo + hi) / 2.0, 3));
                floor = lo;
            }
            0
        }
        "baseline" => {
            if bot != "gap" && bot != "search" {
                return not_ported(&format!("baseline --bot {bot}"));
            }
            let runs: Vec<Trace> = (0..seeds)
                .into_par_iter()
                .map(|i| {
                    let seed = first + 1 + i;
                    Trace::play(&mut GameSim::new(seed), baseline(&bot, seed), cap, true)
                })
                .collect();
            report(o, &format!("baseline {bot}"), &runs, &sw);
            0
        }
        "deaths" => {
            if !ported(&bot) {
                return not_ported(&format!("--bot {bot}"));
            }
            // For each death: from the tick after the last bounce (the new
            // spikes are up and on screen), could a full SurvivalSearch live
            // 150 ticks? If not, the height at the bounce already doomed it.
            let s = skill_of(o, &opt(o, "tier", ""), num(o, "skill", "1"));
            let runs = play(o, &bot, s, first, seeds, cap);
            let rows: Vec<Option<String>> = runs
                .par_iter()
                .map(|r| {
                    if !r.dead || r.bounces.is_empty() {
                        return None;
                    }
                    let from = r.bounces[r.bounces.len() - 1] + 1;
                    let mut sim = GameSim::new(r.seed);
                    let taps: HashSet<i64> = r.taps.iter().copied().collect();
                    sim.step(true);
                    while sim.state.tick < from && !sim.is_over() {
                        let tap = taps.contains(&sim.state.tick);
                        sim.step(tap);
                    }
                    if sim.is_over() {
                        return None;
                    }
                    let mut ss = SurvivalSearch::new();
                    let ok = ss.run(&sim, 150);
                    Some(format!(
                        "{} {} {} ({}t after bounce)",
                        if ok { "savable" } else { "DOOMED" },
                        r.cause,
                        r.room,
                        r.since_bounce
                    ))
                })
                .collect();
            let got: Vec<String> = rows.into_iter().flatten().collect();
            for x in &got {
                println!("  {x}");
            }
            println!(
                "deaths {}: savable after the bounce {}, doomed at the bounce {}",
                got.len(),
                got.iter().filter(|x| x.starts_with("savable")).count(),
                got.iter().filter(|x| x.starts_with("DOOMED")).count()
            );
            0
        }
        "atlas" => Atlas::run(o),
        "motortrace" => {
            let seed: i64 = num(o, "seed", "3");
            let mut m = Motor::at(num(o, "sigma", "0.5"));
            m.react_mu = num(o, "react", "13");
            let mut mp = MotorPlayer::new(m, seed, None);
            mp.log = Some(Vec::new());
            let mut sim = GameSim::new(seed);
            let tr = Trace::play(&mut sim, |s: &GameSim| mp.decide(s), cap, false);
            let lines = mp.log.take().unwrap_or_default();
            let last: i64 = num(o, "last", "100");
            let skip = 0i64.max(lines.len() as i64 - last) as usize;
            for l in lines.iter().skip(skip) {
                println!("{l}");
            }
            println!("{} points, {} in {}", tr.points, tr.cause, tr.room);
            0
        }
        "reflextrace" | "train-reflex" | "runfile" => not_ported(&format!("human {mode}")),
        _ => {
            eprintln!("unknown human mode '{mode}'");
            2
        }
    }
}

fn not_ported(what: &str) -> i32 {
    eprintln!("{what}: not ported to fastsim-rs (use the C# fastsim)");
    2
}

fn skill_of(o: &Opts, tier: &str, s: f64) -> f64 {
    if tier.is_empty() {
        return s;
    }
    let fit = opt(o, "fitted", "");
    if !fit.is_empty() {
        let parts: Vec<f64> = fit.split(',').map(|x| x.parse().expect("--fitted")).collect();
        if let Some(i) = TIERS.iter().position(|&x| x == tier) {
            if i < parts.len() {
                return parts[i];
            }
        }
    }
    HumanTiers::SKILL.iter().find(|x| x.0 == tier).map(|x| x.1).unwrap_or(1.0)
}

/// `--bp name=value`: C# sets any public field of BlindPlanner by reflection
/// (Convert.ChangeType: "true"/"false" become 1/0 in a number field).
fn set_field(bp: &mut BlindPlanner, name: &str, value: &str) {
    let b = match value {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    };
    let i = || -> i64 {
        match b {
            Some(x) => x as i64,
            None => value.parse().unwrap_or_else(|_| panic!("--bp {name}: not a number")),
        }
    };
    let f = || -> bool {
        match b {
            Some(x) => x,
            None => panic!("--bp {name}: not a bool"),
        }
    };
    match name {
        "horizon" => bp.horizon = i(),
        "past" => bp.past = i(),
        "replan" => bp.replan = i() as i32,
        "replan_danger" => bp.replan_danger = i() as i32,
        "copies" => bp.copies = i() as i32,
        "lines" => bp.lines = i() as i32,
        "wobble" => bp.wobble = i() as i32,
        "part" => bp.part = i() as i32,
        "mid_cost" => bp.mid_cost = i(),
        "tap_cost" => bp.tap_cost = i(),
        "margin" => bp.margin = i(),
        "margin_cost" => bp.margin_cost = i(),
        "spike_margin" => bp.spike_margin = f(),
        "min_gap" => bp.min_gap = i(),
        "last_press" => bp.last_press = i(),
        "worst_fangs" => bp.worst_fangs = i() as i32,
        "wall_look" => bp.wall_look = f(),
        "full_speeds" => bp.full_speeds = f(),
        "aim_anchor" => bp.aim_anchor = f(),
        "wall_looks" => bp.wall_looks = i(),
        "no_pingpong" => bp.no_pingpong = f(),
        "keep_plan" => bp.keep_plan = f(),
        "bounce_look" => bp.bounce_look = f(),
        "wide_key" => bp.wide_key = f(),
        "aim_exit" => bp.aim_exit = f(),
        "kept_plans" => bp.kept_plans = i(),
        "bucket_px" => bp.bucket_px = i(),
        "speed_buckets" => bp.speed_buckets = i(),
        "fine_px" => bp.fine_px = i(),
        "fine_speeds" => bp.fine_speeds = i(),
        "reveal" => bp.reveal = i() as i32,
        "last_look" => bp.last_look = i() as i32,
        "last_agree" => bp.last_agree = i() as i32,
        "looks" => bp.looks = i(),
        "fine_looks" => bp.fine_looks = i(),
        "short_looks" => bp.short_looks = i(),
        "no_looks" => bp.no_looks = i(),
        "split_looks" => bp.split_looks = i(),
        "know_exits" => KNOW_EXITS.store(f(), Ordering::Relaxed),
        "boss_blind" => BOSS_BLIND.store(f(), Ordering::Relaxed),
        _ => panic!("no BlindPlanner field '{name}'"),
    }
}

/// C# HumanMain.decider for the ported bots (`blind`, `motor`); `s` is the HumanBot/Reflex skill (unused here).
pub fn decider(o: &Opts, bot: &str, _s: f64, seed: i64) -> Decide {
    if bot == "blind" {
        let mut bp = BlindPlanner::new(seed);
        return Box::new(move |sim: &GameSim| bp.decide(sim));
    }
    if bot == "motor" {
        let mut m =
            if o.contains_key("sigma") { Motor::at(num(o, "sigma", "0")) } else { MotorTiers::of(&opt(o, "tier", "beast")) };
        if o.contains_key("react") {
            m.react_mu = num(o, "react", "13");
        }
        if o.contains_key("gap") {
            m.min_gap = num(o, "gap", "8");
        }
        if o.contains_key("fine") {
            m.fine = opt(o, "fine", "1") == "1";
        }
        let mut bp = MotorPlayer::make_planner(seed, &m);
        if o.contains_key("lines") {
            bp.lines = num(o, "lines", "1");
        }
        if o.contains_key("wobble") {
            bp.wobble = num(o, "wobble", "0");
        }
        if o.contains_key("copies") {
            bp.copies = num(o, "copies", "1");
        }
        // --bp horizon=260,past=150,bucket_px=6: any public field of BlindPlanner.
        for kv in opt(o, "bp", "").split(',').filter(|x| !x.is_empty()) {
            let p: Vec<&str> = kv.split('=').collect();
            set_field(&mut bp, p[0], p.get(1).copied().unwrap_or(""));
        }
        if o.contains_key("margin") {
            bp.margin = num(o, "margin", "10");
        }
        if o.contains_key("smargin") {
            bp.spike_margin = opt(o, "smargin", "1") == "1";
        }
        if o.contains_key("mcost") {
            bp.margin_cost = num(o, "mcost", "40");
        }
        if o.contains_key("midcost") {
            bp.mid_cost = num(o, "midcost", "1");
        }
        let mut mp = MotorPlayer::new(m, seed, Some(bp));
        return Box::new(move |sim: &GameSim| mp.decide(sim));
    }
    panic!("--bot {bot}: not ported to fastsim-rs (HumanBot.cs / Reflex.cs)");
}

/// Seeds first+1 .. first+n, results in seed order.
pub fn play(o: &Opts, bot: &str, s: f64, first: i64, n: i64, cap: i64) -> Vec<Trace> {
    (0..n)
        .into_par_iter()
        .map(|i| {
            let seed = first + 1 + i;
            Trace::play(&mut GameSim::new(seed), decider(o, bot, s, seed), cap, true)
        })
        .collect()
}

fn baseline(bot: &str, seed: i64) -> Decide {
    match bot {
        "gap" => {
            let mut rng = SimRng::new(seed);
            Box::new(move |sim: &GameSim| SimBots::gap_seeker(sim, &mut rng))
        }
        "search" => {
            // SurvivalSearch replanned every 30 ticks over 150 ticks of look-ahead.
            let mut plan: VecDeque<bool> = VecDeque::new();
            Box::new(move |sim: &GameSim| {
                if !sim.state.started {
                    return true;
                }
                if plan.is_empty() {
                    let mut ss = SurvivalSearch::new();
                    if ss.run_quick(sim, 150) {
                        for &b in ss.best_inputs.iter().take(30) {
                            plan.push_back(b != 0);
                        }
                    } else {
                        plan.push_back(false);
                    }
                }
                plan.pop_front().expect("empty plan")
            })
        }
        _ => panic!("unknown baseline bot '{bot}'"),
    }
}

pub fn report(o: &Opts, what: &str, runs: &[Trace], sw: &Instant) {
    let pts: Vec<i64> = runs.iter().map(|r| r.points).collect();
    let ticks: i64 = runs.iter().map(|r| r.ticks).sum();
    let sum: i64 = pts.iter().sum();
    let dead = runs.iter().filter(|r| r.dead).count();
    let secs = sw.elapsed().as_secs_f64();
    println!(
        "{what}: {} runs, median {}, p25 {}, p90 {}, mean {}, alive at cap {}, deaths/100pt {}, rate median {}, {}s ({} ticks/s)",
        runs.len(),
        Humanness::med(&pts),
        Humanness::pct(&pts, 0.25),
        Humanness::pct(&pts, 0.9),
        fmt_f(sum as f64 / pts.len() as f64, 1),
        runs.len() - dead,
        fmt_f(100.0 * dead as f64 / 1i64.max(sum) as f64, 3),
        fmt_f(rate_median(runs), 0),
        fmt_f(secs, 0),
        fmt_f(ticks as f64 / 0.001f64.max(secs), 0)
    );
    println!("  {}", Humanness::of(runs));
    let deaths: Vec<String> = group_count(runs.iter().filter(|r| r.dead).map(|r| r.room.clone()))
        .iter()
        .take(8)
        .map(|(k, n)| format!("{k} {n}"))
        .collect();
    println!("  deaths: {}", deaths.join(", "));
    let causes: Vec<String> = group_count(runs.iter().filter(|r| r.dead).map(|r| r.cause.clone()))
        .iter()
        .map(|(k, n)| format!("{k} {n}"))
        .collect();
    println!("  causes: {}", causes.join(", "));
    if o.contains_key("debug") {
        for r in runs.iter().filter(|r| r.dead && r.cause.starts_with("SPIKE")) {
            println!(
                "    seed {} {}: bounce y {}, death y {}, gap {}, {}t after bounce",
                r.seed, r.room, r.bounce_y, r.death_y, r.gap_y, r.since_bounce
            );
        }
    }
}

/// The median a run would reach at this death rate per point (the yardstick's measure).
pub fn rate_median(runs: &[Trace]) -> f64 {
    let pts: i64 = runs.iter().map(|r| r.points).sum();
    let d = runs.iter().filter(|r| r.dead).count() as f64 / 1i64.max(pts) as f64;
    if d <= 0.0 {
        f64::INFINITY
    } else {
        0.5f64.ln() / (1.0 - d).ln()
    }
}

fn dump(path: &str, runs: &[Trace]) {
    let mut w = File::create(path).unwrap_or_else(|e| panic!("{path}: {e}"));
    let nl = if cfg!(windows) { "\r\n" } else { "\n" }; // StreamWriter.WriteLine
    let mut s = format!("seed,points,ticks,dead,room,cause,taps{nl}");
    for r in runs {
        s += &format!(
            "{},{},{},{},{},{},{}{nl}",
            r.seed,
            r.points,
            r.ticks,
            if r.dead { "True" } else { "False" },
            r.room,
            r.cause,
            r.taps.len()
        );
    }
    w.write_all(s.as_bytes()).unwrap_or_else(|e| panic!("{path}: {e}"));
}
