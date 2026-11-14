//! `fastsim-rs planrun`: BlindPlanner runs written as run files (RunFile), to render
//! a long bot run with tools/render_run.ps1 (docs/RENDERING.md).
//!
//!   fastsim-rs planrun --seeds 8 [--first 0] [--target 2000] [--cap 216000]
//!       --outdir <dir> [BlindPlanner knobs as `rl review fair`: --follow 48 --tapfree 1 --bpx 4 --speeds 12]
//!
//! Each seed plays until death or --cap ticks. Once the score reaches --target the
//! bot stops tapping, so the run ends on the next death (the run file needs an end).
//! Writes `seed_<n>.run.json` for every seed that reached the target, and
//! `seed_<n>.rooms.json`: every room entered, with its tick and score (for cutting
//! highlights). Prints one line per seed: score, ticks, rooms, bosses.
use rayon::prelude::*;
use serde_json::json;
use sim::prelude::*;

use crate::bots::run_file::RunFile;
use crate::bots::BlindPlanner;
use crate::review::{configure, room_name, RUN_CAP};
use crate::speed::Opts;

struct Out {
    seed: i64,
    score: i64,
    ticks: i64,
    reached: bool,
    rooms: Vec<serde_json::Value>,
    bosses: i64,
    kinds: usize,
}

pub fn run(opts: &Opts) -> i32 {
    let l = |key: &str, d: i64| -> i64 { opts.get(key).map(|v| v.parse().expect(key)).unwrap_or(d) };
    let (seeds, first, target, cap) = (l("seeds", 8), l("first", 0), l("target", 2000), l("cap", RUN_CAP));
    let dir = opts.get("outdir").cloned().unwrap_or_else(|| ".".to_string());
    std::fs::create_dir_all(&dir).expect("--outdir");
    let mut outs: Vec<Out> = (0..seeds)
        .into_par_iter()
        .map(|i| {
            let seed = first + i + 1;
            let mut sim = GameSim::new(seed);
            let mut bot = BlindPlanner::new(seed);
            let _ = configure(&mut bot, opts);
            let mut taps: Vec<i64> = Vec::new();
            let mut rooms = Vec::new();
            let (mut last_room, mut bosses) = (-1i64, 0i64);
            let mut kinds = std::collections::HashSet::new();
            while !sim.is_over() && sim.state.tick < cap {
                if sim.state.room_index != last_room {
                    last_room = sim.state.room_index;
                    let def = sim.room.def();
                    if def.boss {
                        bosses += 1;
                    }
                    kinds.insert(def.id);
                    rooms.push(json!({
                        "tick": sim.state.tick,
                        "score": sim.state.score,
                        "room": room_name(&sim),
                        "group": def.group,
                        "boss": def.boss,
                    }));
                }
                // The bot's decision runs every tick (its plan state), even after the target.
                let wants = bot.decide(&sim);
                let tap = wants && sim.state.score < target;
                if tap {
                    taps.push(sim.state.tick);
                }
                sim.step(tap);
            }
            let reached = sim.state.score >= target && sim.is_over();
            if reached {
                let path = format!("{dir}/seed_{seed}.run.json");
                RunFile::write(&path, &sim, &taps, &[], &format!("beast {seed}")).expect("write run file");
                let marks = json!({"seed": seed, "score": sim.state.score, "end_tick": sim.state.tick, "rooms": rooms});
                std::fs::write(format!("{dir}/seed_{seed}.rooms.json"), crate::yardstick::json_pretty(&marks) + "\n")
                    .expect("write rooms");
            }
            eprintln!("seed {seed}: score {} ticks {}", sim.state.score, sim.state.tick);
            Out { seed, score: sim.state.score, ticks: sim.state.tick, reached, rooms, bosses, kinds: kinds.len() }
        })
        .collect();
    outs.sort_by_key(|o| o.seed);
    for o in &outs {
        println!(
            "seed {}  score {}  ticks {}  rooms {}  kinds {}  bosses {}  {}",
            o.seed,
            o.score,
            o.ticks,
            o.rooms.len(),
            o.kinds,
            o.bosses,
            if o.reached { "-> run file" } else { "" }
        );
    }
    0
}
