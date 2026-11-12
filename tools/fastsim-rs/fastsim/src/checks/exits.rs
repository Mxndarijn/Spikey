//! Checks.Exits and ExitMouth (ExitChecks.cs), `fastsim check exits`: from the step after an
//! exit is drawn (its ghost, or its opening) until the bird leaves, no hazard kills in, or turns
//! the bird back from, its mouth (sim/exit_zone.gd), and no wall spike reaches into it; two plays
//! of a seed that fly differently meet each exit at the same place.
use std::collections::HashMap;
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{i, result, Check};
use crate::bots::SurvivalSearch;

/// A C# Dictionary<string, string> with only adds: keys in insertion order.
#[derive(Default)]
pub struct Seen {
    pub list: Vec<(String, String)>,
    at: HashMap<String, usize>,
}

impl Seen {
    pub fn get(&self, k: &str) -> Option<&String> {
        self.at.get(k).map(|&n| &self.list[n].1)
    }
    pub fn insert(&mut self, k: String, v: String) {
        match self.at.get(&k) {
            Some(&n) => self.list[n].1 = v,
            None => {
                self.at.insert(k.clone(), self.list.len());
                self.list.push((k, v));
            }
        }
    }
}

/// Probes: is anything in an exit's mouth now? Bird circles from touching the wall to one bird
/// radius back, within EXIT_HALF of the exit's height.
pub struct ExitMouth;

/// What a play met: the first failure, and its exits by (room number, room, wall, exit score)
/// -> heights.
#[derive(Default)]
pub struct Play {
    pub bad: String,
    pub exits: i32,
    pub seen: Seen,
}

impl ExitMouth {
    pub const STEP: i64 = 2 * SimConfig::SUB;

    /// The kinds of hazard that kill a bird somewhere in an exit's mouth (ExitZone's boxes) right
    /// now, or that turn back a bird flying into it.
    pub fn blockers(sim: &mut GameSim) -> Vec<String> {
        let mut hits: Vec<String> = Vec::new();
        let n = ExitZone::BOXES;
        let r = SimConfig::BIRD_RADIUS;
        let keep_x = sim.state.x;
        let keep_y = sim.state.y;
        for i in 0..n {
            let side = ExitZone::box_side(sim, i);
            let ey = ExitZone::box_y(sim, i);
            if ey == 0 {
                continue;
            }
            let wall = if side == 1 { sim.room.wall_right() - r } else { sim.room.wall_left() + r };
            let dir = if side == 1 { -1 } else { 1 };
            let mut dx = 0;
            while dx < r {
                let mut dy = -SimConfig::EXIT_HALF;
                while dy <= SimConfig::EXIT_HALF {
                    sim.state.x = wall + dir * dx;
                    sim.state.y = ey + dy;
                    for h in &sim.room.hazards {
                        if h.alive() && h.kills(sim) && !hits.iter().any(|x| x == h.kind()) {
                            hits.push(h.kind().to_string());
                        }
                    }
                    dy += Self::STEP;
                }
                dx += Self::STEP;
            }
        }
        sim.state.x = keep_x;
        sim.state.y = keep_y;
        // Solid things (Bumper Cloud, bubbles, balls): one that turns a bird in the mouth back
        // from the wall blocks the exit too.
        for i in 0..n {
            let side = ExitZone::box_side(sim, i);
            let ey = ExitZone::box_y(sim, i);
            if ey == 0 {
                continue;
            }
            let wall = if side == 1 { sim.room.wall_right() - r } else { sim.room.wall_left() + r };
            let dir = if side == 1 { -1 } else { 1 };
            for dy in [-SimConfig::EXIT_HALF / 2, 0, SimConfig::EXIT_HALF / 2] {
                let mut c = sim.clone_deep();
                c.state.x = wall;
                c.state.y = ey + dy;
                c.state.vx = -dir * SimConfig::SPEED_X;
                c.state.vy = 0;
                let mut k = 0;
                while k < c.room.hazards.len() {
                    if !c.room.hazards[k].alive() {
                        k += 1;
                        continue;
                    }
                    let kind = c.room.hazards[k].kind();
                    c.with_hazard(k, |h, s| h.touch(s));
                    if c.state.vx * -dir <= 0 {
                        let name = format!("{} (turns back)", kind);
                        if !hits.contains(&name) {
                            hits.push(name);
                        }
                        c.state.vx = -dir * SimConfig::SPEED_X;
                    }
                    k += 1;
                }
            }
        }
        hits
    }

    /// From an exit's ghost until it closes, no wall spike (slid by a belt or not) reaches into
    /// its mouth (the opening and a bird radius).
    pub fn spike_in_mouth(sim: &GameSim) -> String {
        let st = &sim.state;
        if !st.exit_open && !st.exit_preview {
            return String::new();
        }
        let side = st.exit_side;
        let mask = sim.wall_mask(side);
        let shift = sim.wall_shift(side);
        let mut ys = vec![st.exit_a_y];
        if st.exit_b_kind != ExitKind::NORMAL {
            ys.push(st.exit_b_y);
        }
        for slot in 0..SimConfig::SLOT_COUNT {
            if (mask & (1i64 << slot)) == 0 {
                continue;
            }
            let cy = SimConfig::slot_center_y(slot) + shift;
            for &ey in &ys {
                if G::absi(cy - ey) <= ExitZone::HALF + SimConfig::SPIKE_HALF_BASE {
                    return format!("wall spike at {} px", cy / SimConfig::SUB);
                }
            }
        }
        String::new()
    }

    /// Plays `inputs` on `sim`, checking every step: nothing in a mouth (from the first hazard
    /// step after the boxes appeared or moved: hazards step before the bird, so they keep out of
    /// a new box from the next step on), no spike in a shown exit's mouth, and the exits met.
    pub fn watch(mut sim: GameSim, inputs: impl IntoIterator<Item = u8>) -> Play {
        let mut play = Play::default();
        let mut key: i64 = -1;
        let mut since: i64 = -1;
        for tap in inputs {
            sim.step(tap == 1);
            if !sim.state.alive {
                break;
            }
            let room = format!(
                "{}/{}",
                RoomCatalog::all()[sim.state.room_kind as usize].id,
                sim.room.variant_id()
            );
            let where_ = format!("tick {} score {} {}", sim.state.tick, sim.state.score, room);
            if sim.state.exit_open || sim.state.exit_preview {
                let st = &sim.state;
                let at = (st.score + 1) / SimConfig::POINTS_PER_ROOM;
                let k = format!("room {} {} side {} exit {}", st.room_index, room, st.exit_side, at);
                let v = format!("{}", st.exit_a_y / SimConfig::SUB)
                    + &if st.exit_b_kind != ExitKind::NORMAL {
                        format!("/{}", st.exit_b_y / SimConfig::SUB)
                    } else {
                        String::new()
                    };
                match play.seen.get(&k).cloned() {
                    None => {
                        play.seen.insert(k, v.clone());
                        play.exits += 1;
                    }
                    Some(old) => {
                        if old != v && play.bad.is_empty() {
                            play.bad = format!(
                                "{}: exit moved from {} to {} px on wall {}",
                                where_, old, v, st.exit_side
                            );
                        }
                    }
                }
                let sp = Self::spike_in_mouth(&sim);
                let st = &sim.state;
                if !sp.is_empty() && play.bad.is_empty() {
                    play.bad = format!(
                        "{}: {} exit {} px side {}: {}",
                        where_,
                        if st.exit_open { "open" } else { "ghost" },
                        v,
                        st.exit_side,
                        sp
                    );
                }
            }
            let n = ExitZone::BOXES;
            let mut now = sim.state.room_index;
            for i in 0..n {
                now = SimHash::mix(SimHash::mix(now, ExitZone::box_side(&sim, i)), ExitZone::box_y(&sim, i));
            }
            if now != key {
                key = now;
                since = sim.room.t;
                continue;
            }
            if now == -1 || sim.room.t <= since || !play.bad.is_empty() {
                continue;
            }
            let b = Self::blockers(&mut sim);
            if !b.is_empty() {
                let mut boxes: Vec<String> = Vec::new();
                for i in 0..n {
                    if ExitZone::box_y(&sim, i) != 0 {
                        boxes.push(format!(
                            "{} px side {}",
                            ExitZone::box_y(&sim, i) / SimConfig::SUB,
                            ExitZone::box_side(&sim, i)
                        ));
                    }
                }
                play.bad = format!("{}, exit mouth {}: {}", where_, boxes.join(", "), b.join(", "));
            }
        }
        play
    }
}

/// Every variant of every room (practice, SurvivalSearch through the first portal) and full runs
/// through the portals in every season, seed 4206176851 among them, each played twice with
/// different taps: nothing is ever in an exit's mouth, no spike in a shown exit's mouth, and both
/// plays meet the same exits.
#[derive(Default)]
pub struct Exits {
    /// [kind, room index or season, variant, seed].
    _cases: OnceLock<Vec<(&'static str, i64, &'static str, i64)>>,
}

impl Exits {
    pub const SEEDS_EACH: i32 = 8;
    pub const ROOM_TICKS: i64 = 1700;
    pub const RUN_SEEDS: [i64; 6] = [4206176851, 3392377610, 1, 77, 5000, 9131];
    pub const RUN_TICKS: i64 = 12000;
    /// Taps for the first steps of the second play, so it flies another way into the same seed.
    pub const OTHER_START: [u8; 29] =
        [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1];

    fn cases(&self) -> &Vec<(&'static str, i64, &'static str, i64)> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<(&'static str, i64, &'static str, i64)> {
        let mut out_ = Vec::new();
        let all = RoomCatalog::all();
        for i in 0..all.len() {
            let ids: Vec<&'static str> =
                if all[i].variants.is_empty() { vec![""] } else { all[i].variants.iter().map(|v| v.id).collect() };
            for v in ids {
                for k in 0..Self::SEEDS_EACH {
                    out_.push(("room", i as i64, v, 1000 + k as i64 * 77));
                }
            }
        }
        for seed in Self::RUN_SEEDS {
            for season in Seasons::NONE..Seasons::COUNT {
                out_.push(("run", season, "", seed));
            }
        }
        out_
    }
}

impl Check for Exits {
    fn name(&self) -> &'static str {
        "exits"
    }
    fn test(&self) -> &'static str {
        "tests/sim/test_exit_clear.gd:test_no_hazard_in_an_exit_mouth"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (kind, a, v, seed) = self.cases()[n];
        let start = || {
            if kind == "room" {
                GameSim::with(seed, RoomCatalog::all()[a as usize].season, a, v)
            } else {
                GameSim::with(seed, a, -1, "")
            }
        };
        let what = if kind == "room" {
            format!("{}/{} seed {}", RoomCatalog::all()[a as usize].id, v, seed)
        } else {
            format!("run seed {} season {}", seed, a)
        };
        let ticks = if kind == "room" { Self::ROOM_TICKS } else { Self::RUN_TICKS };
        let mut fails: Vec<String> = Vec::new();
        let mut search = SurvivalSearch::new();
        search.run_quick(&start(), ticks);
        let one = ExitMouth::watch(start(), search.best_inputs.iter().copied());
        if !one.bad.is_empty() {
            fails.push(format!("{}: {}", what, one.bad));
        }
        let mut lead = start();
        for tap in Self::OTHER_START {
            lead.step(tap == 1);
        }
        let mut other = SurvivalSearch::new();
        other.run_quick(&lead, ticks);
        let two = ExitMouth::watch(start(), Self::OTHER_START.iter().copied().chain(other.best_inputs.iter().copied()));
        if !two.bad.is_empty() {
            fails.push(format!("{} (other taps): {}", what, two.bad));
        }
        let mut same = 0;
        for (k, y) in &one.seen.list {
            let Some(y2) = two.seen.get(k) else { continue };
            same += 1;
            if y != y2 {
                fails.push(format!("{}: {}: at {} px in one play, {} px in the other", what, k, y, y2));
            }
        }
        result(fails, json!({ "exits": one.exits + two.exits, "same": same }))
    }

    fn summary(&self, results: &[Value]) -> String {
        let exits: i64 = results.iter().map(|r| i(&r["exits"])).sum();
        let same: i64 = results.iter().map(|r| i(&r["same"])).sum();
        format!(
            "{} exits in {} plays, {} met by both plays of a seed ({} practice seeds per variant, {} run seeds x {} seasons)",
            exits,
            2 * results.len(),
            same,
            Self::SEEDS_EACH,
            Self::RUN_SEEDS.len(),
            Seasons::COUNT + 1
        )
    }
}
