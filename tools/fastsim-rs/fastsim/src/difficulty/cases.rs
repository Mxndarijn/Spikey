//! Port of Difficulty/Cases.cs: the rooms and variants the difficulty tool scores, the room
//! entries every measure starts from, and `fastsim check difficulty` (DifficultyCheck).
use std::collections::{HashMap, HashSet};

use serde_json::{json, Value};
use sim::prelude::*;

use super::tube::Tube;
use crate::checks::passable::Passable;
use crate::checks::Check;
use crate::human::fmt_f;
use crate::setups::Reaction;

/// One thing to score: a room, or one variant of it.
#[derive(Clone)]
pub struct Target {
    pub index: i32,
    pub def: &'static RoomDef,
    pub variant: &'static str,
    pub label: String,
    pub cap: i64,
}

impl Target {
    pub fn boss(&self) -> bool {
        self.def.boss
    }
}

/// The rooms and variants the difficulty tool scores, and the room entries every measure
/// starts from (the same entries for every measure and bot, so they can be compared trial by
/// trial).
pub struct Cases;

impl Cases {
    /// Ticks a trial may last: well past the room's own exit (Passable.CASES
    /// ticks plus the arrival hold and some spare), so a slow line still counts.
    pub const SPARE: i64 = 450;
    pub const DEFAULT_TICKS: i64 = 1150;

    /// C# default: filter = "*".
    pub fn all(filter: &str) -> Vec<Target> {
        let caps: HashMap<&str, i64> = Passable::CASES.iter().map(|c| (c.0, c.1)).collect();
        let mut out_ = Vec::new();
        let defs = RoomCatalog::all();
        let wanted: Option<HashSet<&str>> =
            if filter == "*" || filter.is_empty() || filter == "all" { None } else { Some(filter.split(',').collect()) };
        for i in 0..defs.len() {
            let def = &defs[i];
            let cap = caps.get(def.id).copied().unwrap_or(Self::DEFAULT_TICKS) + Self::SPARE;
            if def.variants.is_empty() {
                if Self::keep(&wanted, def.id, "") {
                    out_.push(Target { index: i as i32, def, variant: "", label: def.id.to_string(), cap });
                }
                continue;
            }
            for v in &def.variants {
                if Self::keep(&wanted, def.id, v.id) {
                    out_.push(Target { index: i as i32, def, variant: v.id, label: format!("{}/{}", def.id, v.id), cap });
                }
            }
        }
        out_
    }

    fn keep(wanted: &Option<HashSet<&str>>, id: &str, v: &str) -> bool {
        match wanted {
            None => true,
            Some(w) => w.contains(id) || w.contains(format!("{}/{}", id, v).as_str()),
        }
    }

    /// Entry `i` into the target: a portal arrival as in a real run (Reaction.arrival:
    /// heights spread over the screen, both sides, a few scores and layout seeds),
    /// at a height the game would bring this variant in at. Bosses: through the
    /// boss portal at 100 (as the boss review, BossRuns.arrive).
    /// Err: C# throws (the measure writes an error row).
    pub fn arrive(t: &Target, i: i64) -> Result<GameSim, String> {
        if t.boss() {
            return Self::arrive_boss(t, i);
        }
        let def = t.def;
        let mut sim = GameSim::with(9000 + i * 37, def.season, -1, "");
        sim.forced_variant = t.variant;
        sim.step(true);
        let mut score = G::maxi(def.from_score, 10) + (i % 3) * 10;
        if score % SimConfig::BOSS_EVERY == 0 {
            score += 10;
        }
        sim.state.score = score;
        let mut y = 130 + (i * 53) % 380;
        let forced = def.variants.iter().find(|v| v.id == t.variant);
        for _ in 0..380 {
            if def.fits_arrival(y * SimConfig::SUB) && forced.is_none_or(|f| f.fits_arrival(y * SimConfig::SUB)) {
                break;
            }
            y = 130 + (y - 130 + 53) % 380;
        }
        sim.state.anchor_y = y * SimConfig::SUB;
        sim.state.y = GameSim::_arrival_y(
            sim.state.anchor_y + Reaction::OFFSETS[(i / 2 % Reaction::OFFSETS.len() as i64) as usize] * SimConfig::SUB,
        );
        let side = i % 2;
        let skip = sim._arrival_retries(side, t.index as i64);
        for _ in 0..skip {
            sim._rng.next_u32();
        }
        sim._arrive_in(side, t.index as i64);
        if sim.room.def().id != def.id || sim.room.variant_id() != t.variant {
            return Err(format!("wanted {}, got {}/{}", t.label, sim.room.def().id, sim.room.variant_id()));
        }
        Ok(sim)
    }

    fn arrive_boss(t: &Target, i: i64) -> Result<GameSim, String> {
        // Some seeds still bring another boss in (the spine's own draws): try the next
        // seed in a fixed order until it is this one.
        for k in 0..64i64 {
            let seed = 1 + i + k * 100003;
            let mut sim = GameSim::new(seed);
            sim.step(true);
            sim.state.score = SimConfig::BOSS_EVERY;
            sim.state.bosses_met = 7 & !RoomCatalog::boss_bit(t.index as i64);
            let mut r = SimRng::new(seed * 31 + 7);
            sim._go_through(1, ExitKind::NORMAL, (200 + r.next_below(261)) * SimConfig::SUB);
            if sim.room.def().id == t.def.id {
                return Ok(sim);
            }
        }
        Err(format!("no seed brings {} in", t.label))
    }

    /// The room is beaten: the bird went through the exit, or (boss rooms) the boss is down.
    pub fn cleared(s: &GameSim, room: i64) -> bool {
        if s.state.room_index > room {
            return true;
        }
        if !s.room.def().boss {
            return false;
        }
        for h in &s.room.hazards {
            if let Some(b) = h.as_boss() {
                if b.down_at >= 0 {
                    return true;
                }
            }
        }
        false
    }
}

/// `fastsim check difficulty`: the tube finds a way through a plain room, and a
/// room with shutter gates leaves a narrower band than Open Sky on the same entries.
pub struct DifficultyCheck;

impl DifficultyCheck {
    const CASES: [(&'static str, i64); 4] = [("open", 0), ("open", 1), ("gates/classic", 0), ("gates/classic", 1)];
}

impl Check for DifficultyCheck {
    fn name(&self) -> &'static str {
        "difficulty"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim/Difficulty:tube"
    }
    fn count(&self) -> usize {
        Self::CASES.len()
    }

    fn run(&self, n: usize) -> Value {
        let (room, entry) = Self::CASES[n];
        let t = Cases::all(room).into_iter().next().unwrap_or_else(|| panic!("no room {}", room));
        let start = Cases::arrive(&t, entry).unwrap_or_else(|e| panic!("{}", e));
        let r = Tube::new().run(&start, t.cap);
        let mut fails: Vec<String> = Vec::new();
        if !r.way {
            fails.push(format!("{} entry {}: the tube found no way through", room, entry));
        }
        json!({ "fails": fails, "room": room, "band": r.band_p10 })
    }

    fn combine(&self, results: &[Value]) -> Vec<String> {
        // Enumerable.Average over (double) nodes: a sequential sum, then one division.
        let band = |room: &str| -> f64 {
            let xs: Vec<f64> =
                results.iter().filter(|r| r["room"].as_str() == Some(room)).map(|r| r["band"].as_f64().unwrap_or(0.0)).collect();
            if xs.is_empty() {
                panic!("Sequence contains no elements");
            }
            xs.iter().fold(0.0, |a, &x| a + x) / xs.len() as f64
        };
        let mut f = Vec::new();
        if band("gates/classic") >= band("open") {
            f.push(format!(
                "gates/classic band p10 {} px is not below open's {} px",
                fmt_f(band("gates/classic"), 0),
                fmt_f(band("open"), 0)
            ));
        }
        f
    }

    fn summary(&self, results: &[Value]) -> String {
        format!("{} tubes (open, gates/classic)", results.len())
    }
}
