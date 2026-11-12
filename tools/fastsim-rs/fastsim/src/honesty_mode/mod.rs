//! Port of tools/fastsim/Honesty.cs `run`: `fastsim-rs honesty plan|anchor|rooms|seeds`.
//! Does the BlindPlanner's plan depend on things that are not on screen?
//! (research/planner-review/01-honesty.md)
//!
//! plan: a real run is played by a BlindPlanner. Every `every` ticks the state is forked: one
//! hidden value is changed in the fork (nothing drawn changes), and two fresh planners with the
//! same own seed look once, one at the state and one at the fork. An honest planner makes the
//! same plan.
//!   --seeds n --cap ticks --every ticks --boss 1 (practice runs in the boss rooms)
//!   --room id (practice runs in the rooms whose id starts with it)
//!   --hideboss 0 --hidekeys 0 --ownanchor 0 (the fixes off / on)
//! anchor: how often the anchor a player can track from the walls is the room's own.
//! seeds: the seed scan (checks/honesty.rs, Honesty::seedscan).
//! rooms: practice runs per room, deaths per 100 points (to price a fix).
//!
//! `--threads` is not read: runs go on rayon's global pool (`--jobs N`). C# merges each run's
//! tally under a lock as the runs finish, so the room lists of `plan` (insertion order breaks
//! ties) can differ between C# runs with several threads; here they merge in run order (as C#
//! with `--threads 1`).
use std::collections::HashMap;
use std::sync::atomic::Ordering;

use rayon::prelude::*;
use sim::hazards::dart::State as DartState;
use sim::hazards::exit_key::Mode as KeyMode;
use sim::prelude::*;

use crate::bots::blind_planner::{BOSS_BLIND, HIDE_KEYS};
use crate::bots::BlindPlanner;
use crate::checks::honesty::Honesty;
use crate::review::{culture_cmp, room_name};
use crate::speed::Opts;
use crate::review::fixed;

/// One hidden change. Returns None when it does not apply to this state.
struct Change {
    name: &'static str,
    what: &'static str,
    make: fn(&GameSim, &BlindPlanner, &mut SimRng) -> Option<GameSim>,
}

fn boss_seed(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    if !sim.room.hazards.iter().any(|h| h.as_boss().map(|b| b.base.alive && b.down_at < 0).unwrap_or(false)) {
        return None;
    }
    let mut c = sim.clone_deep();
    for hz in c.room.hazards.iter_mut() {
        if let Hz::BossCrusher(bc) = hz {
            // The attack being told (or under way) stays: only the crusher's slam is re-read from the seed.
            let (mut k, mut keep) = (-1i64, -1i64);
            if bc.boss.phase == 1 && bc.boss.clock() >= 0 {
                k = bc.boss.clock() / BossCrusher::CYCLE;
                keep = bc.slam_of(k);
            }
            loop {
                bc.boss.seed = own.next_u32();
                if !(keep >= 0 && bc.slam_of(k) != keep) {
                    break;
                }
            }
            continue;
        }
        let Some(boss) = hz.as_boss_mut() else { continue };
        boss.seed = own.next_u32();
    }
    Some(c)
}

fn rng_world(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    let mut c = sim.clone_deep();
    c._rng = SimRng::new(own.next_u32());
    c._spine = SimRng::new(own.next_u32());
    c.room.rng_seed = own.next_u32();
    if c.state.plan_at != 0 {
        let at = c.state.plan_at;
        ExitPlanner::plan_room(&mut c, at);
    }
    Some(c)
}

fn exit_plan(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    if sim.state.plan_at == 0 || sim.state.exit_open || sim.state.exit_preview {
        return None;
    }
    let mut c = sim.clone_deep();
    let seed = c.room.rng_seed;
    c.room.rng_seed = own.next_u32();
    let at = c.state.plan_at;
    ExitPlanner::plan_room(&mut c, at);
    c.room.rng_seed = seed;
    Some(c)
}

fn anchor_shift(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    let mut c = sim.clone_deep();
    let lo = SimConfig::KILL_TOP + SimConfig::ARRIVAL_EDGE;
    let hi = SimConfig::KILL_BOTTOM - SimConfig::ARRIVAL_EDGE;
    let mut to = c.state.anchor_y + (if own.next_below(2) == 0 { 1 } else { -1 }) * SimConfig::SLOT_SIZE;
    if to < lo || to > hi {
        to = c.state.anchor_y - (to - c.state.anchor_y);
    }
    c.state.anchor_y = to;
    Some(c)
}

/// The anchor a player can know (tracked from the walls) in place of the room's.
fn anchor_tracked(sim: &GameSim, driver: &BlindPlanner, _: &mut SimRng) -> Option<GameSim> {
    if driver.anchor == sim.state.anchor_y {
        return None;
    }
    let mut c = sim.clone_deep();
    c.state.anchor_y = driver.anchor;
    Some(c)
}

fn stalactite_target(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    if !sim.room.hazards.iter().any(|h| matches!(h, Hz::Stalactite(s) if s.base.alive && s.gap_y != s.target_y)) {
        return None;
    }
    let mut c = sim.clone_deep();
    let mut changed = false;
    for hz in c.room.hazards.iter_mut() {
        let Hz::Stalactite(st) = hz else { continue };
        if st.gap_y == st.target_y {
            continue;
        }
        let dir = if st.target_y > st.gap_y { 1 } else { -1 };
        let to = G::clampi(
            st.gap_y + dir * (1 + own.next_below(Stalactite::REACH + Stalactite::MAX_STEP)),
            Stalactite::GAP_MIN,
            Stalactite::GAP_MAX,
        );
        if to == st.gap_y {
            continue;
        }
        changed |= to != st.target_y;
        st.target_y = to;
    }
    if changed {
        Some(c)
    } else {
        None
    }
}

/// A key chain: where the keys after the one on screen will appear.
fn key_chain(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    if !sim
        .room
        .hazards
        .iter()
        .any(|h| matches!(h, Hz::ExitKey(k) if k.base.alive && k.mode == KeyMode::CHAIN && k.got + 1 < k.count))
    {
        return None;
    }
    let mut c = sim.clone_deep();
    for hz in c.room.hazards.iter_mut() {
        let Hz::ExitKey(ek) = hz else { continue };
        if ek.mode != KeyMode::CHAIN {
            continue;
        }
        for i in (ek.got + 1)..ek.count {
            ek.chain_off[i as usize] =
                ExitKey::KEY_OFF_MIN + own.next_below(ExitKey::CHAIN_OFF_MAX - ExitKey::KEY_OFF_MIN + 1);
            ek.chain_d[i as usize] = ExitKey::CHAIN_D_MIN + own.next_below(ExitKey::CHAIN_D_MAX - ExitKey::CHAIN_D_MIN + 1);
        }
    }
    Some(c)
}

/// When an idle hunter dart next takes aim (nothing is drawn while it idles).
fn dart_idle(sim: &GameSim, _: &BlindPlanner, _own: &mut SimRng) -> Option<GameSim> {
    if !sim.room.hazards.iter().any(|h| matches!(h, Hz::Dart(d) if d.base.alive && d.state == DartState::IDLE)) {
        return None;
    }
    let mut c = sim.clone_deep();
    for hz in c.room.hazards.iter_mut() {
        if let Hz::Dart(d) = hz {
            if d.state == DartState::IDLE {
                d.since += 15;
            }
        }
    }
    Some(c)
}

/// A value the revive keeps (the room as entered): never read by a look.
fn entry_state(sim: &GameSim, _: &BlindPlanner, own: &mut SimRng) -> Option<GameSim> {
    // C# `_entry_rng == null`: it is set with the entry state.
    sim._entry_state?;
    let mut c = sim.clone_deep();
    c._entry_rng = SimRng::new(own.next_u32());
    c._entry_spine = SimRng::new(own.next_u32());
    Some(c)
}

const CHANGES: [Change; 9] = [
    Change {
        name: "rng_world",
        what: "the sim's RNG, the room's wall seed, the room spine and the planned exits (control: blind_copy replaces these)",
        make: rng_world,
    },
    Change { name: "exit_plan", what: "only the planned exit heights, before the ghost shows", make: exit_plan },
    Change { name: "entry_state", what: "the RNGs kept for a revive (control)", make: entry_state },
    Change {
        name: "stalactite_target",
        what: "where a sliding stalactite gap will stop (same side)",
        make: stalactite_target,
    },
    Change { name: "boss_seed", what: "a boss's seed: every attack after the one being told", make: boss_seed },
    Change { name: "anchor_shift", what: "state.anchor_y moved one slot (40 px)", make: anchor_shift },
    Change {
        name: "anchor_tracked",
        what: "state.anchor_y set to what a player can track from the walls (where the two differ)",
        make: anchor_tracked,
    },
    Change {
        name: "key_chain",
        what: "a key chain's later keys (each shows only when the one before is taken)",
        make: key_chain,
    },
    Change {
        name: "dart_idle",
        what: "an idle dart's timer moved 15 ticks (no countdown is drawn; gray: a rhythm can be learned)",
        make: dart_idle,
    },
];

fn o<'a>(opts: &'a Opts, k: &str, d: &'a str) -> &'a str {
    opts.get(k).map(|s| s.as_str()).unwrap_or(d)
}

fn plan_of(sim: &GameSim, own_seed: i64, opts: &Opts, driver: &BlindPlanner) -> (bool, Vec<bool>) {
    let mut p = BlindPlanner::new(own_seed);
    configure(&mut p, opts);
    // The fresh planner gets the driver's memory (what was seen before the fork).
    p.anchor = driver.anchor;
    p.skip_observe = true;
    let first = p.decide(&sim.clone_deep());
    (first, p.plan().iter().copied().collect())
}

fn configure(p: &mut BlindPlanner, opts: &Opts) {
    BOSS_BLIND.store(o(opts, "hideboss", "1") != "0", Ordering::Relaxed);
    HIDE_KEYS.store(o(opts, "hidekeys", "1") != "0", Ordering::Relaxed);
    p.own_anchor = o(opts, "ownanchor", "1") != "0";
}

/// C# Dictionary<string, long>: keys in first-insertion order.
#[derive(Default, Clone)]
struct Counts {
    list: Vec<(String, i64)>,
    at: HashMap<String, usize>,
}

impl Counts {
    fn add(&mut self, k: &str, n: i64) {
        match self.at.get(k) {
            Some(&i) => self.list[i].1 += n,
            None => {
                self.at.insert(k.to_string(), self.list.len());
                self.list.push((k.to_string(), n));
            }
        }
    }
}

#[derive(Default, Clone)]
struct Tally {
    forks: i64,
    differ: i64,
    first_tap: i64,
    early: i64,
    rooms: Counts,
}

fn seeds_check(opts: &Opts, seeds: i64, cap: i64) -> i32 {
    configure(&mut BlindPlanner::new(1), opts);
    let mut lines: Vec<String> = Vec::new();
    let bad = Honesty::seedscan(seeds, cap, &mut lines);
    for l in &lines {
        println!("{}", l);
    }
    if bad == 0 {
        0
    } else {
        1
    }
}

/// C# `{x,n}`: right-aligned in `n` characters (left-aligned for a negative `n`).
fn pad(s: impl ToString, n: i32) -> String {
    let s = s.to_string();
    if n < 0 {
        format!("{:<w$}", s, w = (-n) as usize)
    } else {
        format!("{:>w$}", s, w = n as usize)
    }
}

/// `honesty rooms --boss 1 | --room id`: practice runs, 20 points each: how many die, per room.
fn rooms(runs: &[(i64, i64)], opts: &Opts, cap: i64) -> i32 {
    let res: Vec<(String, bool, i64)> = runs
        .par_iter()
        .map(|&(seed, room)| {
            let mut sim = GameSim::with(seed, Seasons::NONE, room, "");
            let mut bot = BlindPlanner::new(seed);
            configure(&mut bot, opts);
            let mut t = 0;
            while t < cap && !sim.is_over() && sim.room.points < SimConfig::BOSS_POINTS {
                let tap = bot.decide(&sim);
                sim.step(tap);
                t += 1;
            }
            (sim.room.def().id.to_string(), sim.is_over(), sim.room.points)
        })
        .collect();
    println!(
        "honesty rooms [hideboss {} ownanchor {} hidekeys {}], {} points per run:",
        if BOSS_BLIND.load(Ordering::Relaxed) { 1 } else { 0 },
        o(opts, "ownanchor", "1"),
        if HIDE_KEYS.load(Ordering::Relaxed) { 1 } else { 0 },
        SimConfig::BOSS_POINTS
    );
    // GroupBy (first-appearance order), then OrderBy the key (a stable sort).
    let mut groups: Vec<(String, Vec<&(String, bool, i64)>)> = Vec::new();
    for r in &res {
        match groups.iter_mut().find(|g| g.0 == r.0) {
            Some(g) => g.1.push(r),
            None => groups.push((r.0.clone(), vec![r])),
        }
    }
    groups.sort_by(|a, b| culture_cmp(&a.0, &b.0));
    let per100 = |dead: i64, pts: i64| fixed(100.0 * dead as f64 / 1.max(pts) as f64, 3);
    for (key, g) in &groups {
        let dead = g.iter().filter(|r| r.1).count() as i64;
        let pts: i64 = g.iter().map(|r| r.2).sum();
        println!(
            "  {} {} deaths in {} runs, {} points = {} per 100",
            pad(key, -16),
            pad(dead, 4),
            pad(g.len(), 4),
            pad(pts, 6),
            per100(dead, pts)
        );
    }
    let dead = res.iter().filter(|r| r.1).count() as i64;
    let pts: i64 = res.iter().map(|r| r.2).sum();
    println!(
        "  all              {} deaths in {} runs, {} points = {} per 100",
        pad(dead, 4),
        pad(res.len(), 4),
        pad(pts, 6),
        per100(dead, pts)
    );
    0
}

/// One run's share of the plan / anchor tally (C# `local` and `lb`..`loff`).
struct Local {
    tally: Vec<Tally>,
    lb: i64,
    ls: i64,
    lnb: i64,
    lns: i64,
    loff: i64,
}

/// Honesty.run (the words after `honesty`; pos[0] = what).
pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let what = pos.first().map(|s| s.as_str()).unwrap_or("plan");
    let l = |k: &str, d: i64| -> i64 { opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d) };
    let seeds = l("seeds", 16);
    let cap = l("cap", 6000);
    let every = l("every", 23);
    let first = l("first", 0);
    let boss = l("boss", 0) != 0;
    let room_id = o(opts, "room", "").to_string();
    let mut runs: Vec<(i64, i64)> = Vec::new();
    for i in 1..=seeds {
        if boss {
            for &b in RoomCatalog::bosses() {
                runs.push((first + i, b));
            }
        } else if !room_id.is_empty() {
            for r in 0..RoomCatalog::all().len() {
                if RoomCatalog::all()[r].id.starts_with(room_id.as_str()) {
                    runs.push((first + i, r as i64));
                }
            }
        } else {
            runs.push((first + i, -1));
        }
    }
    if what == "seeds" {
        return seeds_check(opts, l("seeds", 3), l("cap", 900));
    }
    if what == "rooms" {
        return rooms(&runs, opts, cap);
    }
    let locals: Vec<Local> = runs
        .par_iter()
        .map(|&(seed, room)| {
            let mut sim = if room >= 0 { GameSim::with(seed, Seasons::NONE, room, "") } else { GameSim::new(seed) };
            let mut driver = BlindPlanner::new(seed);
            configure(&mut driver, opts);
            let mut own = SimRng::new(seed * 7919 + 13);
            let mut loc = Local { tally: vec![Tally::default(); CHANGES.len()], lb: 0, ls: 0, lnb: 0, lns: 0, loff: 0 };
            let mut t = 0i64;
            while t < cap && !sim.is_over() {
                let tap = driver.decide(&sim);
                if sim.events.contains(&Event::BOUNCE) && sim.state.started {
                    let near = !sim.state.exit_open && sim.points_to_exit() <= GameSim::EXIT_STEER;
                    loc.lb += 1;
                    if near {
                        loc.lnb += 1;
                    }
                    if driver.anchor == sim.state.anchor_y {
                        loc.ls += 1;
                        if near {
                            loc.lns += 1;
                        }
                    } else {
                        loc.loff += (driver.anchor - sim.state.anchor_y).abs() / SimConfig::SUB;
                    }
                }
                if what == "plan" && sim.state.started && sim.state.arrival_hold == 0 && t % every == 0 {
                    let ps = seed * 31 + t;
                    let mut base_plan: Option<(bool, Vec<bool>)> = None;
                    for (ci, ch) in CHANGES.iter().enumerate() {
                        let Some(fork) = (ch.make)(&sim, &driver, &mut own) else { continue };
                        if base_plan.is_none() {
                            base_plan = Some(plan_of(&sim, ps, opts, &driver));
                        }
                        let b = plan_of(&fork, ps, opts, &driver);
                        let a = base_plan.as_ref().unwrap();
                        let tl = &mut loc.tally[ci];
                        tl.forks += 1;
                        let mut at: i32 = -1;
                        if a.0 != b.0 {
                            at = 0;
                        } else {
                            let n = a.1.len().max(b.1.len());
                            let mut j = 0;
                            while j < n && at < 0 {
                                if (j < a.1.len() && a.1[j]) != (j < b.1.len() && b.1[j]) {
                                    at = j as i32 + 1;
                                }
                                j += 1;
                            }
                        }
                        if at < 0 {
                            continue;
                        }
                        tl.differ += 1;
                        if at == 0 {
                            tl.first_tap += 1;
                        }
                        if at < 4 {
                            tl.early += 1;
                        }
                        tl.rooms.add(&room_name(&sim), 1);
                    }
                }
                sim.step(tap);
                t += 1;
            }
            loc
        })
        .collect();
    let mut tally: Vec<Tally> = vec![Tally::default(); CHANGES.len()];
    let (mut bounces, mut same, mut near_bounces, mut near_same, mut off_px) = (0i64, 0i64, 0i64, 0i64, 0i64);
    for loc in &locals {
        bounces += loc.lb;
        same += loc.ls;
        near_bounces += loc.lnb;
        near_same += loc.lns;
        off_px += loc.loff;
        for (g, tl) in tally.iter_mut().zip(loc.tally.iter()) {
            g.forks += tl.forks;
            g.differ += tl.differ;
            g.first_tap += tl.first_tap;
            g.early += tl.early;
            for (id, n) in &tl.rooms.list {
                g.rooms.add(id, *n);
            }
        }
    }
    let setup = format!(
        "hideboss {} ownanchor {} hidekeys {}",
        if BOSS_BLIND.load(Ordering::Relaxed) { 1 } else { 0 },
        o(opts, "ownanchor", "1"),
        if HIDE_KEYS.load(Ordering::Relaxed) { 1 } else { 0 }
    );
    let kind = if boss {
        "practice, boss rooms".to_string()
    } else if !room_id.is_empty() {
        format!("practice, rooms {}*", room_id)
    } else {
        "full runs".to_string()
    };
    println!(
        "honesty {}: {} runs ({}), seeds {}..{}, cap {}, a fork every {} ticks [{}]",
        what,
        runs.len(),
        kind,
        first + 1,
        first + seeds,
        cap,
        every,
        setup
    );
    let p1 = |a: i64, b: i64| fixed(100.0 * a as f64 / 1.max(b) as f64, 1);
    println!(
        "  anchor: tracked == the room's at {}/{} bounces ({}%); within {} points of an exit {}/{} ({}%), elsewhere {}/{}; mean gap when off {} px",
        same,
        bounces,
        p1(same, bounces),
        GameSim::EXIT_STEER,
        near_same,
        near_bounces,
        p1(near_same, near_bounces),
        same - near_same,
        bounces - near_bounces,
        off_px / 1.max(bounces - same)
    );
    if what != "plan" {
        return 0;
    }
    println!("  change             forks   plan differs   first tap   in 4 ticks   rooms");
    for (ch, g) in CHANGES.iter().zip(tally.iter()) {
        // OrderByDescending (stable), Take(6).
        let mut rs: Vec<&(String, i64)> = g.rooms.list.iter().collect();
        rs.sort_by(|a, b| b.1.cmp(&a.1));
        let rooms = rs.iter().take(6).map(|kv| format!("{} {}", kv.0, kv.1)).collect::<Vec<_>>().join(", ");
        println!(
            "  {} {}   {} {}%   {}       {}        {}",
            pad(ch.name, -18),
            pad(g.forks, 5),
            pad(g.differ, 5),
            pad(p1(g.differ, g.forks), 5),
            pad(g.first_tap, 5),
            pad(g.early, 5),
            rooms
        );
    }
    for ch in CHANGES.iter() {
        println!("  {}: {}", ch.name, ch.what);
    }
    0
}
