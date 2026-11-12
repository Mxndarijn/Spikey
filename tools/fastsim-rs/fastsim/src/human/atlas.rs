//! Port of Human/Atlas.cs. `fastsim human atlas`: what does the beast lack at each death?
//! Each run is replayed to `back` ticks before its death; from there a fresh
//! bot plays on with the copy's hidden values (BlindPlanner.Reveal) left as
//! they truly are, one kind at a time. Verdicts:
//!   luck     - the same bot with nothing revealed lives in most tries (a bad guess)
//!   doomed   - even with every hidden value true it dies (too late at `back`, or the search fails)
//!   <kind>   - revealing that one kind saves it in most tries (what it lacked)
//!   combo    - only all kinds together save it
use std::collections::HashSet;
use std::sync::atomic::Ordering;

use rayon::prelude::*;
use sim::prelude::*;

use crate::bots::blind_planner::{Reveal, KNOW_EXITS};
use crate::human::motor_player::{MotorPlayer, MotorTiers};
use crate::human::trace::Trace;
use crate::human::{fmt_f, group_count};
use crate::speed::Opts;

pub struct Atlas;

impl Atlas {
    const TRIES: i32 = 3;

    pub fn run(o: &Opts) -> i32 {
        let opt = |k: &str, d: &str| o.get(k).cloned().unwrap_or_else(|| d.to_string());
        let seeds: i64 = opt("seeds", "64").parse().expect("seeds");
        let first: i64 = opt("first", "0").parse().expect("first");
        let cap: i64 = opt("cap", "30000").parse().expect("cap");
        let back: i64 = opt("back", "240").parse().expect("back");
        let after: i64 = opt("after", "300").parse().expect("after");
        let tier = opt("tier", "beast");
        let motor = MotorTiers::of(&tier);
        let runs: Vec<Trace> = (0..seeds)
            .into_par_iter()
            .map(|i| {
                let seed = first + 1 + i;
                let mut mp = MotorPlayer::new(motor, seed, None);
                Trace::play(&mut GameSim::new(seed), |s: &GameSim| mp.decide(s), cap, false)
            })
            .collect();
        let dead: Vec<&Trace> = runs.iter().filter(|r| r.dead).collect();
        let pts: i64 = runs.iter().map(|r| r.points).sum();
        println!(
            "{tier}: {seeds} runs, {} deaths, {pts} points, {} deaths/100 pt (know_exits {})",
            dead.len(),
            fmt_f(100.0 * dead.len() as f64 / 1i64.max(pts) as f64, 3),
            if KNOW_EXITS.load(Ordering::Relaxed) { "True" } else { "False" }
        );
        let res: Vec<(String, String)> = dead
            .par_iter()
            .map(|r| {
                let death = r.ticks; // the tick it died on (runs start at tick 0)
                let from = 1i64.max(death - back);
                let taps: HashSet<i64> = r.taps.iter().copied().collect();
                let tries = |reveal: i32| -> i32 {
                    let mut ok = 0;
                    for k in 1..=Atlas::TRIES as i64 {
                        let mut sim = GameSim::new(r.seed);
                        while sim.state.tick < from && !sim.is_over() {
                            let tap = taps.contains(&sim.state.tick);
                            sim.step(tap);
                        }
                        if sim.is_over() {
                            return 0;
                        }
                        let bot_seed = r.seed * 7919 + k * 104729;
                        let mut bp = MotorPlayer::make_planner(bot_seed, &motor);
                        bp.reveal = reveal;
                        let mut mp = MotorPlayer::new(motor, bot_seed, Some(bp));
                        while sim.state.tick < death + after && !sim.is_over() {
                            let tap = mp.decide(&sim);
                            sim.step(tap);
                        }
                        if !sim.is_over() {
                            ok += 1;
                        }
                    }
                    ok
                };
                let v: String;
                let base_ok = tries(0);
                if base_ok * 2 > Atlas::TRIES {
                    v = "luck".to_string();
                } else if tries(Reveal::ALL) * 2 <= Atlas::TRIES {
                    v = "doomed".to_string();
                } else {
                    let mut hit: Vec<&str> = Vec::new();
                    for &(name, bit) in Reveal::KINDS.iter() {
                        if tries(bit) * 2 > Atlas::TRIES {
                            hit.push(name);
                        }
                    }
                    v = if hit.is_empty() { "combo".to_string() } else { hit.join("+") };
                }
                let row = format!("  seed {} at {} pts, tick {death}: {} in {} -> {v}", r.seed, r.points, r.cause, r.room);
                (row, v)
            })
            .collect();
        for (row, _) in &res {
            println!("{row}");
        }
        let verdicts: Vec<String> =
            group_count(res.iter().map(|x| x.1.clone())).iter().map(|(k, n)| format!("{k} {n}")).collect();
        println!("verdicts: {}", verdicts.join(", "));
        let rooms: Vec<String> =
            group_count(dead.iter().map(|d| d.room.clone())).iter().take(12).map(|(k, n)| format!("{k} {n}")).collect();
        println!("rooms: {}", rooms.join(", "));
        0
    }
}
