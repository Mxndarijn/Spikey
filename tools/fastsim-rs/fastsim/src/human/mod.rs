//! Human/ (docs/HUMAN_BOT.md): the human tiers. Ported: MotorPlayer.cs (Motor,
//! MotorPlayer, MotorTiers and Register), Trace.cs (Trace, Humanness), Atlas.cs
//! and the parts of HumanMain.cs the motor and blind bots need. Not ported:
//! HumanBot.cs and Reflex.cs (the `human` and `reflex` bots), RunFile (`runfile`),
//! the RL policy (`baseline --bot rl`).
pub mod atlas;
pub mod human_main;
pub mod motor_player;
pub mod trace;

use std::sync::atomic::Ordering;
use std::sync::Arc;

use sim::prelude::*;

use crate::bots::blind_planner::KNOW_EXITS;
use crate::yardstick::bots::{BotSpec, Copies, Decide, Make};
use motor_player::{MotorPlayer, MotorTiers};

pub use human_main::run;
pub use motor_player::sims_swapped;

/// The `human:<tier>` and `human-ke:<tier>` bots (MotorPlayer.cs Register).
pub fn yardstick_bots() -> Vec<BotSpec> {
    let mut v = Vec::new();
    for &(name, _) in MotorTiers::TIER.iter() {
        let tier: &'static str = name;
        // C# runs Register as a module initializer, before any option sets know_exits.
        let m = MotorTiers::of_table(tier, false);
        let make: Make = Arc::new(move |seed: i64| -> Decide {
            let mut mp = MotorPlayer::new(MotorTiers::of(tier), seed, None);
            Box::new(move |sim: &GameSim| mp.decide(sim))
        });
        v.push(BotSpec {
            name: format!("human:{tier}"),
            about: format!(
                "MotorPlayer: BlindPlanner (class defaults{}; 8 lines tried with tap shifts when sd > 0) + motor model: \
                 tap sd {} ticks, reaction {} to new spikes/hazards, 8 ticks between presses",
                if m.fine { ", 4 px x 12 speed buckets" } else { "" },
                m.sigma,
                if m.react_mu < 0.0 { "none".to_string() } else { format!("~{} ticks", fmt_f(m.react_mu + m.react_tau, 0)) }
            ),
            copies: Copies::SCRAMBLED,
            make,
        });
        // The same tier on the known-exits table, with the planner told the planned exit
        // mouths (only honest if the game shows them from room start). Process-wide switch:
        // run these bots in their own yardstick call.
        let make_ke: Make = Arc::new(move |seed: i64| -> Decide {
            KNOW_EXITS.store(true, Ordering::Relaxed);
            let mut mp = MotorPlayer::new(MotorTiers::of(tier), seed, None);
            Box::new(move |sim: &GameSim| mp.decide(sim))
        });
        v.push(BotSpec {
            name: format!("human-ke:{tier}"),
            about: format!("human:{tier} on the known-exits table, BlindPlanner.know_exits = true"),
            copies: Copies::SCRAMBLED,
            make: make_ke,
        });
    }
    v
}

/// C# `x.ToString("F<d>")`: fixed point, midpoints rounded away from zero (Rust's `{:.d}`
/// rounds them to even), infinity as the invariant culture's "∞".
pub fn fmt_f(x: f64, d: usize) -> String {
    if x.is_nan() {
        return "NaN".to_string();
    }
    if x.is_infinite() {
        return if x > 0.0 { "∞".to_string() } else { "-∞".to_string() };
    }
    // Enough digits to see an exact midpoint (a tie is a short binary fraction).
    let long = format!("{:.*}", d + 40, x);
    let dot = long.find('.').unwrap_or(long.len());
    let tail = &long[dot + d + 1..];
    if tail.starts_with('5') && tail[1..].bytes().all(|b| b == b'0') {
        let kept = &long[..if d > 0 { dot + d + 1 } else { dot }];
        let mut b: Vec<u8> = kept.bytes().collect();
        let mut i = b.len();
        loop {
            if i == 0 || b[i - 1] == b'-' {
                b.insert(i, b'1');
                break;
            }
            i -= 1;
            match b[i] {
                b'.' => continue,
                b'9' => b[i] = b'0',
                c => {
                    b[i] = c + 1;
                    break;
                }
            }
        }
        return String::from_utf8(b).unwrap_or_default();
    }
    format!("{:.*}", d, x)
}

/// C# `x.ToString("P<d>")` (en-US style: no space before %).
pub fn fmt_p(x: f64, d: usize) -> String {
    format!("{}%", fmt_f(x * 100.0, d))
}

/// C# `GroupBy(key).OrderByDescending(g => g.Count())`: keys in first-seen order, then a stable sort by count.
pub fn group_count(keys: impl Iterator<Item = String>) -> Vec<(String, usize)> {
    let mut g: Vec<(String, usize)> = Vec::new();
    for k in keys {
        match g.iter_mut().find(|x| x.0 == k) {
            Some(x) => x.1 += 1,
            None => g.push((k, 1)),
        }
    }
    g.sort_by(|a, b| b.1.cmp(&a.1));
    g
}
