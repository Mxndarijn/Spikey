//! `speed`: port of RL/Review.cs `rl review speed` for the BlindPlanner (same
//! seeds, cap, options and taps fingerprint, so a Rust run can be compared with
//! the C# one), and `bench`: the copy / step part of Program.cs Bench.
use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::time::Instant;

use rayon::prelude::*;
use sim::arrival_memo;
use sim::prelude::*;

use crate::bots::blind_planner::{BlindPlanner, KNOW_EXITS};
use crate::bots::PlannerBot;

pub type Opts = HashMap<String, String>;

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

/// Review.configure.
pub fn configure(bot: &mut BlindPlanner, opts: &Opts) -> String {
    KNOW_EXITS.store(l(opts, "knowexits", 0) != 0, Ordering::Relaxed);
    bot.horizon = l(opts, "h", bot.horizon);
    bot.past = l(opts, "past", bot.past);
    bot.replan = l(opts, "k", bot.replan as i64) as i32;
    bot.replan_danger = l(opts, "kd", bot.replan_danger as i64) as i32;
    bot.copies = l(opts, "n", bot.copies as i64) as i32;
    bot.lines = l(opts, "lines", bot.lines as i64) as i32;
    bot.wobble = l(opts, "wobble", bot.wobble as i64) as i32;
    bot.part = l(opts, "part", bot.part as i64) as i32;
    bot.after = l(opts, "after", bot.after);
    bot.band = l(opts, "band", bot.band);
    bot.coarse_px = l(opts, "coarse", bot.coarse_px);
    bot.mid_cost = l(opts, "mid", bot.mid_cost);
    bot.tap_cost = l(opts, "tap", bot.tap_cost);
    bot.margin = l(opts, "margin", bot.margin);
    bot.margin_cost = l(opts, "margincost", bot.margin_cost);
    bot.worst_fangs = l(opts, "fangs", bot.worst_fangs as i64) as i32;
    bot.no_pingpong = l(opts, "pingpong", 1) != 0;
    bot.keep_plan = l(opts, "keep", 1) != 0;
    bot.bounce_look = l(opts, "bouncelook", 1) != 0;
    bot.wide_key = l(opts, "widekey", 0) != 0;
    bot.aim_exit = l(opts, "aimexit", 1) != 0;
    bot.wall_look = l(opts, "walllook", 1) != 0;
    bot.full_speeds = l(opts, "fullspeeds", 0) != 0;
    bot.aim_anchor = l(opts, "aimanchor", 0) != 0;
    bot.fine_speeds = l(opts, "finespeeds", bot.fine_speeds);
    bot.spike_margin = l(opts, "spikemargin", bot.spike_margin as i64) != 0;
    bot.bucket_px = l(opts, "bpx", bot.bucket_px);
    format!(
        "h {} past {} k {}/{} n {} lines {} margin {} bpx {}",
        bot.horizon, bot.past, bot.replan, bot.replan_danger, bot.copies, bot.lines, bot.margin, bot.bucket_px
    )
}

pub const RUN_CAP: i64 = 60 * 60 * SimConfig::TICKS_PER_SECOND;

pub fn speed(opts: &Opts) -> i32 {
    let seeds = l(opts, "seeds", 32);
    let cap = l(opts, "cap", RUN_CAP);
    let first = l(opts, "first", 0);
    let threads = rayon::current_num_threads();
    arrival_memo::ON.store(opts.get("memo").map(|s| s.as_str()).unwrap_or("1") != "0", Ordering::Relaxed);
    arrival_memo::VERIFY.store(opts.get("memo").map(|s| s.as_str()) == Some("2"), Ordering::Relaxed);
    let setup = {
        let mut b = BlindPlanner::new(1);
        configure(&mut b, opts)
    };
    arrival_memo::HITS.store(0, Ordering::Relaxed);
    arrival_memo::MISSES.store(0, Ordering::Relaxed);
    let clock = Instant::now();
    let res: Vec<(i64, i64, bool, u64, i64)> = (0..seeds)
        .into_par_iter()
        .map(|i| {
            let seed = first + i + 1;
            let mut sim = GameSim::new(seed);
            let mut ticks: i64 = 0;
            let mut fp: u64 = 14695981039346656037;
            let mut bot = BlindPlanner::new(seed);
            configure(&mut bot, opts);
            while !sim.is_over() && ticks < cap {
                let tap = bot.decide(&sim);
                fp = (fp ^ (tap as u64) ^ ((ticks as u64) << 1)).wrapping_mul(1099511628211);
                sim.step(tap);
                ticks += 1;
            }
            (sim.state.score, ticks, sim.is_over(), fp, bot.looks)
        })
        .collect();
    let sec = clock.elapsed().as_secs_f64();
    let all: i64 = res.iter().map(|r| r.1).sum();
    let pts: i64 = res.iter().map(|r| r.0).sum();
    let deaths = res.iter().filter(|r| r.2).count();
    let looks: i64 = res.iter().map(|r| r.4).sum();
    println!("speed blind [{setup}] seeds {}..{} cap {cap} threads {threads}", first + 1, first + seeds);
    println!(
        "  {all} ticks in {sec:.1} s = {:.0} ticks/s, {:.0} per thread; {deaths} deaths in {pts} points; looks {looks} ({:.3} ms each)",
        all as f64 / sec,
        all as f64 / sec / threads as f64,
        1000.0 * sec * threads as f64 / looks.max(1) as f64
    );
    let mut all_fp: u64 = 0;
    for r in &res {
        all_fp = (all_fp ^ r.3).wrapping_mul(1099511628211);
    }
    let on = arrival_memo::ON.load(Ordering::Relaxed);
    let verify = arrival_memo::VERIFY.load(Ordering::Relaxed);
    println!(
        "  taps fingerprint {all_fp:016x} (same = same play); arrival memo {}: {} hits, {} misses{}",
        if on { "on" } else { "off" },
        arrival_memo::HITS.load(Ordering::Relaxed),
        arrival_memo::MISSES.load(Ordering::Relaxed),
        if verify { format!(", {} wrong", arrival_memo::WRONG.load(Ordering::Relaxed)) } else { String::new() }
    );
    if opts.contains_key("perseed") {
        for (i, r) in res.iter().enumerate() {
            println!("  seed {} score {} ticks {} dead {} fp {:016x}", first + i as i64 + 1, r.0, r.1, r.2, r.3);
        }
    }
    0
}

/// Program.cs Bench, the copy and step part: every room in practice.
pub fn bench() -> i32 {
    let mut rng = SimRng::new(7);
    let rooms = RoomCatalog::all();
    let (mut copies, mut steps) = (0i64, 0i64);
    let (mut copy_t, mut step_t) = (0f64, 0f64);
    let mut sink = 0i64;
    for index in 0..rooms.len() {
        let mut sim = GameSim::with(1077, rooms[index].season, index as i64, "");
        for _ in 0..40 {
            let tap = PlannerBot::aim(&sim, &mut rng);
            sim.step(tap);
        }
        if sim.is_over() {
            sim = GameSim::with(1077, rooms[index].season, index as i64, "");
        }
        let t0 = Instant::now();
        for _ in 0..2000 {
            let c = sim.clone_deep();
            sink += c.state.tick;
        }
        copy_t += t0.elapsed().as_secs_f64();
        copies += 2000;
        let mut c = sim.clone_deep();
        let t0 = Instant::now();
        for _ in 0..20000 {
            if c.is_over() {
                c = sim.clone_deep();
            }
            let tap = PlannerBot::aim(&c, &mut rng);
            c.step(tap);
        }
        step_t += t0.elapsed().as_secs_f64();
        steps += 20000;
        sink += c.checksum();
    }
    println!("copy      {:8.2} us", copy_t * 1e6 / copies as f64);
    println!("step      {:8.2} us", step_t * 1e6 / steps as f64);
    println!("(sink {})", sink & 1);
    0
}
