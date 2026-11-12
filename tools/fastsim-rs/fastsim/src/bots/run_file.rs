//! Port of Bots/RunFile.cs: writes a run file, the same JSON as meta/run_file.gd
//! (RunFile), for tools/render_run.ps1 (docs/RENDERING.md). Record every tick
//! the bot tapped on (and every revive) while it plays, then call `write` with
//! the sim as it ended.
use serde_json::{json, Map, Value};
use sim::prelude::*;

use crate::bots::SimBots;

pub struct RunFile;

impl RunFile {
    pub const FORMAT: &'static str = "flapjaw_run";
    pub const FORMAT_VERSION: i64 = 1;

    /// The run file of `sim` (as it ended) played with `taps` (and `revives`).
    /// `loadout`: ItemKind -> id; `settings`: color_blind_spikes, reduced_flashing, large_buttons.
    pub fn make(
        sim: &GameSim,
        taps: &[i64],
        revives: &[i64],
        loadout: &[(&str, &str)],
        name: &str,
        settings: &[(&str, bool)],
    ) -> Value {
        let mut look = Map::new();
        for (k, v) in loadout {
            look.insert(k.to_string(), json!(v));
        }
        let mut flags = Map::new();
        for (k, v) in settings {
            flags.insert(k.to_string(), json!(v));
        }
        json!({
            "format": Self::FORMAT,
            "format_version": Self::FORMAT_VERSION,
            "gameplay_version": SimConfig::GAMEPLAY_VERSION,
            "seed": sim.seed_value,
            "season": sim.season,
            "taps": taps,
            "revives": revives,
            "score": sim.state.score,
            "coins": sim.state.coins,
            "end_tick": sim.state.tick,
            "checksum": sim.checksum(),
            "name": name,
            "loadout": Value::Object(look),
            "settings": Value::Object(flags),
        })
    }

    pub fn write(path: &str, sim: &GameSim, taps: &[i64], revives: &[i64], name: &str) -> std::io::Result<()> {
        let v = Self::make(sim, taps, revives, &[], name, &[]);
        std::fs::write(path, crate::yardstick::json_pretty(&v) + "\n")
    }

    /// `fastsim-rs runfile <seed> [bot_seed] --out <file>`: a gap_seeker run, as an
    /// example run file and for tests of the renderer.
    pub fn run_mode(seed_value: i64, bot_seed: i64, out_path: &str) -> i32 {
        let mut sim = GameSim::new(seed_value);
        let mut rng = SimRng::new(bot_seed);
        let mut taps = Vec::new();
        while !sim.is_over() && sim.state.tick < SimConfig::MAX_TICKS {
            let tap = SimBots::gap_seeker(&sim, &mut rng);
            if tap {
                taps.push(sim.state.tick);
            }
            sim.step(tap);
        }
        if let Err(e) = Self::write(out_path, &sim, &taps, &[], "gap seeker") {
            eprintln!("fastsim-rs runfile: cannot write {out_path}: {e}");
            return 2;
        }
        println!(
            "fastsim runfile: seed {seed_value}, score {}, {} ticks -> {out_path}",
            sim.state.score, sim.state.tick
        );
        0
    }
}
