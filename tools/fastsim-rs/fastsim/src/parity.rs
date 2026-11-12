//! Port of Program.cs `Parity`: replays tools/fastsim_parity.gd's recording and
//! reports the first tick where this sim differs from Godot's.
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Mutex;

use rayon::prelude::*;
use sim::prelude::*;

use crate::bots::{PlannerBot, SimBots, SurvivalSearch};
use crate::setups::{Reaction, Setups};

fn p64(s: &str) -> i64 {
    s.parse::<i64>().unwrap_or_else(|_| panic!("not a number: {s}"))
}

fn room_id(sim: &GameSim) -> &'static str {
    RoomCatalog::all()[sim.state.room_kind as usize].id
}

fn taps_text(inputs: &[u8]) -> String {
    inputs.iter().map(|&b| if b == 1 { '1' } else { '0' }).collect()
}

pub fn run(path: &str) -> i32 {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("cannot read {path}: {e}"));
    let lines: Vec<&str> = text.lines().map(|l| l.trim_end_matches('\r')).filter(|l| !l.is_empty()).collect();
    let fails = Mutex::new(Vec::<String>::new());
    let ticks = AtomicI64::new(0);
    lines.par_iter().for_each(|line| {
        let f: Vec<&str> = line.split(' ').collect();
        let name = f[1];
        if f[0] == "case" || f[0] == "csearch" || f[0] == "qsearch" {
            let fail = if f[0] == "case" { play_case(&f) } else { search_case(&f) };
            if let Some(fail) = fail {
                fails.lock().unwrap().push(format!("{} {} ({}): {}", f[0], name, f[2], fail));
            }
            let n = if f[0] == "case" { f[4].len() as i64 } else { p64(f[3]) };
            ticks.fetch_add(n, Ordering::Relaxed);
            return;
        }
        let (seed, season, practice) = (p64(f[2]), p64(f[3]), p64(f[4]));
        let tag = format!("{} {} seed {} season {}", f[0], name, seed, season);
        if f[0] == "run" {
            let actions = f[5].as_bytes();
            let sums: Vec<&str> = if f.len() > 6 && !f[6].is_empty() { f[6].split(',').collect() } else { Vec::new() };
            let mut sim = GameSim::with(seed, season, practice, "");
            let mut w = SimHash::SEED;
            let mut warns: Vec<i64> = Vec::new();
            for i in 0..actions.len() {
                let a = actions[i];
                if a == b'r' {
                    sim.revive();
                } else {
                    sim.step(a == b'1');
                }
                w = warn_mix(w, &sim, &mut warns);
                ticks.fetch_add(1, Ordering::Relaxed);
                if sim.checksum() != p64(sums[i]) {
                    fails.lock().unwrap().push(format!(
                        "{tag}: differs at action {i} ('{}'), tick {}, room {}",
                        a as char,
                        sim.state.tick,
                        room_id(&sim)
                    ));
                    return;
                }
            }
            if warns_differ(&f, w) {
                fails.lock().unwrap().push(format!("{tag}: the state matches but the warnings (Hazard.warnings) differ somewhere in the run"));
            }
        } else if f[0] == "search" {
            let n = p64(f[5]);
            let ok = f[6] == "1";
            let survived = p64(f[7]);
            let taps = f[8];
            let mut search = SurvivalSearch::new();
            let got_ok = search.run(&GameSim::with(seed, season, practice, ""), n);
            let got_taps = if got_ok { taps_text(&search.best_inputs) } else { "-".to_string() };
            if got_ok != ok || search.ticks_survived != survived || got_taps != taps {
                let at = common_prefix(&got_taps, taps);
                fails.lock().unwrap().push(format!(
                    "{tag}: search ok {got_ok}/{ok}, survived {}/{survived}, taps differ from {at}",
                    search.ticks_survived
                ));
            }
        }
    });
    let mut fails = fails.into_inner().unwrap();
    fails.sort();
    for m in &fails {
        println!("  DIFF {m}");
    }
    println!(
        "parity: {} of {} cases match ({} ticks replayed)",
        lines.len() - fails.len(),
        lines.len(),
        ticks.load(Ordering::Relaxed)
    );
    if fails.is_empty() { 0 } else { 1 }
}

fn common_prefix(a: &str, b: &str) -> usize {
    a.bytes().zip(b.bytes()).take_while(|(x, y)| x == y).count()
}

fn variant_of(s: &str) -> &str {
    if s == "-" { "" } else { s }
}

/// A sim from a `case` setup (tools/fastsim_parity.gd setup()).
pub fn setup(text: &str) -> GameSim {
    let f: Vec<&str> = text.split(':').collect();
    let variant = variant_of(f[f.len() - 1]);
    match f[0] {
        "p" => GameSim::with(p64(f[1]), p64(f[2]), p64(f[3]), variant),
        "a" => Reaction::arrival(p64(f[1]), p64(f[3]), variant_of(f[2])),
        "r" => Setups::revived(p64(f[1]), p64(f[2]), f[3], p64(f[4]), p64(f[5]), p64(f[6])),
        "cr" => Setups::crawl_revived(p64(f[1]), p64(f[2]), f[3], p64(f[4]), p64(f[5])),
        "gr" => Setups::gates_revived(p64(f[1]), f[2] == "1", p64(f[3]), p64(f[4]), f[5]),
        "ir" => Setups::isles_revived(f[1], p64(f[2]), f[3], p64(f[4]), f[5]),
        "n" => {
            let mut sim = Setups::practice(f[1], p64(f[2]), variant_of(f[3]));
            sim.state.score += p64(f[4]);
            sim
        }
        "b" => {
            let mut sim = GameSim::with(p64(f[1]), p64(f[2]), -1, "");
            sim.step(true);
            sim.state.score = p64(f[3]);
            sim._go_through(1, ExitKind::NORMAL, 320 * SimConfig::SUB);
            sim
        }
        _ => panic!("unknown setup {text}"),
    }
}

/// Replays a `case` line; with a bot driver the Rust bot must also choose
/// every tap itself. None when it matches, else where it differs.
/// Every tick's warnings mixed into one number (tools/fastsim_parity.gd, _warn_mix).
fn warn_mix(w: i64, sim: &GameSim, warns: &mut Vec<i64>) -> i64 {
    sim.warnings(warns);
    let mut out_ = SimHash::mix(w, warns.len() as i64);
    for &v in warns.iter() {
        out_ = SimHash::mix(out_, v);
    }
    out_
}

/// True when the line ends in "w:<n>" (the recorded warnings) and `w` is another number.
fn warns_differ(f: &[&str], w: i64) -> bool {
    match f.last() {
        Some(last) if last.starts_with("w:") => p64(&last[2..]) != w,
        _ => false,
    }
}

fn play_case(f: &[&str]) -> Option<String> {
    let mut sim = setup(f[2]);
    let (driver, actions) = (f[3], f[4].as_bytes());
    let sums: Vec<&str> = if f.len() > 5 && !f[5].is_empty() { f[5].split(',').collect() } else { Vec::new() };
    let d: Vec<&str> = driver.split(':').collect();
    let mut gap = SimRng::new(7);
    let mut tapper = if d[0] == "tap" { Some(SimRng::new(p64(d[1]))) } else { None };
    let mut planner = if d[0] == "planner" { Some(PlannerBot::new(p64(d[1]), p64(d[2]), p64(d[3]))) } else { None };
    let hold = if d[0] == "planner" { p64(d[4]) } else { 0 };
    let y0 = sim.state.y;
    let mut n = 0;
    let mut w = SimHash::SEED;
    let mut warns: Vec<i64> = Vec::new();
    for i in 0..actions.len() {
        let a = actions[i];
        if driver != "replay" {
            let want = if d[0] == "gap" {
                if sim.is_over() {
                    b'r'
                } else if SimBots::gap_seeker(&sim, &mut gap) {
                    b'1'
                } else {
                    b'0'
                }
            } else if d[0] == "tap" {
                if SimBots::random_tapper(&sim, tapper.as_mut().unwrap(), 12) { b'1' } else { b'0' }
            } else if n < hold {
                let g = sim.room.gravity;
                if (sim.state.y - y0) * g > 0 && sim.state.vy * g >= 0 { b'1' } else { b'0' }
            } else if planner.as_mut().unwrap().decide(&sim) {
                b'1'
            } else {
                b'0'
            };
            if want != a {
                return Some(format!(
                    "the {} bot chose '{}', not '{}', at action {i} (tick {})",
                    d[0], want as char, a as char, sim.state.tick
                ));
            }
        }
        if a == b'r' {
            sim.revive();
        } else {
            sim.step(a == b'1');
            n += 1;
        }
        w = warn_mix(w, &sim, &mut warns);
        if sim.checksum() != p64(sums[i]) {
            return Some(format!(
                "differs at action {i} ('{}'), tick {}, room {}",
                a as char,
                sim.state.tick,
                room_id(&sim)
            ));
        }
    }
    if warns_differ(f, w) {
        return Some("the state matches but the warnings (Hazard.warnings) differ somewhere in the case".into());
    }
    // The bot must also stop where the GDScript one stopped.
    if d[0] == "gap" && (if sim.is_over() { sim.can_revive() } else { sim.state.tick < 1500 }) {
        return Some("the gap run ended early".into());
    }
    if d[0] == "planner" && !sim.is_over() && n < hold + p64(d[5]) {
        return Some("the planner run ended early".into());
    }
    if d[0] == "tap" && !sim.is_over() && sim.state.tick < 20000 {
        return Some("the tapper run ended early".into());
    }
    None
}

fn search_case(f: &[&str]) -> Option<String> {
    let n = p64(f[3]);
    let ok = f[4] == "1";
    let survived = p64(f[5]);
    let taps = f[6];
    let mut search = SurvivalSearch::new();
    let start = setup(f[2]);
    let got_ok = if f[0] == "qsearch" { search.run_quick(&start, n) } else { search.run(&start, n) };
    let got_taps = if got_ok { taps_text(&search.best_inputs) } else { "-".to_string() };
    if got_ok == ok && search.ticks_survived == survived && got_taps == taps {
        return None;
    }
    let at = common_prefix(&got_taps, taps);
    Some(format!(
        "search ok {got_ok}/{ok}, survived {}/{survived}, taps differ from {at}",
        search.ticks_survived
    ))
}
