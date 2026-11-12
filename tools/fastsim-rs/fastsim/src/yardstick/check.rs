//! Port of Yardstick/YardstickCheck.cs: the yardstick (docs/YARDSTICK.md) measures what was
//! played: a replay of a bot's taps scores what the bot scored, tiers map as documented and
//! the human-vs-bot classifier can tell different players apart but not two halves of one.
//! C# runs it as the `yardstick` step of `fastsim check`; here `fastsim-rs yardstick check`.
use serde_json::{json, Value};
use sim::prelude::*;

use super::bots::Bots;
use super::compare::Compare;
use super::leak::Leak;
use super::node_str;
use super::runs::{Run, RunInput};
use super::stats::Stats;
use super::timing::Timing;

/// Checks.Yardstick.run: the failures (empty = pass) and `{"runs": n}`.
pub fn run() -> (Vec<String>, Value) {
    let mut fails: Vec<String> = Vec::new();
    let cases: [(f64, &str); 7] = [
        (20.0, "below beginner"),
        (30.0, "beginner"),
        (50.0, "normal"),
        (120.0, "good"),
        (300.0, "expert"),
        (354.0, "beast"),
        (900.0, "beast"),
    ];
    for (m, want) in cases {
        if Stats::tier_of(m) != want {
            fails.push(format!("tier_of({}) is {}, not {}", m, Stats::tier_of(m), want));
        }
    }
    let gap = Bots::find("gap").expect("the gap bot");
    let mut runs: Vec<Run> = Vec::new();
    let mut s: i64 = 1;
    while s <= 40 && fails.is_empty() {
        let mut decide = (gap.make)(s);
        let mut sim = GameSim::new(s);
        let mut taps: Vec<i64> = Vec::new();
        while !sim.is_over() && sim.state.tick < 20_000 {
            let t = decide(&sim);
            if t {
                taps.push(sim.state.tick);
            }
            sim.step(t);
        }
        let r = Run::analyze(&RunInput::new(s, Seasons::NONE, taps, ""), 20_000);
        if r.points != sim.state.score || r.ticks != sim.state.tick {
            fails.push(format!(
                "seed {}: the replay scored {} in {} ticks, the bot {} in {}",
                s, r.points, r.ticks, sim.state.score, sim.state.tick
            ));
        }
        runs.push(r);
        s += 1;
    }
    if fails.is_empty() {
        let even: Vec<Run> = runs.iter().step_by(2).cloned().collect();
        let odd: Vec<Run> = runs.iter().skip(1).step_by(2).cloned().collect();
        let same = Compare::classify(&even, &odd);
        if same["balanced_accuracy"].as_f64().unwrap_or(f64::NAN) > 0.75 {
            fails.push(format!(
                "the classifier tells two halves of one bot's runs apart ({})",
                node_str(&same["balanced_accuracy"])
            ));
        }
        // C# also checks against "rl:beast" when the RL policy is there; the RL bots are not ported.
        if let Some(rl) = Bots::find("rl:beast") {
            let other: Vec<Run> = (1..=20).map(|s| Run::analyze(&Run::play(&rl, s, 20_000), 20_000)).collect();
            let apart = Compare::classify(&runs, &other);
            if apart["balanced_accuracy"].as_f64().unwrap_or(f64::NAN) < 0.9 {
                fails.push(format!(
                    "the classifier cannot tell the gap seeker from the RL bot ({})",
                    node_str(&apart["balanced_accuracy"])
                ));
            }
        }
        // The leak check: PlannerBot rolls out real copies, so it must be caught; the gap seeker reads only the screen.
        let lp = Leak::check(&Bots::find("planner").expect("the planner bot"), 2, 1);
        if lp["leaks"].as_str() != Some("yes") {
            fails.push(format!("the leak check misses PlannerBot's real copies ({})", serde_json::to_string(&lp).unwrap()));
        }
        let lg = Leak::check(&gap, 4, 1);
        if lg["leaks"].as_str() != Some("no") {
            fails.push(format!("the leak check flags the gap seeker ({})", serde_json::to_string(&lg).unwrap()));
        }
        let t = Timing::judge(&runs[0].input, &runs[0], 10);
        if t.taps_judged == 0 {
            fails.push("no tap of a gap seeker run could be timed".to_string());
        }
    }
    (fails, json!({ "runs": runs.len() }))
}

/// Checks.Yardstick.summary.
pub fn summary(result: &Value) -> String {
    format!("yardstick: replays match {} bot runs, tiers and classifier behave", node_str(&result["runs"]))
}

/// `fastsim-rs yardstick check`: 0 when it passes.
pub fn main() -> i32 {
    let (fails, result) = run();
    if fails.is_empty() {
        println!("{}", summary(&result));
        0
    } else {
        for f in &fails {
            println!("FAIL yardstick: {}", f);
        }
        1
    }
}
