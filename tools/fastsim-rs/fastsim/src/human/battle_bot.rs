//! The Battle bots (docs/DUEL_MODE.md, section 6): one human-model run of a
//! battle round's seed, for the server's battle-bot worker.
//!
//!   fastsim-rs battlebot --seed S [--season X] [--level 1..8] [--bot-seed B] [--cap T]
//!
//! prints {"taps": [...], "score": n, "coins": n, "end_tick": n, "level": n} on
//! one line. The bot is the MotorPlayer (BlindPlanner with screen-only sight plus
//! the measured human motor model and the 8-tick thumb gap) at one of 8 levels
//! from beginner to beast: the five measured tiers and three between them where
//! the gaps are widest. `bot-seed` draws its tap noise, so a run is reproducible.
//! It never sees the rival's run. The level is hidden from players.

use serde_json::json;
use sim::prelude::*;
use sim::sim_config::SimConfig;

use super::motor_player::{Motor, MotorPlayer};
use crate::speed::Opts;

/// (sigma, reaction to new things, fine search) per level, 1 = beginner .. 8 =
/// beast. Levels 1, 3, 5, 7 and 8 are MotorTiers::TIER; 2, 4 and 6 sit between.
pub const LEVELS: [(f64, f64, bool); 8] = [
    (1.4, 13.0, false),
    (1.0, 13.0, false),
    (0.6, 13.0, false),
    (0.3, 10.0, false),
    (0.0, 8.0, false),
    (0.0, 5.0, false),
    (0.2, 2.0, true),
    (0.0, -100.0, true),
];

/// The motor model of a level (1..8, kept in range).
pub fn motor(level: i64) -> Motor {
    let (sigma, react, fine) = LEVELS[(level.clamp(1, 8) - 1) as usize];
    let mut m = Motor::at(sigma);
    m.react_mu = react;
    m.react_tau = if react < 0.0 { 0.0 } else { 4.0 };
    m.fine = fine;
    m
}

/// One run: (taps, score, coins, end tick).
pub fn play(seed: i64, season: i64, level: i64, bot_seed: i64, cap: i64) -> (Vec<i64>, i64, i64, i64) {
    let mut sim = GameSim::with(seed, season, -1, "");
    let mut bot = MotorPlayer::new(motor(level), bot_seed, None);
    let mut taps = Vec::new();
    while !sim.is_over() && sim.state.tick < cap {
        let tap = bot.decide(&sim);
        if tap {
            taps.push(sim.state.tick);
        }
        sim.step(tap);
    }
    (taps, sim.state.score, sim.state.coins, sim.state.tick)
}

fn num(o: &Opts, k: &str, d: i64) -> i64 {
    o.get(k).and_then(|v| v.parse().ok()).unwrap_or(d)
}

pub fn run(o: &Opts) -> i32 {
    let Some(seed) = o.get("seed").and_then(|v| v.parse::<i64>().ok()) else {
        eprintln!("usage: fastsim-rs battlebot --seed S [--season X] [--level 1..8] [--bot-seed B] [--cap T]");
        return 2;
    };
    let level = num(o, "level", 3).clamp(1, 8);
    let (taps, score, coins, end_tick) = play(
        seed,
        num(o, "season", Seasons::NONE),
        level,
        num(o, "bot-seed", 1),
        num(o, "cap", SimConfig::MAX_TICKS),
    );
    println!("{}", json!({"taps": taps, "score": score, "coins": coins, "end_tick": end_tick, "level": level}));
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_bot_run_replays_to_the_same_result() {
        let (taps, score, coins, end) = play(2024, Seasons::NONE, 1, 7, 6000);
        let mut sim = GameSim::with(2024, Seasons::NONE, -1, "");
        let mut next = 0;
        while !sim.is_over() && sim.state.tick < 6000 {
            let tap = next < taps.len() && taps[next] == sim.state.tick;
            if tap {
                next += 1;
            }
            sim.step(tap);
        }
        assert_eq!((sim.state.score, sim.state.coins, sim.state.tick), (score, coins, end));
        assert_eq!(play(2024, Seasons::NONE, 1, 7, 6000).0, taps, "the bot seed decides the noise");
    }

    #[test]
    fn levels_climb_from_beginner_to_beast() {
        assert_eq!(LEVELS.len(), 8);
        assert!(motor(1).sigma > motor(3).sigma && motor(3).sigma > motor(5).sigma);
        assert!(motor(8).react_mu < 0.0 && motor(8).fine, "beast: no reaction lag, fine search");
        assert_eq!(motor(99).sigma, motor(8).sigma, "kept in range");
    }
}
