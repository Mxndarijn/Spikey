//! Port of Yardstick/Runs.cs: one run as the yardstick keeps it, and its replay.
use sim::prelude::*;

use super::bots::BotSpec;

/// One run as the yardstick keeps it: where it was played and when it tapped.
/// Bots and humans give the same thing, so both are measured by one replay
/// (Run::analyze). Revives are not played: a run ends at its first death.
/// C# record RunInput(seed, season, taps, source = "").
#[derive(Clone, Debug)]
pub struct RunInput {
    pub seed: i64,
    pub season: i64,
    pub taps: Vec<i64>,
    #[allow(dead_code)]
    pub source: String,
}

impl RunInput {
    pub fn new(seed: i64, season: i64, taps: Vec<i64>, source: &str) -> RunInput {
        RunInput { seed, season, taps, source: source.to_string() }
    }
}

/// What one replayed run tells the yardstick.
#[derive(Clone, Debug)]
pub struct Run {
    pub input: RunInput,
    pub points: i64,
    pub ticks: i64,
    pub start_tick: i64,
    pub dead: bool,
    pub room: String,
    pub cause: String,
    /// Ticks between taps after the start tap.
    pub intervals: Vec<i32>,
    /// Ticks spent in each of 8 height bands (KILL_TOP at band 0 .. KILL_BOTTOM).
    pub bands: [i64; Run::BANDS],
    /// Ticks from a wall bounce (a new wall ahead) to the next tap.
    pub react_bounce: Vec<i32>,
    /// Ticks from a new room or a new hazard in the room to the next tap.
    pub react_new: Vec<i32>,
    /// Rooms entered ("id" or "id/variant"), the first one included, in first-entered order
    /// (C# Dictionary<string, int>, whose enumeration is insertion order).
    pub visits: Vec<(String, i32)>,
    pub taps_played: i32,
    /// Taps made while the bird waits at a portal, which the game ignores.
    pub taps_held: i32,
}

impl Run {
    pub const BANDS: usize = 8;
    pub const BAND_H: i64 = (SimConfig::KILL_BOTTOM - SimConfig::KILL_TOP) / Self::BANDS as i64;
    /// A first tap more than this many ticks after a new thing is not a reaction to it.
    pub const REACT_WINDOW: i32 = 60;

    fn blank(input: RunInput) -> Run {
        Run {
            input,
            points: 0,
            ticks: 0,
            start_tick: 0,
            dead: false,
            room: String::new(),
            cause: String::new(),
            intervals: Vec::new(),
            bands: [0; Run::BANDS],
            react_bounce: Vec::new(),
            react_new: Vec::new(),
            visits: Vec::new(),
            taps_played: 0,
            taps_held: 0,
        }
    }

    pub fn seconds(&self) -> f64 {
        (self.ticks - self.start_tick).max(1) as f64 / SimConfig::TICKS_PER_SECOND as f64
    }

    pub fn taps_per_s(&self) -> f64 {
        (self.taps_played - 1).max(0) as f64 / self.seconds()
    }

    pub fn room_name(sim: &GameSim) -> String {
        let v = sim.room.variant_id();
        if v.is_empty() {
            sim.room.def().id.to_string()
        } else {
            format!("{}/{}", sim.room.def().id, v)
        }
    }

    /// Plays `bot` from a fresh sim of `seed` to death or `cap` ticks and
    /// returns the taps it made.
    pub fn play(bot: &BotSpec, seed: i64, cap: i64) -> RunInput {
        let mut decide = (bot.make)(seed);
        let mut sim = GameSim::new(seed);
        let mut taps = Vec::new();
        while sim.state.tick < cap && !sim.is_over() {
            let tap = decide(&sim);
            if tap {
                taps.push(sim.state.tick);
            }
            sim.step(tap);
        }
        RunInput::new(seed, Seasons::NONE, taps, &bot.name)
    }

    fn visit(visits: &mut Vec<(String, i32)>, name: String) {
        match visits.iter_mut().find(|(k, _)| *k == name) {
            Some(kv) => kv.1 += 1,
            None => visits.push((name, 1)),
        }
    }

    /// Replays `r` to its first death or `cap` ticks and measures it.
    pub fn analyze(r: &RunInput, cap: i64) -> Run {
        let mut run = Run::blank(r.clone());
        let mut sim = GameSim::with(r.seed, r.season, -1, "");
        let start_score = sim.state.score;
        let mut next = 0usize;
        let mut last_tap: i64 = -1;
        let mut pending_bounce: Vec<i64> = Vec::new();
        let mut pending_new: Vec<i64> = Vec::new();
        let mut hazards = sim.room.hazards.len();
        // run.visits[room_name(sim)] = 1
        let first = Self::room_name(&sim);
        run.visits.push((first, 1));
        run.start_tick = -1;
        while sim.state.tick < cap && !sim.is_over() {
            let t = sim.state.tick;
            let tap = next < r.taps.len() && r.taps[next] == t;
            if tap {
                next += 1;
            }
            if sim.state.started {
                let b = (sim.state.y - SimConfig::KILL_TOP) / Self::BAND_H;
                run.bands[b.clamp(0, Self::BANDS as i64 - 1) as usize] += 1;
            }
            // A tap during the portal wait (arrival_hold) does nothing in the game: not counted.
            if tap && sim.state.arrival_hold > 0 {
                run.taps_held += 1;
            } else if tap {
                run.taps_played += 1;
                if last_tap >= 0 && sim.state.started {
                    run.intervals.push((t - last_tap) as i32);
                }
                last_tap = t;
                for &e in &pending_bounce {
                    if t - e <= Self::REACT_WINDOW as i64 {
                        run.react_bounce.push((t - e) as i32);
                    }
                }
                for &e in &pending_new {
                    if t - e <= Self::REACT_WINDOW as i64 {
                        run.react_new.push((t - e) as i32);
                    }
                }
                pending_bounce.clear();
                pending_new.clear();
            }
            let was_started = sim.state.started;
            sim.step(tap);
            if !was_started && sim.state.started {
                run.start_tick = sim.state.tick;
            }
            let mut room_change = false;
            for &ev in &sim.events {
                if ev == Event::BOUNCE {
                    pending_bounce.push(sim.state.tick);
                }
                if ev == Event::ROOM_CHANGE {
                    room_change = true;
                }
            }
            let now = sim.room.hazards.len();
            if room_change {
                let name = Self::room_name(&sim);
                Self::visit(&mut run.visits, name);
                pending_new.push(sim.state.tick);
            } else if now > hazards {
                pending_new.push(sim.state.tick);
            }
            hazards = now;
        }
        if run.start_tick < 0 {
            run.start_tick = sim.state.tick;
        }
        run.points = sim.state.score - start_score;
        run.ticks = sim.state.tick;
        run.dead = sim.is_over();
        run.room = Self::room_name(&sim);
        run.cause = if run.dead { DeathCause::NAMES[sim.state.death_cause as usize].to_string() } else { String::new() };
        run
    }
}
