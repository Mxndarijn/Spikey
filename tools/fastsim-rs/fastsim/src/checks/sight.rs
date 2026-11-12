//! Checks.SightCheck (Perception.cs), `sight`: every bot sees every hazard (docs/BOT_SIGHT.md).
//! For every hazard class a few rooms that hold it are played on a line that lives
//! (SurvivalSearch). The truth is the sim's own kills(): the bird is moved to every point of a
//! 12 px grid and each hazard is asked.
//!   deadly  a tick where the hazard kills somewhere: does the bot's eye see that danger now?
//!   tell    an onset: danger that appears where the hazard killed nothing 24 px around one
//!           tick before. Asked LEAD ticks earlier: does the bot expect danger there at the onset?
//! Hidden values: every hazard field of type SimRng or named seed / salt is a hidden draw. Two
//! blind copies with different RNGs must differ in it (blind_copy replaces it).
//!
//! Ported eye: only BlindPlanner ("blind": a blind copy stepped on). The C# eyes world
//! (WorldPlanner, Models.Read), worldobs, mpc (Sight) and rl (Observer) are not ported, so
//! their columns, their input-change samples and their hidden-value read checks are left out;
//! the truth, the samples, the blind column and the hidden-draw check are as in C#.
use std::collections::BTreeMap;
use std::sync::OnceLock;
use std::time::Instant;

use serde_json::{json, Map, Value};
use sim::prelude::*;

use super::honesty::hz_name;
use super::passable::Passable;
use super::{culture_cmp, i, result, Check};
use crate::bots::blind_planner::BlindPlanner;
use crate::bots::SurvivalSearch;

/// (class, bot) samples: tell seen, of; deadly seen, of.
#[derive(Clone)]
struct Tally {
    tell_n: i64,
    deadly_n: i64,
    tell: Vec<i64>,
    deadly: Vec<i64>,
    tell_of: Vec<i64>,
    deadly_of: Vec<i64>,
}

impl Tally {
    fn new() -> Tally {
        let b = SightCheck::BOTS.len();
        Tally { tell_n: 0, deadly_n: 0, tell: vec![0; b], deadly: vec![0; b], tell_of: vec![0; b], deadly_of: vec![0; b] }
    }
}

/// A C# Dictionary<string, V>: keys in the order first added.
fn entry<'a, V>(map: &'a mut Vec<(String, V)>, key: &str, make: impl FnOnce() -> V) -> &'a mut V {
    let k = match map.iter().position(|e| e.0 == key) {
        Some(k) => k,
        None => {
            map.push((key.to_string(), make()));
            map.len() - 1
        }
    };
    &mut map[k].1
}

/// One sample: (hazard index, tell, cells, onset tick).
type Sample = (usize, bool, Vec<usize>, i64);

#[derive(Default)]
pub struct SightCheck {
    _cases: OnceLock<Vec<(usize, &'static str, i64)>>,
}

impl SightCheck {
    pub const CELL: i64 = 12 * SimConfig::SUB;
    pub const COLS: usize = (SimConfig::WORLD_W / Self::CELL) as usize;
    pub const ROWS: usize = ((SimConfig::KILL_BOTTOM - SimConfig::KILL_TOP) / Self::CELL) as usize;
    /// Ticks between the look and the onset it must expect (1/3 s; the fairness rule is about 1 s).
    pub const LEAD: i64 = 20;
    /// Danger points within this of a bot's shape count as seen (the unported eyes).
    #[allow(dead_code)]
    pub const TOL: i64 = 8 * SimConfig::SUB;
    /// Plays per hazard class: rooms that place it, then more seeds of them.
    pub const SCENES_PER_CLASS: i64 = 3;
    pub const MAX_POINTS: usize = 24;
    pub const DEADLY_EVERY: i64 = 30;
    pub const LEAK_EVERY: i64 = 30;
    pub const MIN_RATE: f64 = 0.5;
    pub const MIN_SAMPLES: i64 = 4;
    pub const DEFAULT_TICKS: i64 = 1150;

    /// The BlindPlanner (the world, worldobs, mpc and rl eyes were retired with C# FastSim).
    pub const BOTS: [&'static str; 1] = ["blind"];

    /// Hazard classes that are only a base (never placed themselves).
    pub const BASES: [(&'static str, &'static str); 1] = [("Boss", "base of the boss hazards")];

    /// Blind cells allowed while their fix is in flight: (class, bot, "tell" or "deadly", fix
    /// session). Empty: every hazard is seen (the entries for the retired bots went with them).
    pub const KNOWN: [(&'static str, &'static str, &'static str, &'static str); 0] = [];

    fn known(cls: &str, bot: &str, what: &str) -> bool {
        Self::KNOWN.iter().any(|k| k.0 == cls && k.1 == bot && k.2 == what)
    }

    /// C# `classes()`: every hazard class that is not abstract (Boss is a class, not in `Hz`), by name.
    pub fn classes() -> Vec<&'static str> {
        let mut out_: Vec<&'static str> = vec![
            "Beam", "Belt", "Block", "Boss", "BossCrusher", "BossSaw", "BossWatcher", "Bouncer", "Bubble",
            "Bumper", "CoinPickup", "CrateDrop", "Crawler", "CuriousBouncer", "Dart", "Drop", "Echo",
            "EdgePad", "ExitKey", "Firework", "Gate", "HeavyBouncer", "KeepyBall", "Lava", "Mover",
            "OrbitCoin", "OrchardSpawner", "PadCoin", "Pendulum", "Piston", "RevvingBouncer", "Rotor",
            "SawRing", "SpikeBall", "SplittingBouncer", "Stalactite", "Stalker", "Updraft", "Wind",
        ];
        out_.sort_by(|a, b| culture_cmp(a, b));
        out_
    }

    /// C# `hidden_fields(type)` read on a hazard: (field name, value) of every field of type
    /// SimRng (its state checksum) or a long named seed / salt / *_seed / *_salt.
    fn hidden_values(h: &Hz) -> Vec<(&'static str, i64)> {
        match h {
            Hz::BossCrusher(_) | Hz::BossSaw(_) | Hz::BossWatcher(_) => vec![("seed", h.as_boss().unwrap().seed)],
            Hz::CrateDrop(x) => vec![("salt", x.salt)],
            Hz::Dart(x) => vec![("salt", x.salt)],
            Hz::Drop(x) => vec![("_rng", x._rng.state_checksum())],
            Hz::Firework(x) => vec![("_rng", x._rng.state_checksum())],
            Hz::OrchardSpawner(x) => vec![("_rng", x._rng.state_checksum())],
            _ => Vec::new(),
        }
    }

    fn only() -> String {
        std::env::var("FASTSIM_SIGHT_ONLY").unwrap_or_default()
    }

    fn cases(&self) -> &Vec<(usize, &'static str, i64)> {
        self._cases.get_or_init(Self::make)
    }

    /// [room index, variant id, again]: SCENES_PER_CLASS plays per hazard class, in different
    /// rooms while there are, then on other seeds.
    fn make() -> Vec<(usize, &'static str, i64)> {
        let all = RoomCatalog::all();
        let mut scenes: Vec<(usize, &'static str, i64)> = Vec::new();
        let mut per: Vec<(String, i64)> = Vec::new();
        let mut holds: Vec<((usize, &'static str), Vec<&'static str>)> = Vec::new();
        let only = Self::only();
        for i in 0..all.len() {
            let def = &all[i];
            let ids: Vec<&'static str> =
                if def.variants.is_empty() { vec![""] } else { def.variants.iter().map(|v| v.id).collect() };
            for id in ids {
                let mut made: Vec<&'static str> = def.hazards.iter().map(|f| hz_name(&f())).collect();
                if let Some(v) = def.variants.iter().find(|x| x.id == id) {
                    made.extend(v.hazards.iter().map(|f| hz_name(&f())));
                    // A GENERATED variant has no factories: build the room (practice) and read it.
                    if v.kind == Kind::GENERATED {
                        let sim = GameSim::with(1, def.season, i as i64, id);
                        made.extend(sim.room.hazards.iter().map(hz_name));
                    }
                }
                let mut distinct: Vec<&'static str> = Vec::new();
                for t in made {
                    if !distinct.contains(&t) {
                        distinct.push(t);
                    }
                }
                let mut want = false;
                for &t in &distinct {
                    let n = entry(&mut per, t, || 0);
                    if *n < Self::SCENES_PER_CLASS {
                        want = true;
                    }
                    *n += 1;
                }
                // FASTSIM_SIGHT_ONLY: only rooms whose label contains it (to time or debug one room).
                let label = if id.is_empty() { def.id.to_string() } else { format!("{}/{}", def.id, id) };
                if !label.contains(only.as_str()) {
                    continue;
                }
                holds.push(((i, id), distinct));
                if want {
                    scenes.push((i, id, 0));
                }
            }
        }
        // A class in fewer rooms than SCENES_PER_CLASS: its rooms again, on other seeds.
        for again in 1..Self::SCENES_PER_CLASS {
            for ((i, id), types) in &holds {
                let want = types.iter().any(|t| *entry(&mut per, t, || 0) < Self::SCENES_PER_CLASS);
                if !want {
                    continue;
                }
                for t in types {
                    *entry(&mut per, t, || 0) += 1;
                }
                scenes.push((*i, *id, again));
            }
        }
        scenes
    }

    fn cx(c: usize) -> i64 {
        c as i64 * Self::CELL + Self::CELL / 2
    }

    fn cy(r: usize) -> i64 {
        SimConfig::KILL_TOP + r as i64 * Self::CELL + Self::CELL / 2
    }

    fn probe(sim: &mut GameSim, i: usize, cell: usize) -> bool {
        sim.state.x = Self::cx(cell % Self::COLS);
        sim.state.y = Self::cy(cell / Self::COLS);
        sim.room.hazards[i].kills(&*sim)
    }

    /// The grid cells where hazard `i` kills a bird now. Coarse first (every other cell: a
    /// deadly zone is at least a bird wide, 28 px, so it covers a coarse point), then every cell
    /// around a coarse hit.
    fn danger(sim: &mut GameSim, i: usize) -> Vec<usize> {
        let mut out_: Vec<usize> = Vec::new();
        if !sim.room.hazards[i].alive() {
            return out_;
        }
        let saved = sim.state;
        let mut done = vec![false; Self::COLS * Self::ROWS];
        let mut hits: Vec<usize> = Vec::new();
        for r in (0..Self::ROWS).step_by(2) {
            for c in (0..Self::COLS).step_by(2) {
                let cell = r * Self::COLS + c;
                done[cell] = true;
                if Self::probe(sim, i, cell) {
                    hits.push(cell);
                }
            }
        }
        for &hit in &hits {
            let (c0, r0) = (hit % Self::COLS, hit / Self::COLS);
            for r in r0.saturating_sub(2)..=(r0 + 2).min(Self::ROWS - 1) {
                for c in c0.saturating_sub(2)..=(c0 + 2).min(Self::COLS - 1) {
                    let cell = r * Self::COLS + c;
                    if done[cell] {
                        continue;
                    }
                    done[cell] = true;
                    if Self::probe(sim, i, cell) {
                        out_.push(cell);
                    }
                }
            }
        }
        out_.extend(hits);
        out_.sort();
        sim.state = saved;
        out_
    }

    fn kills_at(sim: &mut GameSim, i: usize, cell: usize) -> bool {
        if !sim.room.hazards[i].alive() {
            return false;
        }
        let saved = sim.state;
        let k = Self::probe(sim, i, cell);
        sim.state = saved;
        k
    }

    /// Cells of `now` with no cell of `before` within 2 cells.
    fn onset(before: &[usize], now: &[usize]) -> Vec<usize> {
        if now.is_empty() {
            return now.to_vec();
        }
        let mut near = vec![false; Self::COLS * Self::ROWS];
        for &cell in before {
            let (c0, r0) = (cell % Self::COLS, cell / Self::COLS);
            for r in r0.saturating_sub(2)..=(r0 + 2).min(Self::ROWS - 1) {
                for c in c0.saturating_sub(2)..=(c0 + 2).min(Self::COLS - 1) {
                    near[r * Self::COLS + c] = true;
                }
            }
        }
        now.iter().copied().filter(|&cell| !near[cell]).collect()
    }

    fn thin(cells: &[usize]) -> Vec<usize> {
        if cells.len() <= Self::MAX_POINTS {
            return cells.to_vec();
        }
        (0..Self::MAX_POINTS).map(|k| cells[k * cells.len() / Self::MAX_POINTS]).collect()
    }

    fn half(cells: &[usize], mut seen: impl FnMut(usize) -> bool) -> bool {
        let n = cells.iter().filter(|&&c| seen(c)).count();
        n * 2 >= cells.len()
    }

    /// The matrix over every scene: class -> bot -> (tell seen, of; deadly seen, of).
    fn sum(results: &[Value]) -> Vec<(String, Tally)> {
        let mut out_: Vec<(String, Tally)> = Vec::new();
        for r in results {
            let Some(stats) = r["stats"].as_object() else { continue };
            for (k, v) in stats {
                let ta = entry(&mut out_, k, Tally::new);
                ta.tell_n += i(&v["tell_n"]);
                ta.deadly_n += i(&v["deadly_n"]);
                for b in 0..Self::BOTS.len() {
                    ta.tell[b] += i(&v["tell"][b]);
                    ta.tell_of[b] += i(&v["tell_of"][b]);
                    ta.deadly[b] += i(&v["deadly"][b]);
                    ta.deadly_of[b] += i(&v["deadly_of"][b]);
                }
            }
        }
        out_
    }

    /// "sees", "blind" or "-" (too few samples to judge).
    fn verdict(seen: i64, of: i64) -> &'static str {
        if of < Self::MIN_SAMPLES {
            "-"
        } else if seen as f64 >= Self::MIN_RATE * of as f64 {
            "sees"
        } else {
            "blind"
        }
    }
}

/// C# `s.PadRight(n)`.
fn pad(s: &str, n: usize) -> String {
    format!("{:<width$}", s, width = n)
}

impl Check for SightCheck {
    fn name(&self) -> &'static str {
        "sight"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim-rs/fastsim/src/checks/sight.rs:test_bots_see_every_hazard"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (index, variant, again) = self.cases()[n];
        let def = &RoomCatalog::all()[index];
        let seed: i64 = 700 + 31 * index as i64 + variant.len() as i64 + 1000 * again;
        let label = (if variant.is_empty() { def.id.to_string() } else { format!("{}/{}", def.id, variant) })
            + &(if again > 0 { format!(" (seed {})", seed) } else { String::new() });
        let ticks =
            Passable::CASES.iter().find(|c| c.0 == def.id).map(|c| c.1).unwrap_or(Self::DEFAULT_TICKS);
        let start = GameSim::with(seed, def.season, index as i64, variant);
        let clock = Instant::now();
        let mut search = SurvivalSearch::new();
        search.run_quick(&start.clone_deep(), ticks);
        let line: Vec<u8> = search.best_inputs.clone();
        let log = |what: &str| {
            if !Self::only().is_empty() {
                eprintln!("sight {}: {} at {} s", label, what, crate::human::fmt_f(clock.elapsed().as_secs_f64(), 1));
            }
        };
        let fails: Vec<String> = Vec::new();

        // Pass 1: the truth, every tick on the line, while in the first room.
        let mut sim = start.clone_deep();
        let mut truth: Vec<Vec<Vec<usize>>> = Vec::new();
        let mut room_t: Vec<i64> = Vec::new();
        let mut cls: Vec<&'static str> = Vec::new();
        while sim.state.tick < line.len() as i64 && !sim.is_over() && sim.state.room_index == 0 {
            while cls.len() < sim.room.hazards.len() {
                cls.push(hz_name(&sim.room.hazards[cls.len()]));
            }
            let count = sim.room.hazards.len();
            let mut row: Vec<Vec<usize>> = Vec::with_capacity(count);
            for i in 0..count {
                row.push(Self::danger(&mut sim, i));
            }
            truth.push(row);
            room_t.push(sim.room.t);
            let tap = line[sim.state.tick as usize] == 1;
            sim.step(tap);
        }
        let end = truth.len() as i64;
        log(&format!("line {} ticks, truth {} ticks", line.len(), end));
        let empty: Vec<usize> = Vec::new();
        fn at_<'a>(truth: &'a [Vec<Vec<usize>>], empty: &'a [usize], t: i64, i: usize) -> &'a [usize] {
            let row = &truth[t as usize];
            if i < row.len() {
                &row[i]
            } else {
                empty
            }
        }
        let at = |t: i64, i: usize| -> &[usize] { at_(&truth, &empty, t, i) };

        // The samples: deadly ticks and onsets (looked at LEAD ticks before).
        let mut looks: BTreeMap<i64, Vec<Sample>> = BTreeMap::new();
        for i in 0..cls.len() {
            let mut last_onset: i64 = -1000;
            let mut last_deadly: i64 = -1000;
            for t in 1..end {
                let now = at(t, i);
                if now.is_empty() {
                    continue;
                }
                if t - last_deadly >= Self::DEADLY_EVERY {
                    looks.entry(t).or_default().push((i, false, Self::thin(now), t));
                    last_deadly = t;
                }
                let fresh = Self::onset(at(t - 1, i), now);
                if !fresh.is_empty() && t - last_onset > Self::LEAD && t - Self::LEAD >= 1 {
                    looks.entry(t - Self::LEAD).or_default().push((i, true, Self::thin(&fresh), t));
                    last_onset = t;
                }
            }
        }

        log(&format!("{} looks", looks.values().map(|l| l.len()).sum::<usize>()));
        // Pass 2: the eyes, every tick, as each bot keeps them.
        let mut tally: Vec<(String, Tally)> = Vec::new();
        let mut hidden: Vec<(String, (i64, i64))> = Vec::new();
        let mut sim = start.clone_deep();
        for t in 0..end {
            if let Some(list) = looks.get(&t) {
                for (i, tell, cells, on) in list {
                    let (i, tell, on) = (*i, *tell, *on);
                    let key = cls[i];
                    let ta = entry(&mut tally, key, Tally::new);
                    let lead = on - t;
                    let mut seen: Vec<Option<bool>> = vec![None; Self::BOTS.len()];
                    // blind: a blind copy stepped on the bot's own line.
                    let mut bc = BlindPlanner::blind_copy(&sim, SimRng::new(seed * 31 + t * 7 + i as i64), -1, 0, -1, false, false);
                    let mut k = 0;
                    while k < lead && !bc.is_over() {
                        bc.step(line[(t + k) as usize] == 1);
                        k += 1;
                    }
                    if !bc.is_over() && bc.state.room_index == 0 {
                        seen[0] = Some(Self::half(cells, |c| Self::kills_at(&mut bc, i, c)));
                    }
                    // world, worldobs, mpc, rl: not ported.
                    for b in 0..Self::BOTS.len() {
                        let Some(s) = seen[b] else { continue };
                        if tell {
                            ta.tell_of[b] += 1;
                            if s {
                                ta.tell[b] += 1;
                            }
                        } else {
                            ta.deadly_of[b] += 1;
                            if s {
                                ta.deadly[b] += 1;
                            }
                        }
                    }
                    if tell {
                        ta.tell_n += 1;
                    } else {
                        ta.deadly_n += 1;
                    }
                }
            }
            if t % Self::LEAK_EVERY == 0 {
                // Hidden draws: two blind copies must differ in each.
                let a = BlindPlanner::blind_copy(&sim, SimRng::new(seed * 3 + t * 2 + 1), -1, 0, -1, false, false);
                let b = BlindPlanner::blind_copy(&sim, SimRng::new(seed * 3 + t * 2 + 2), -1, 0, -1, false, false);
                for i in 0..sim.room.hazards.len() {
                    let ht = hz_name(&sim.room.hazards[i]);
                    let va = Self::hidden_values(&a.room.hazards[i]);
                    let vb = Self::hidden_values(&b.room.hazards[i]);
                    for (f, (name, x)) in va.iter().enumerate() {
                        let k = format!("{}.{}", ht, name);
                        let d = *x != vb[f].1;
                        let hv = entry(&mut hidden, &k, || (0, 0));
                        hv.0 += 1;
                        if d {
                            hv.1 += 1;
                        }
                    }
                }
                // Every eye reads the same from a blind copy as from the truth: the eyes that
                // read (world, worldobs, mpc, rl) are not ported.
            }
            let tap = line[t as usize] == 1;
            sim.step(tap);
            if t % 200 == 0 {
                log(&format!("pass 2 tick {}", t));
            }
        }

        let mut stats = Map::new();
        for (k, ta) in &tally {
            stats.insert(
                k.clone(),
                json!({
                    "tell_n": ta.tell_n,
                    "deadly_n": ta.deadly_n,
                    "tell": ta.tell,
                    "tell_of": ta.tell_of,
                    "deadly": ta.deadly,
                    "deadly_of": ta.deadly_of,
                }),
            );
        }
        let mut hid = Map::new();
        for (k, (s, d)) in &hidden {
            hid.insert(k.clone(), json!([s, d]));
        }
        let mut present: Vec<&'static str> = Vec::new();
        for &c in &cls {
            if !present.contains(&c) {
                present.push(c);
            }
        }
        result(
            fails,
            json!({
                "scene": label,
                "ticks": end,
                "seconds": clock.elapsed().as_secs_f64(),
                "stats": Value::Object(stats),
                "hidden": Value::Object(hid),
                "present": present,
            }),
        )
    }

    fn combine(&self, results: &[Value]) -> Vec<String> {
        let mut fails: Vec<String> = Vec::new();
        let m = Self::sum(results);
        let mut present: Vec<String> = Vec::new();
        for r in results {
            if let Some(a) = r["present"].as_array() {
                for x in a {
                    let s = x.as_str().unwrap_or("").to_string();
                    if !present.contains(&s) {
                        present.push(s);
                    }
                }
            }
        }
        let filtered = !Self::only().is_empty();
        for t in Self::classes() {
            if !filtered && !present.iter().any(|p| p == t) && !Self::BASES.iter().any(|b| b.0 == t) {
                fails.push(format!(
                    "{}: no room scene holds it (add it to a room, or to SightCheck.BASES if it is only a base)",
                    t
                ));
            }
        }
        for (k, ta) in &m {
            for b in 0..Self::BOTS.len() {
                for (what, seen, of) in [("tell", ta.tell[b], ta.tell_of[b]), ("deadly", ta.deadly[b], ta.deadly_of[b])] {
                    if Self::verdict(seen, of) == "blind" && !Self::known(k, Self::BOTS[b], what) {
                        fails.push(format!(
                            "{} is blind to {} {}: sees {} of {}",
                            Self::BOTS[b],
                            k,
                            if what == "tell" { "tells" } else { "danger" },
                            seen,
                            of
                        ));
                    }
                }
            }
        }
        let mut hidden: Vec<(String, (i64, i64))> = Vec::new();
        for r in results {
            let Some(h) = r["hidden"].as_object() else { continue };
            for (k, v) in h {
                let hv = entry(&mut hidden, k, || (0, 0));
                hv.0 += i(&v[0]);
                hv.1 += i(&v[1]);
            }
        }
        for (k, (s, d)) in &hidden {
            if *d == 0 {
                fails.push(format!("blind_copy keeps the hidden draw {} (the same in two blind copies, {} looks)", k, s));
            }
        }
        fails
    }

    fn summary(&self, results: &[Value]) -> String {
        let mut m = Self::sum(results);
        let mut sb = String::new();
        sb.push_str(&format!(
            "{} rooms, {} tells and {} deadly looks over {} hazard classes",
            results.len(),
            m.iter().map(|e| e.1.tell_n).sum::<i64>(),
            m.iter().map(|e| e.1.deadly_n).sum::<i64>(),
            m.len()
        ));
        sb.push_str("\n      hazard            ");
        sb.push_str(&Self::BOTS.iter().map(|b| pad(b, 18)).collect::<String>());
        // OrderBy is a stable sort.
        m.sort_by(|a, b| culture_cmp(&a.0, &b.0));
        for (k, ta) in &m {
            sb.push_str("\n      ");
            sb.push_str(&pad(k, 18));
            for b in 0..Self::BOTS.len() {
                let cell = |what: &str, seen: i64, of: i64| -> String {
                    let v = Self::verdict(seen, of);
                    if v == "-" {
                        return "-".to_string();
                    }
                    let pct = format!("{}", 100 * seen / of);
                    if v == "blind" {
                        return if Self::known(k, Self::BOTS[b], what) { format!("gap{}", pct) } else { format!("BLIND{}", pct) };
                    }
                    pct
                };
                let s = format!(
                    "T{} D{}",
                    cell("tell", ta.tell[b], ta.tell_of[b]),
                    cell("deadly", ta.deadly[b], ta.deadly_of[b])
                );
                sb.push_str(&pad(&s, 18));
            }
        }
        sb
    }
}
