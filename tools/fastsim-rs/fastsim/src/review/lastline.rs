//! `rl review lastline --seed N [planner knobs] [--every 60] [--tail 40] [--before 600]`:
//! settles a fairness-judge `lost` death (no line found inside the judge's look-back). It plays
//! the judge's run of seed N (the same BlindPlanner and knobs as `rl review fair`) and keeps the
//! state every `every` ticks. Then, from the death backwards, SurvivalSearch (the oracle: the
//! true future) asks of each kept state whether any line lives to `tail` ticks past the death;
//! it goes back as far as `before` ticks before the death room's arrival. The first state that
//! has one is the last moment the bird could still live. What happened in the `every` ticks
//! after it says whose fault the death was: the warnings that came on screen then (the
//! hazards' tells), the walls drawn, the exit opening, and the bird's own taps. A warning that
//! came on screen less than a reaction time before that point, or nothing new at all on screen
//! while the line was lost to the bird's own taps, tell a room bug from play.
use sim::prelude::*;

use super::{configure, room_name};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::speed::Opts;

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

/// The warnings on screen now, one tuple each (x0, y0, x1, y1 in px, eta, dur, kind).
fn warns(sim: &GameSim) -> Vec<[i64; 7]> {
    let mut raw: Vec<i64> = Vec::new();
    sim.warnings(&mut raw);
    raw.chunks(7)
        .map(|w| {
            [
                w[0] / SimConfig::SUB,
                w[1] / SimConfig::SUB,
                w[2] / SimConfig::SUB,
                w[3] / SimConfig::SUB,
                w[4],
                w[5],
                w[6],
            ]
        })
        .collect()
}

fn wall(sim: &GameSim, side: i64) -> String {
    let mask = sim.wall_mask(side);
    (0..SimConfig::SLOT_COUNT).map(|k| if RoomRules::has_slot(mask, k) { '#' } else { '.' }).collect()
}

pub fn lastline(opts: &Opts, cap: i64) -> i32 {
    let seed = l(opts, "seed", 1);
    let every = l(opts, "every", 60).max(1);
    let tail = l(opts, "tail", 40);
    let before = l(opts, "before", 600);
    let mut sim = GameSim::new(seed);
    let mut bot = BlindPlanner::new(seed);
    println!("lastline seed {} [{}]", seed, configure(&mut bot, opts));
    let mut kept: Vec<(i64, GameSim)> = Vec::new();
    let mut taps: Vec<bool> = Vec::new();
    let mut entry = 0i64;
    while !sim.is_over() && (taps.len() as i64) < cap {
        let t = taps.len() as i64;
        if t % every == 0 {
            kept.push((t, sim.clone_deep()));
        }
        let room = sim.state.room_index;
        let tap = bot.decide(&sim);
        taps.push(tap);
        sim.step(tap);
        if sim.state.room_index != room {
            entry = t + 1;
        }
    }
    if !sim.is_over() {
        println!("alive at the cap");
        return 0;
    }
    let died = taps.len() as i64;
    println!(
        "died at tick {died}, score {}, room {} (arrived at tick {entry}, {} ticks before), cause {}",
        sim.state.score,
        room_name(&sim),
        died - entry,
        DeathCause::NAMES[sim.state.death_cause as usize]
    );
    let end = died + tail;
    let mut found: Option<usize> = None;
    for i in (0..kept.len()).rev() {
        let (t, s) = &kept[i];
        if *t < entry - before {
            break;
        }
        let mut ss = SurvivalSearch::new();
        let ok = ss.run(s, end - t);
        if ok {
            println!("  {:>6} ({:>5} before the death): a line lives", t, died - t);
        } else {
            // How far the best line got: dying long after this point is a later trap, dying
            // within a reaction time of it is one already set.
            println!(
                "  {:>6} ({:>5} before the death): no line; the best dies {} ticks on (tick {}, {} before the death)",
                t,
                died - t,
                ss.ticks_survived,
                t + ss.ticks_survived,
                died - t - ss.ticks_survived
            );
        }
        if ok {
            found = Some(i);
            break;
        }
    }
    let Some(i) = found else {
        println!("no line from any kept state back to {before} ticks before the arrival: trapped earlier");
        return 0;
    };
    let (t0, s0) = &kept[i];
    println!(
        "last line at tick {t0}: {} ticks before the death, {} after the arrival{}",
        died - t0,
        t0 - entry,
        if *t0 < entry { " (before the room: the portal or the room before)" } else { "" }
    );
    // What came in the next `every` ticks, as the bird played them.
    let mut c = s0.clone_deep();
    let mut seen = warns(&c);
    let side0 = if c.state.vx > 0 { 1 } else { 0 };
    println!(
        "  at it: bird x {} y {} vy {}; wall ahead {} ({}); behind {}; warnings {}",
        c.state.x / SimConfig::SUB,
        c.state.y / SimConfig::SUB,
        c.state.vy * 10 / SimConfig::SUB,
        wall(&c, side0),
        if side0 == 1 { "right" } else { "left" },
        wall(&c, 1 - side0),
        seen.len()
    );
    let stop = (t0 + every).min(died);
    let mut t = *t0;
    while t < stop && !c.is_over() {
        let tap = taps[t as usize];
        c.step(tap);
        t += 1;
        let now = warns(&c);
        for w in &now {
            if !seen.iter().any(|o| o[0] == w[0] && o[2] == w[2] && o[6] == w[6] && (o[1] - w[1]).abs() < 8) {
                println!(
                    "  {:>6} new warning: x {}..{} y {}..{} eta {} dur {} kind {} ({} ticks before the death)",
                    t,
                    w[0],
                    w[2],
                    w[1],
                    w[3],
                    w[4],
                    w[5],
                    w[6],
                    died - t
                );
            }
        }
        seen = now;
        for e in c.events.iter() {
            if *e == Event::BOUNCE || *e == Event::EXIT_OPEN || *e == Event::EXIT_PREVIEW || *e == Event::ROOM_CHANGE {
                let side = if c.state.vx > 0 { 1 } else { 0 };
                println!(
                    "  {:>6} event {}: wall ahead now {}, behind {}",
                    t,
                    match *e {
                        Event::BOUNCE => "bounce",
                        Event::EXIT_OPEN => "exit open",
                        Event::EXIT_PREVIEW => "exit ghost",
                        _ => "room change",
                    },
                    wall(&c, side),
                    wall(&c, 1 - side)
                );
            }
        }
        if tap {
            println!("  {:>6} tap (bird y {})", t, c.state.y / SimConfig::SUB);
        }
    }
    0
}
